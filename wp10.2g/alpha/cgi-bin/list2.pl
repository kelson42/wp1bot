#!/usr/bin/perl

use strict;
use Encode;
use URI::Escape;

# WP 1.0 bot - second generation
# CGI to display table of ratings information

require 'read_conf.pl';
our $Opts = read_conf();

require 'database_www.pl';
require 'layout.pl';
require 'init_cache.pl';

require Mediawiki::API;
my $api = new Mediawiki::API;
$api->debug_level(0); # no output at all 
$api->base_url('http://en.wikipedia.org/w/api.php');

require CGI;
require CGI::Carp; 
CGI::Carp->import('fatalsToBrowser');

require DBI;
require POSIX;
POSIX->import('strftime');

my $cacheFile = init_cache();
my $cacheMem = {};

my $cgi = new CGI;
my %param = %{$cgi->Vars()};

if ( $param{'limit'} > 500 ) { 
  $param{'limit'} = 500;
}

my $p;
foreach $p ( keys %param ) { 
  $param{$p} =~ s/^\s*//;
  $param{$p} =~ s/\s*$//;
}

my $proj = $param{'project'} || $ARGV[0];

our $dbh = db_connect($Opts);

print CGI::header(-type=>'text/html', -charset=>'utf-8');      

layout_header("Article lists");

my $projects = list_projects();
query_form(\%param, $projects);

if ( ! defined $param{'entry'} ) { 
  ratings_table(\%param, $projects);
}

layout_footer();

###########################################################################
###########################################################################

sub ratings_table { 
  my $params = shift;
  my $projects = shift;

  my $p;
  foreach $p ( ( 'importance', 'importanceb', 'quality', 'qualityb' ) ) { 
    if ( (defined $params->{$p}) 
         && ! ($params->{$p} =~/^\s*$/ )
         && ! ($params->{$p} =~ /-Class$/)) { 
      $params->{$p} .= "-Class";
    }
  }

  if (($params->{'intersect'} eq 'on') && 
      ($params->{'projecta'} ne $params->{'projectb'})) { 
		ratings_table_intersect($params);
		return;
  } 
	
  my $project = $params->{'projecta'};
#  return if ( ! defined $project);

#  if ( ! defined $projects->{$project}) { 
#    print "Project '$project' not available\n";
#    return;
#  }
	
  my $limit = $params->{'limit'} || 20;
  my $offset = $params->{'offset'} || 0;
  if ( $offset > 0 ) { $offset --; }

  my $query = "SELECT * FROM ratings WHERE";
  my $queryc = "SELECT count(r_article) FROM ratings WHERE";
  my @qparam;
  my @qparamc;

  if ( defined $project && $project =~ /\w|\d/ ) { 
    if ( defined $projects->{$project} ) { 
      $query .= " r_project = ?";
      $queryc .= " r_project = ?";
      push @qparam, $project;
      push @qparamc, $project;
    } else { 
      print "Project '$project' is not in the database<br/>\n";
      return;
    }
  }

  my $quality = $params->{'quality'};

  # First, make sure quality is defined and has some alphanumeric 
  # character in it
  if ( defined $quality && $quality =~ /\w|\d/) {

    # Quality 'Assessed' is a magic word that means "not unassessed".
    # This is required for certain links from table.pl
    if ( $quality eq 'Assessed' ) { 
      $query .= " AND NOT r_quality = 'Unassessed-Class'";
      $queryc .= " AND NOT r_quality = 'Unassessed-Class'";
    } else { 
      $query .= " AND r_quality = ?";
      $queryc .= " AND r_quality = ?";
      push @qparam, $quality;
      push @qparamc, $quality;
    }
  }

  my $pagename = $params->{'pagename'};

  if ( defined $pagename and $pagename =~ /\w|\d/ ) { 
    if ( $params->{'pagenameWC'} eq 'on' ) { 
      $pagename = '%' . $pagename . '%';
      $query .= " AND r_article like ?";
      $queryc .= " AND r_article like ?";
      push @qparam, $pagename;
      push @qparamc, $pagename;
    } else { 
      $query .= " AND r_article = ?";
      $queryc .= " AND r_article = ?";
      push @qparam, $pagename;
      push @qparamc, $pagename;
    }
  }


  my $importance =  $params->{'importance'};
  if ( defined $importance && $importance =~ /\w|\d/) {
    $query .= " AND r_importance = ?";
    $queryc .= " AND r_importance = ?";
    push @qparam, $importance;
    push @qparamc, $importance;
  }

  $query .= " LIMIT ?";
  push @qparam, $limit;

  $query .= " OFFSET ?";
  push @qparam, $offset;

  # clean up the SQL for edge cases 
  $query =~ s/WHERE AND/WHERE /;
  $queryc =~ s/WHERE AND/WHERE /;

  $query =~ s/WHERE LIMIT/LIMIT/;
  $queryc =~ s/WHERE LIMIT/LIMIT/;

  print "Q: $query<br/>\n";
  print join "<br/>", @qparam;

  my $sthcount = $dbh->prepare($queryc);
  $sthcount->execute(@qparamc);
  	
  my @row = $sthcount->fetchrow_array() ;
  my $total = $row[0];
  
  print "<div class=\"navbox\">\n";
  print_header_text($project);
  print "</div>\n";

  print "<p><b>Total results: " . $total 
        . "</b>.<br/> Displaying up to $limit results beginning with #" 
        . ($offset +1) . "</p><hr/>\n";

  my $sth = $dbh->prepare($query);
  my $c = $sth->execute(@qparam);
  my $i = $offset;

  print "<table class=\"wikitable\">\n";
  while ( @row = $sth->fetchrow_array ) {
    $i++;

    print "<tr><td>$i</td>\n";
    print "    <td>" . $row[0] . "</td>\n";
    print "    <td>" . $row[1] . "</td>\n";
    print "    " . get_cached_td_background($row[2]) . "\n";
    print "    <td>" . $row[3] . "</td>\n";
    print "    " . get_cached_td_background($row[4]) . "\n";
    print "    <td>" . $row[5] . "</td>\n";
    print "</tr>\n";
  }
  print "</table>\n";
	# For display purposes - whether we use a pipe between "previous" and "next"
	# depends on whether "previous" is defined or not 
	my $prev = 0;
  if (($offset - $limit + 1) > 0)
  {
    my $newURL = $ENV{"SCRIPT_URI"}
                      . "?projecta="   . uri_escape($project)
                      . "&quality="    . uri_escape($quality)
                      . "&importance=" . uri_escape($importance)
                      . "&limit="      . $limit
		      . "&offset=" . ($offset - $limit + 1);	  
		
		print "<a href=\"" . $newURL . "\">Previous $limit entries</a>";
	    $prev = 1;
	}
	
  if ($limit + $offset < $total)
  {
	  if ($prev == 1)
	  {
		  print " | ";
	  }
	  my $newURL = $ENV{"SCRIPT_URI"}
                     . "?projecta=" . uri_escape($project)
                     . "&quality=" . uri_escape($quality)
                     . "&importance=" . uri_escape($importance)
                     . "&limit=" . $limit
                     . "&offset=" . ($limit + $offset + 1);	  

	  print "<a href=\"" . $newURL . "\">Next $limit entries</a>";
  }
  print "\n";
}
  

###########################################################################

sub ratings_table_intersect { 
  my $params = shift;

  my $projecta = $params->{'projecta'};

  return if ( ! defined $projecta);

  my $projectb = $params->{'projectb'};


  return if ( ! defined $projectb);

  if ( ! defined $projects->{$projecta}) { 
    print "Project '$projecta' not available\n";
    return;
  }

  if ( ! defined $projects->{$projectb}) { 
    print "Project '$projectb' not available\n";
    return;
  }

  my $limit = $params->{'limit'} || 10;
  if ( $limit > 500 ) { $limit = 500;}

  my $offset = $params->{'offset'} || 0;

  if ( $offset > 0 ) { $offset --; }


  my $query = "SELECT ra.r_article, ra.r_quality, ra.r_importance, rb.r_quality, rb.r_importance ". 
              "  FROM ratings as ra join ratings as rb on rb.r_article = ra.r_article" . 
              " WHERE ra.r_project = ? AND rb.r_project = ?";
  my $queryc = "SELECT count(ra.r_article) FROM ratings as ra join ratings as rb on rb.r_article = ra.r_article" . 
              " WHERE ra.r_project = ? AND rb.r_project = ?";

  my @qparam = ($projecta, $projectb);
  my @qparamc = ($projecta, $projectb);

  my $quality = $params->{'quality'};
  my $qualityb = $params->{'qualityb'};

  if ( defined $quality && $quality =~ /\w|\d/) {
    $query .= " AND ra.r_quality = ?";
    $queryc .= " AND ra.r_quality = ?";
    push @qparam, $quality;
    push @qparamc, $quality;
  }

  my $importance =  $params->{'importance'};
  my $importanceb =  $params->{'importanceb'};

  if ( defined $importance && $importance =~ /\w|\d/) {
    $query .= " AND ra.r_importance = ?";
    $queryc .= " AND ra.r_importance = ?";
    push @qparam, $importance;
    push @qparamc, $importance;
  }

  if ( defined $param{'diffonly'} ) { 
    $query .= " AND NOT ra.r_quality = rb.r_quality";
    $queryc .= " AND NOT ra.r_quality = rb.r_quality";
  }

  $query .= " LIMIT ?";
  push @qparam, $limit;

  $query .= " OFFSET ?";
  push @qparam, $offset;

  my $sthcount = $dbh->prepare($queryc);
  $sthcount->execute(@qparamc);
  my @row = $sthcount->fetchrow_array()	;

  print "<div class=\"navbox\">\n";
  print_header_text($projecta);
  print "<br />";
  print_header_text($projectb);
  print "</div>\n";

  my $total = $row[0];
  print "<p><b>Total results: " . $total
        . "</b>.<br/> Displaying up to $limit results beginning with #" 
        . ($offset +1) . "</p><hr/>\n";


  my $sth = $dbh->prepare($query);
  my $c = $sth->execute(@qparam);
  my $i = $offset;

  print << "HERE";
<table class="wikitable">
<tr>
  <td><b>Result</b></td>
  <td><b>Article</b></td>
  <td colspan="2"><b>$projecta</b></td>
  <td colspan="2"><b>$projectb</b></td>
</tr>
HERE
     
  while ( @row = $sth->fetchrow_array ) {
    $i++;

     print "<tr><td>$i</td>\n";
    print "    <td>" . $row[0] . "</td>\n";
    print "    " . get_cached_td_background($row[1]) . "\n";
    print "    " . get_cached_td_background($row[2]) . "\n";
    print "    " . get_cached_td_background($row[3]) . "\n";
    print "    " . get_cached_td_background($row[4]) . "\n";
    print "</tr>\n";


  }
  print "</table>\n";
	# For display purposes - whether we use a pipe between "previous" and "next"
	# depends on whether "previous" is defined or not 
	my $prev = 0;
	if (($offset - $limit + 1) > 0)
	{
	  my $newURL = $ENV{"SCRIPT_URI"}
                     . "?projecta="    . uri_escape($projecta)
                     . "&quality="     . uri_escape($quality)
                     . "&importance="  . uri_escape($importance)
                     . "&intersect=on"
                     . "&projectb="    . uri_escape($projectb)
                     . "&qualityb="    . uri_escape($qualityb)
                     . "&importanceb=" . uri_escape($importanceb)
                     . "&limit=" .    $limit
                     . "&offset=" . ($offset - $limit + 1);	  
		
		print "<a href=\"" . $newURL . "\">Previous $limit entries</a>";
	    $prev = 1;
	}
	
	if ($limit + $offset < $total)
	{
		if ($prev == 1)
		{
			print " | ";
		}
		my $newURL = $ENV{"SCRIPT_URI"}
		            . "?projecta="   . uri_escape($projecta)
                            . "&quality="    . uri_escape($quality)
                            . "&importance=" . uri_escape($importance)
                            . "&intersect=on"
                            . "&projectb="   . uri_escape($projectb)
                            . "&qualityb="   . uri_escape($qualityb)
                            . "&importanceb=" . uri_escape($importanceb)
                            . "&limit="     . $limit
                            . "&offset=" . ($limit + $offset + 1);	  
		
		print "<a href=\"" . $newURL . "\">Next $limit entries</a>";
	}
	print "\n";
	
}

###########################################################################

sub list_projects { 
  my @row;
  my $projects = {};

  my $sth = $dbh->prepare("SELECT p_project FROM projects");
  $sth->execute();

  while ( @row = $sth->fetchrow_array ) { 
    $projects->{$row[0]} = 1;
  }
  return $projects;
}


sub query_form {
  my $params = shift;

  my $projecta = $params->{'projecta'} || '';
  my $projectb = $params->{'projectb'} || '';

  my $quality = $params->{'quality'} || "";
  my $importance = $params->{'importance'} || "";
  my $qualityb = $params->{'qualityb'} || "";
  my $importanceb = $params->{'importanceb'} || "";
  my $limit = $params->{'limit'} || "20";
  my $offset = $params->{'offset'} || "1";
  my $intersect = $params->{'intersect'} || "";
  my $pagename = $params->{'pagename'} || "";
  my $pagenameWC = $params->{'pagenameWC'} || "";

  my $intersect_checked = "";
  if ( $intersect eq 'on' ) { 
    $intersect_checked = "checked=\"yes\" ";
  }

  my $pagename_wc_checked = "";
  if ( $pagenameWC eq 'on' ) { 
    $pagename_wc_checked = "checked=\"yes\" ";
  }


  print << "HERE";
<form>
<table class="mainform">
<tr><td><b>First project:</b></td></tr>
<tr><td><table class="subform">
  <tr><td>Project name</td>
      <td><input type="text" value="$projecta" name="projecta"/></td></tr>
  <tr><td>Page name</td>
      <td><input type="text" value="$pagename" name="pagename"/></td></tr>
  <tr><td></td>
      <td><input type="checkbox" $pagename_wc_checked  name="pagenameWC" />	
          Use this name as a wildcard</td></tr>
  <tr><td>Quality</td>
      <td><input type="text" value="$quality" name="quality"/></td></tr>
  <tr><td>Importance</td>
      <td><input type=\"text\" value="$importance" name="importance"/></td></tr>
   <tr><td colspan="2">Note: leave any field blank to 
                       select all values.</td></tr>
  </table>
</td></tr>
<tr><td><b>Specify second project</b>
        <input type="checkbox" $intersect_checked  name="intersect" 
         rel="secondproj"/>	
</td></tr>
<tr><td><table class=\"subform\" rel="secondproj">
  <tr><td>Project name</td>
      <td><input type="text" value="$projectb" name="projectb"/></td></tr>
  <tr><td>Quality</td>
      <td><input type="text" value="$qualityb" name="qualityb"/></td></tr>
  <tr><td>Importance</td>
      <td><input type=\"text\" value="$importanceb" name="importanceb"/>
      </td></tr>
HERE

  print "<tr><td colspan=\"2\"><input type=\"checkbox\" name=\"diffonly\" ";
  if ( defined $param{'diffonly'} ) {
    print "checked=\"checked\" ";
  }
  print "> Show only rows where quality ratings differ</input></td></tr>\n";

  print "</table></td></tr>\n";
  print << "HERE";
  <tr><td><b>Output options</b></td></tr>
  <tr><td><table class="subform">
  <tr><td>Results per page</td>
      <td><input type="text" value="$limit" name="limit"/></td></tr>
  <tr><td>Start with result #</td>
      <td><input type="text" value="$offset" name="offset"/></td></tr>
  <tr>
  <td colspan="2" style="text-align: center;">
    <input type="submit" value="Make list"/>
  </td></tr>
  </table>
  </td></tr></table></form>
  <hr/>
HERE

}

sub get_cached_td_background { 
  my $class = shift;

  if ( defined $cacheMem->{$class} ) { 
    print " <!-- hit $class in memory cache --> ";
    return $cacheMem->{$class};
  }

  my $key = "CLASS:" . $class;
  my $data;

  if ( $cacheFile->exists($key) ) { 
     print " <!-- hit $class in file cache, expires " 
           . strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($cacheFile->expiry($key)))
           . " --> ";
    $data = $cacheFile->get($key);
    $cacheMem->{$class} = $data;
    return $data;
  }
 
  $data = get_td_background($class);
  
  $cacheFile->set($key, $data, '12 hours');
  $cacheMem->{$class} = $data;
  return $data;
}


sub get_td_background { 
  my $class = shift;
  my $r =  $api->parse('{{' . $class . '}}');
  my $t = $r->{'text'};

  $t =~ s/\|.*//s;
  $t =~ s!^<p>!!;
  $class =~ s/-Class//;
  $t = "<td $t><b>$class</b></td>";

  return $t;
}

sub get_link_from_api { 
	my $text = shift;
	my $r =  $api->parse($text);
	my $t = $r->{'text'};

	# TODO: internationalize this bare URL
	my $baseURL = "http://en.wikipedia.org";
	$t =~ s!^<p>!!;
	my @t = split('</p>',$t);
	$t = @t[0];
	
    @t = split('"',$t,2);
    $t = @t[0] . "\"" . $baseURL .  @t[1];
	
	return $t;
}

sub print_header_text {
	my $project = shift;
	my ($timestamp, $wikipage, $parent, $shortname);
	my $tableURL = $ENV{"SCRIPT_URI"};
	my @t = split('list2.pl',$tableURL);
	$tableURL = @t[0];
	$tableURL = $tableURL . "table.pl?project=" . $project;

	($project, $timestamp, $wikipage, $parent, $shortname) = 
		get_project_data($project);
	if ( ! defined $wikipage) 
	{
		print "Data for $project "; 	
	}
	elsif ( ! defined $shortname) 
	{
		print "Data for " . get_link_from_api("[[$wikipage]]") . " "; 
	}
	else
	{
		print "Data for " . get_link_from_api("[[$wikipage|$shortname]]") . " "; 		
	}
	print "(<b>lists</b> \| <a href=\"" . $tableURL . "\">summary table</a>)\n";
	
}
