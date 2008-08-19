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

if ( ! defined $param{'sorta'} ) { 
  $param{'sorta'} = 'Project';
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


  my $query;
  my $queryc;
  my @qparam;
  my @qparamc;

  my $sort = $params->{'sorta'};

  $queryc = "SELECT count(r_article) FROM ratings WHERE";

  if ( $sort eq 'Project' || $sort eq 'Project (reverse)' ) { 
    $query = "SELECT * FROM ratings WHERE";
  } elsif ( $sort eq 'Importance' || $sort eq 'Importance (reverse)' ) { 
    $query = "SELECT r_project, r_article, r_quality,
                     r_quality_timestamp, r_importance,
                     r_importance_timestamp, c_ranking
                 from ratings join categories
                on r_project = c_project
                 and c_type = 'importance'
                 and c_rating = r_importance WHERE";
  } elsif ( $sort eq 'Quality' || $sort eq 'Quality (reverse)' ) { 
    $query = "SELECT r_project, r_article, r_quality,
                     r_quality_timestamp, r_importance,
                     r_importance_timestamp, c_ranking
                from ratings join categories
                on r_project = c_project
                 and c_type = 'quality'
                 and c_rating = r_quality WHERE";
  }


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
      $query .= " AND r_article REGEXP ?";
      $queryc .= " AND r_article REGEXP ?";
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


  if (   $sort eq 'Quality' || $sort eq 'Quality (reverse)'
      || $sort eq 'Importance' || $sort eq 'Importance (reverse)' ) { 
    $query .= " ORDER BY c_ranking";
  } else { 
    $query .= " ORDER BY r_project";
  }

  if ( ! ($sort =~ /reverse/) ) { 
    $query .= ' DESC';
  } 

  $query .= ", r_article";

  $query .= " LIMIT ?";
  push @qparam, $limit;

  $query .= " OFFSET ?";
  push @qparam, $offset;

  # clean up the SQL for edge cases 
  $query =~ s/WHERE AND/WHERE /;
  $queryc =~ s/WHERE AND/WHERE /;

  $query =~ s/WHERE ORDER/ORDER/;
  $queryc =~ s/WHERE ORDER/ORDER/;

  print "Q: $query<br/>\n";
#  print join "<br/>", @qparam;

  my $sthcount = $dbh->prepare($queryc);
  $sthcount->execute(@qparamc);
  	
  my @row = $sthcount->fetchrow_array() ;
  my $total = $row[0];
  
  print "<div class=\"navbox\">\n";
  print_header_text($project);
  print "</div>\n";

  print "<p><b>Total results: " . $total 
        . "</b>.<br/> Displaying up to $limit results beginning with #" 
        . ($offset +1) . "</p>\n";

  my $sth = $dbh->prepare($query);
  my $c = $sth->execute(@qparam);
  my $i = $offset;

  print "<center>\n<table class=\"wikitable\">\n";
  while ( @row = $sth->fetchrow_array ) {
    $i++;

    print "<tr><td>$i</td>\n";
    print "    <td>" . $row[0] . "</td>\n";
    print "    <td>" . $row[1] . "</td>\n";
    print "    " . get_cached_td_background($row[2]) . "\n";
    print "    <td>" . $row[3] . "</td>\n";
    print "    " . get_cached_td_background($row[4]) . "\n";
    print "    <td>" . $row[5] . "</td>";

    print "<td>$row[6]</td>\n";

    print "\n";
    print "</tr>\n";
  }
  print "</table>\n</center>\n";
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


  my $query;

  my $queryc = "SELECT count(ra.r_article) FROM ratings as ra join ratings as rb on rb.r_article = ra.r_article" . 
              " WHERE ra.r_project = ? AND rb.r_project = ?";

  my @qparam = ($projecta, $projectb);
  my @qparamc = ($projecta, $projectb);

  my $sort = $params->{'sorta'};

  if ( $sort eq 'Project' || $sort eq 'Project (reverse)' ) { 
    $query =   "SELECT ra.r_article, ra.r_quality, ra.r_importance, 
                       rb.r_quality, rb.r_importance
                FROM ratings as ra 
                JOIN ratings as rb 
                     on rb.r_article = ra.r_article
                WHERE ra.r_project = ? AND rb.r_project = ?";
  } elsif ( $sort eq 'Importance' || $sort eq 'Importance (reverse)' ) { 
    $query =   "SELECT ra.r_article, ra.r_quality, ra.r_importance, 
                       rb.r_quality, rb.r_importance, c_ranking
                FROM ratings AS ra 
                JOIN ratings AS rb 
                     ON rb.r_article = ra.r_article
                JOIN categories 
                     ON ra.r_project = c_project
                     AND c_type = 'importance'
                     AND c_rating = ra.r_importance
                WHERE ra.r_project = ? AND rb.r_project = ?";
  } elsif ( $sort eq 'Quality' || $sort eq 'Quality (reverse)' ) { 
    $query =   "SELECT ra.r_article, ra.r_quality, ra.r_importance, 
                       rb.r_quality, rb.r_importance, c_ranking
                FROM ratings AS ra 
                JOIN ratings AS rb 
                     ON rb.r_article = ra.r_article
                JOIN categories 
                     ON ra.r_project = c_project
                     AND c_type = 'quality'
                     AND c_rating = ra.r_quality
                WHERE ra.r_project = ? AND rb.r_project = ?";
  }


  my $quality = $params->{'quality'};
  my $qualityb = $params->{'qualityb'};

  if ( defined $quality && $quality =~ /\w|\d/) {
    $query .= " AND ra.r_quality = ?";
    $queryc .= " AND ra.r_quality = ?";
    push @qparam, $quality;
    push @qparamc, $quality;
  }

  if ( defined $qualityb && $qualityb =~ /\w|\d/) {
    $query .= " AND rb.r_quality = ?";
    $queryc .= " AND rb.r_quality = ?";
    push @qparam, $qualityb;
    push @qparamc, $qualityb;
  }

  my $importance =  $params->{'importance'};
  my $importanceb =  $params->{'importanceb'};

  if ( defined $importance && $importance =~ /\w|\d/) {
    $query .= " AND ra.r_importance = ?";
    $queryc .= " AND ra.r_importance = ?";
    push @qparam, $importance;
    push @qparamc, $importance;
  }

  if ( defined $importanceb && $importanceb =~ /\w|\d/) {
    $query .= " AND rb.r_importance = ?";
    $queryc .= " AND rb.r_importance = ?";
    push @qparam, $importanceb;
    push @qparamc, $importanceb;
  }


  my $pagename = $params->{'pagename'};

  if ( defined $pagename and $pagename =~ /\w|\d/ ) {
    if ( $params->{'pagenameWC'} eq 'on' ) {
      $query .= " AND ra.r_article REGEXP ?";
      $queryc .= " AND ra.r_article REGEXP ?";
      push @qparam, $pagename;
      push @qparamc, $pagename;
    } else {
      $query .= " AND ra.r_article = ?";
      $queryc .= " AND ra.r_article = ?";
      push @qparam, $pagename;
      push @qparamc, $pagename;
    }
  }

  if ( defined $param{'diffonly'} ) { 
    $query .= " AND NOT ra.r_quality = rb.r_quality";
    $queryc .= " AND NOT ra.r_quality = rb.r_quality";
  }

  if (   $sort eq 'Quality' || $sort eq 'Quality (reverse)'
      || $sort eq 'Importance' || $sort eq 'Importance (reverse)' ) { 
    $query .= " ORDER BY c_ranking";
  } else { 
    $query .= " ORDER BY ra.r_project";
  }

  if ( ! ($sort =~ /reverse/) ) { 
    $query .= ' DESC';
  } 

  $query .= ", ra.r_article";

  $query .= " LIMIT ?";
  push @qparam, $limit;

  $query .= " OFFSET ?";
  push @qparam, $offset;

  print "Q: $query\<br/>\n";
#  print join "<br/>", @qparam;

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
        . ($offset +1) . "</p>\n";


  my $sth = $dbh->prepare($query);
  my $c = $sth->execute(@qparam);
  my $i = $offset;

  print << "HERE";
<center>
<table class="wikitable">
<tr>
  <th><b>Result</b></th>
  <th><b>Article</b></th>
  <th colspan="2"><b>$projecta</b></th>
  <th colspan="2"><b>$projectb</b></th>
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
  print "</table>\n</center>\n";
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

  my $diffonly_checked = "";
  if ( defined $param{'diffonly'} ) {
    $diffonly_checked = "checked";
  }


  my $sorts = sort_orders();
  my $s;
  my $sort_html = "";
  foreach $s ( sort {$a cmp $b} keys %$sorts ) {
    $sort_html .=  "<option value=\"$s\"";
    if ( $s eq $param{'sorta'} ) { 
      $sort_html .= " selected"; 
    }
    $sort_html .= ">$s</option>\n";
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
  <tr><td>Quality</td>
      <td><input type="text" value="$quality" name="quality"/></td></tr>
  <tr><td>Importance</td>
      <td><input type=\"text\" value="$importance" name="importance"/></td></tr>
  <tr><td colspan="2"><input type="checkbox" $pagename_wc_checked  name="pagenameWC" />
      Treat page name as a <a href="http://en.wikipedia.org/wiki/Regular_expression">regular expression</a></td></tr>
   <tr><td colspan="2" class="note">Note: leave any field blank to 
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
  <tr><td colspan="2"><input type="checkbox" name="diffonly" $diffonly_checked>
     Show only rows where quality ratings differ</input>
     </td></tr>
  </table></td></tr>

<tr><td><b>Output options</b></td></tr>
<tr><td><table class="subform">
  <tr><td>Results per page</td>
      <td><input type="text" value="$limit" name="limit"/></td></tr>
  <tr><td>Start with result #</td>
      <td><input type="text" value="$offset" name="offset"/></td></tr>
  <tr><td>Sort by</td><td><select name="sorta">
      $sort_html
      </select></td></tr>
  <tr><td colspan="2" class="note">Note: sorting is done 
            relative to the first project. </td></tr>
  <tr><td colspan="2" style="text-align: center;">
    <input type="submit" value="Make list"/>
    </td></tr>
  </table></td></tr>
</table></form>
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

###########################################################################

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

###########################################################################

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

###########################################################################

sub print_header_text {
  my $project = shift;
  my ($timestamp, $wikipage, $parent, $shortname);
  my $tableURL = $ENV{"SCRIPT_URI"};
  my @t = split('list2.pl',$tableURL);
  $tableURL = @t[0] . "table.pl";

  if ( $project =~ /\w|\d/ ) { 
    $tableURL = $tableURL . "?project=" . $project;

    ($project, $timestamp, $wikipage, $parent, $shortname) = 
      get_project_data($project);

    if ( ! defined $wikipage) {
      print "Data for $project "; 	
    } elsif ( ! defined $shortname) {
      print "Data for " . get_link_from_api("[[$wikipage]]") . " "; 
    } else {
      print "Data for " . get_link_from_api("[[$wikipage|$shortname]]") . " ";
    }
  } else { 
    print " Data for all projects ";
  }

  print "(<b>list</b> \| <a href=\"" . $tableURL 
        . "\">summary table</a>)\n";
}

###########################################################################

sub sort_orders { 
   return { 
            'Project' => 'r_project',
            'Project (reverse)' => 'r_project DESC',
            'Quality' => 'r_quality',
            'Quality (reverse)' => 'r_quality DESC',
            'Importance' => 'r_importance',
            'Importance (reverse)' => 'r_importance DESC',
          };
}
