#!/usr/bin/perl

use strict;
use Encode;

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

my $proj = $param{'project'} || $ARGV[0];

our $dbh = db_connect($Opts);

print CGI::header(-type=>'text/html', -charset=>'utf-8');      

layout_header("Query article assessment data");

my $projects = {};
query_form(\%param);
ratings_table(\%param);
layout_footer();

###########################################################################
###########################################################################

sub ratings_table { 
  my $params = shift;

  if ( $params->{'intersect'} eq 'on' ) { 
    ratings_table_intersect($params);
    return;
  } 

  my $project = $params->{'projecta'};
  return if ( ! defined $project);

  if ( ! defined $projects->{$project}) { 
    print "Project '$project' not available\n";
    return;
  }
	
  my $limit = $params->{'limit'} || 20;
  my $offset = $params->{'offset'} || 0;
  if ( $offset > 0 ) { $offset --; }

  my $query = "SELECT * FROM ratings WHERE r_project = ?";
  my $queryc = "SELECT count(r_article) FROM ratings WHERE r_project = ?";
  my @qparam = ($project);
  my @qparamc = ($project);

  my $quality = $params->{'quality'};

  # FIXME: What does this code do?
  if ( defined $quality && $quality =~ /\w|\d/) {
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
  my $sthcount = $dbh->prepare($queryc);
  $sthcount->execute(@qparamc);
  	
  my @row = $sthcount->fetchrow_array() ;
  my $total = $row[0];
  
  print_header_text($project);

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
		my $newURL = $ENV{"SCRIPT_URI"};
		$newURL = $newURL . "?projecta=" . $project;
		$newURL = $newURL . "&quality=" . $quality;
		$newURL = $newURL . "&importance=" . $importance;
		$newURL = $newURL . "&limit=" . $limit;	  
		$newURL = $newURL . "&offset=" . ($offset - $limit + 1);	  
		
		print "<a href=\"" . $newURL . "\">Previous $limit entries</a>";
	    $prev = 1;
	}
	
  if ($limit + $offset < $total)
  {
	  if ($prev == 1)
	  {
		  print " | ";
	  }
	  my $newURL = $ENV{"SCRIPT_URI"};
	  $newURL = $newURL . "?projecta=" . $project;
	  $newURL = $newURL . "&quality=" . $quality;
	  $newURL = $newURL . "&importance=" . $importance;
	  $newURL = $newURL . "&limit=" . $limit;	  
	  $newURL = $newURL . "&offset=" . ($limit + $offset + 1);	  

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
		my $newURL = $ENV{"SCRIPT_URI"};
		$newURL = $newURL . "?projecta=" . $projecta;
		$newURL = $newURL . "&quality=" . $quality;
		$newURL = $newURL . "&importance=" . $importance;
		$newURL = $newURL . "&intersect=on";
		$newURL = $newURL . "&projectb=" . $projectb;
		$newURL = $newURL . "&qualityb=" . $qualityb;
		$newURL = $newURL . "&importanceb=" . $importanceb;		
		$newURL = $newURL . "&limit=" . $limit;	  
		$newURL = $newURL . "&offset=" . ($offset - $limit + 1);	  
		
		print "<a href=\"" . $newURL . "\">Previous $limit entries</a>";
	    $prev = 1;
	}
	
	if ($limit + $offset < $total)
	{
		if ($prev == 1)
		{
			print " | ";
		}
		my $newURL = $ENV{"SCRIPT_URI"};
		$newURL = $newURL . "?projecta=" . $projecta;
		$newURL = $newURL . "&quality=" . $quality;
		$newURL = $newURL . "&importance=" . $importance;
		$newURL = $newURL . "&intersect=on";
		$newURL = $newURL . "&projectb=" . $projectb;
		$newURL = $newURL . "&qualityb=" . $qualityb;
		$newURL = $newURL . "&importanceb=" . $importanceb;		
		$newURL = $newURL . "&limit=" . $limit;	  
		$newURL = $newURL . "&offset=" . ($limit + $offset + 1);	  
		
		print "<a href=\"" . $newURL . "\">Next $limit entries</a>";
	}
	print "\n";
	
}

###########################################################################

sub query_form {
  my $params = shift;

  my $projecta = $params->{'projecta'} || 'Mathematics';
  my $projectb = $params->{'projectb'} || 'Computer science';

  my @row;

  my $sth = $dbh->prepare("SELECT p_project FROM projects");
  $sth->execute();

  while ( @row = $sth->fetchrow_array ) { 
    $projects->{$row[0]} = 1;
  }

  my $quality = $params->{'quality'} || "";
  my $importance = $params->{'importance'} || "";
  my $qualityb = $params->{'qualityb'} || "";
  my $importanceb = $params->{'importanceb'} || "";
  my $limit = $params->{'limit'} || "20";
  my $offset = $params->{'offset'} || "1";
  my $intersect = $params->{'intersect'} || "";

  print << "HERE";
<form>
<table class="mainform">
<tr><td><b>First project:</b></td></tr>
<tr><td><table class="subform">
  <tr><td>Project name</td>
  <td><select name="projecta">
HERE

  my $p;
  foreach $p ( sort { $a cmp $b} keys %$projects) { 
    if ( $p eq $projecta ) { 
      print "      <option value=\"" . $p 
          . "\" selected>" . $p ."</option>\n";
    } else { 
      print "      <option value=\"" . $p . "\">" . $p ."</option>\n";
    }
  }
  print "</select></td></tr>\n";

  my $intersect_checked = "";
  if ( $params->{'intersect'} eq 'on' ) { 
    $intersect_checked = "checked=\"yes\" ";
  }

  print << "HERE";
  <tr><td>Quality</td>
      <td><input type="text" value="$quality" name="quality"/></td></tr>
  <tr><td>Importance</td>
      <td><input type=\"text\" value="$importance" name="importance"/></td></tr>
   <tr><td colspan="2">Note: leave quality or importance blank to 
                       select all values.</td></tr>
  </table>
</td></tr>
<tr><td><b>Specify second project</b>
        <input type="checkbox" $intersect_checked  name="intersect" 
         rel="secondproj"/>	
</td></tr>
<tr><td><table class=\"subform\" rel="secondproj">
<tr><td colspan="2">
<tr><td>Project name</td>
    <td><select name="projectb">
HERE

  my $p;
  foreach $p ( sort { $a cmp $b} keys %$projects) { 
    if ( $p eq $projectb ) { 
      print "      <option value=\"" . $p . "\" selected>" 
          . $p ."</option>\n";
    } else { 
      print "      <option value=\"" . $p . "\">" . $p ."</option>\n";
    }
  }

  print << "HERE";
    </select></td></tr>
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
	my ($timestamp, $wikipage, $parent);
	my $tableURL = $ENV{"SCRIPT_URI"};
	$tableURL = $tableURL . "?project=" . $project;

	($project, $timestamp, $wikipage, $parent) = 
		get_project_data($project);
	if ( ! defined $wikipage) 
	{
		print "Data for $project "; 	
	}
	else
	{
		print "Data for " . get_link_from_api("[[$wikipage]]") . " "; 
	}
	print "(<b>lists \| <a href=\"" . $tableURL . "\">summary table</a>)\n";
	
}