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
$api->base_url(get_conf('api_url'));

require CGI;
require CGI::Carp; 
CGI::Carp->import('fatalsToBrowser');

require DBI;
require POSIX;
POSIX->import('strftime');

my $cacheFile = init_cache();
my $cacheMem = {};

my $Namespaces;

my $cgi = new CGI;
my %param = %{$cgi->Vars()};

if ( $param{'limit'} > 1000 ) { 
  $param{'limit'} = 1000;
}

if ( ! defined $param{'sorta'} ) { 
  $param{'sorta'} = 'Importance';
}

if ( ! defined $param{'sortb'} ) { 
  $param{'sortb'} = 'Quality';
}

my $p;
my $logFile = "list2." . time() . "." . $$;
my $logEntry = $logFile;

foreach $p ( keys %param ) { 
  $param{$p} =~ s/^\s*//;
  $param{$p} =~ s/\s*$//;
  $logEntry .= "&" . uri_escape($p) . "=" . uri_escape($param{$p});
}

# FIXME: Use get_conf instead of Opts
if ( defined $Opts->{'log-dir'} 
     && -d $Opts->{'log-dir'} ) { 
  open LOG, ">", $Opts->{'log-dir'} . "/" . $logFile;
  print LOG $logEntry . "\n";
  close LOG;
}

my $proj = $param{'projecta'} || $ARGV[0];

our $dbh = db_connect($Opts);

print CGI::header(-type=>'text/html', -charset=>'utf-8');      

if (defined $param{'projecta'}) {
	layout_header("Article lists: " . $proj . " " . get_conf('pages_label'), 1);
} else {
	layout_header("Article lists", 1);
}

my $projects = list_projects();
query_form(\%param, $projects);


if ( defined $param{'run'} ) { 
  ratings_table(\%param, $projects);
}

layout_footer();


exit;
###########################################################################
###########################################################################

sub ratings_table { 
  my $params = shift;
  my $projects = shift;

  my $p;
  # FIXME: use get_conf('class-suffix') instead of "-Class";
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
	
  my $limit = $params->{'limit'} || 100;
  my $offset = $params->{'offset'} || 0;
  if ( $offset > 0 ) { $offset --; }

  my $query;
  my $queryc;
  my @qparam;
  my @qparamc;


  $queryc = "SELECT count(r_article) FROM ratings";

  $query = << "HERE";
SELECT r_project, r_namespace, r_article, r_importance, 
       r_importance_timestamp, r_quality, 
       r_quality_timestamp, rel_0p5_category, 
       rev_value, ISNULL(rel_0p5_category) as null_rel,
       ISNULL(rev_value) as null_rev
FROM ratings 
HERE

  my $sort = $params->{'sorta'};
  my $sortb = $params->{'sortb'};
  $query .= sort_sql($sort, "a", "") . " " . sort_sql($sortb, "b", "") ." ";

  $query .= " LEFT JOIN releases ON r_namespace = 0 
                     AND r_article = rel_article ";
  $query .= " \n   LEFT JOIN reviews ON r_namespace = 0 
                      AND r_article = rev_article ";

  $query .= " \nWHERE";
  $queryc .= " \nWHERE";

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
    if ( $quality eq 'Assessed-Class' ) { 
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


  $query .= " \nORDER BY ";
  $query .= sort_key($sort, "a", "");
  $query .= ", ";
  $query .= sort_key($sortb, "b", "");

  $query .= ", r_namespace, r_article";

  $query .= " LIMIT ?";
  push @qparam, $limit;

  $query .= " OFFSET ?";
  push @qparam, $offset;

  # clean up the SQL for edge cases 
  $query =~ s/WHERE\s*AND/WHERE /;
  $queryc =~ s/WHERE\s*AND/WHERE /;

  $query =~ s/WHERE\s*ORDER/ORDER/;
  $queryc =~ s/WHERE\s*ORDER/ORDER/;

  $queryc =~ s/WHERE\s*$//;

# print "<pre>Qs:\n$query</pre>\n";
# print join "<br/>", @qparam;

#  print "QC: $queryc<br/>\n";

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

  print << "HERE";
  <center><table class="wikitable">
  <tr>
    <th><b>Result</b></th>
HERE

    if (  ! ( $project =~ /\w|\d/ ) ) { 
      print "    <th>Project</th>\n";

    }

print << "HERE";
    <th><b>Article</b></th>
    <th colspan="2"><b>Importance</b></th>
    <th colspan="2"><b>Quality</b></th>
    <th colspan="2"><b>Review</b><br/><b>Release</b></th>
  </tr>
HERE


  while ( @row = $sth->fetchrow_array ) {
    $i++;

    print "<tr><td>$i</td>\n";

    if (  ! ( $project =~ /\w|\d/ ) ) { 
      print "    <td>" . $row[0] . "</td>\n";
    }

    print "    <td>" . make_article_link($row[1], $row[2]) . "</td>\n";
    print "    " . get_cached_td_background($row[3]) . "\n";
    print "    <td>" . make_history_link($row[1],$row[2],$row[4]) . "</td>\n";
    print "    " . get_cached_td_background($row[5]) . "\n";
    print "    <td>" . make_history_link($row[1],$row[2],$row[6]) . "</td>";


    if ( defined $row[8] ) { 
      print make_review_link($row[8]) ;
    } else { 
      print "<td></td>\n"; 
    }

    if ( defined $row[7] ) { 
      print "<td>" . make_wp05_link($row[7]) . "</td>\n";
    } else { 
      print "<td></td>\n"; 
    }

    print "\n";
    print "</tr>\n";
  }
  print "</table>\n</center>\n";

  # For display purposes - whether we use a pipe between "previous" and "next"
  # depends on whether "previous" is defined or not 
  my $prev = 0;

  my $p;
  my $params_enc;
  foreach $p ( keys %$params ) { 
    next if ( $p eq 'offset' ) ;
    $params_enc .= "$p=" . uri_escape($params->{$p}) . "&";   
  }

  if (($offset - $limit + 1) > 0)  {
    my $newURL = $ENV{"SCRIPT_URI"} . "?" . $params_enc
		      . "&offset=" . ($offset - $limit + 1);	  
    print "<a href=\"" . $newURL . "\">Previous $limit entries</a>";
    $prev = 1;
  }
	
  if ($limit + $offset < $total)  {
    if ($prev == 1)  {
      print " | ";
    }
    my $newURL = $ENV{"SCRIPT_URI"} . "?" . $params_enc 
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

  my $queryc = "SELECT count(ra.r_article) 
                FROM ratings as ra 
                JOIN ratings as rb on rb.r_article = ra.r_article
                              AND ra.r_namespace = rb.r_namespace
                WHERE ra.r_project = ? AND rb.r_project = ?";

  my @qparam = ($projecta, $projectb);
  my @qparamc = ($projecta, $projectb);


  $query = << "HERE";
SELECT ra.r_namespace, ra.r_article, ra.r_importance, ra.r_quality,
       rb.r_importance, rb.r_quality, rel_0p5_category,
       rev_value, ISNULL(rel_0p5_category) as null_rel,
       ISNULL(rev_value) as null_rev
FROM ratings as ra
  JOIN ratings as rb ON rb.r_article = ra.r_article 
                    AND ra.r_namespace = rb.r_namespace  
HERE

  my $sort = $params->{'sorta'};
  my $sortb = $params->{'sortb'};
  $query .= sort_sql($sort, "a", "ra") . " " 
      . sort_sql($sortb, "b", "ra") ." ";

  $query .= " LEFT JOIN releases ON ra.r_namespace = 0 
                  AND ra.r_article = rel_article ";
  $query .= " \n   LEFT JOIN reviews ON ra.r_namespace = 0 
                     AND ra.r_article = rev_article ";

  $query .= " \nWHERE ra.r_project = ? AND rb.r_project = ?";

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
    $query .= " AND NOT ra.r_quality = rb.r_quality ";
    $queryc .= " AND NOT ra.r_quality = rb.r_quality ";
  }


  $query .= " \nORDER BY ";
  $query .= sort_key($sort, "a", "");
  $query .= ", ";
  $query .= sort_key($sortb, "b", "");

  $query .= ", ra.r_namespace, ra.r_article";

  $query .= " LIMIT ?";
  push @qparam, $limit;

  $query .= " OFFSET ?";
  push @qparam, $offset;

  print "<pre>Q: $query</pre><br/>\n";
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
  <th colspan="2"><b>Review</b><br/><b>Release</b></th>
</tr>
HERE
     
  while ( @row = $sth->fetchrow_array ) {
    $i++;

     print "<tr><td>$i</td>\n";
    print "    <td>" . make_article_link($row[0], $row[1]) . "</td>\n";
    print "    " . get_cached_td_background($row[2]) . "\n";
    print "    " . get_cached_td_background($row[3]) . "\n";
    print "    " . get_cached_td_background($row[4]) . "\n";
    print "    " . get_cached_td_background($row[5]) . "\n";


    if ( defined $row[7] ) { 
      print make_review_link($row[7]) ;
    } else { 
      print "<td></td>\n"; 
    }

    if ( defined $row[6] ) { 
      print "<td>" . make_wp05_link($row[6]) . "</td>\n";
    } else { 
      print "<td></td>\n"; 
    }

    print "</tr>\n";


  }
  print "</table>\n</center>\n";

  my $p;
  my $params_enc;
  foreach $p ( keys %$params ) { 
    next if ( $p eq 'offset' ) ;
    $params_enc .= "$p=" . uri_escape($params->{$p}) . "&";   
  }

  # For display purposes - whether we use a pipe between "previous" and "next"
  # depends on whether "previous" is defined or not 
  my $prev = 0;
  if (($offset - $limit + 1) > 0) {
    my $newURL = $ENV{"SCRIPT_URI"} . "?" . $params_enc
               . "offset=" . ($offset - $limit + 1);	  
		
    print "<a href=\"" . $newURL . "\">Previous $limit entries</a>";
    $prev = 1;
  }
	
  if ($limit + $offset < $total){ 
    if ($prev == 1) {
 	print " | ";
    }
    my $newURL = $ENV{"SCRIPT_URI"} . "?" . $params_enc
                 . "&offset=" . ($offset + $limit + 1);	  

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
  my $limit = $params->{'limit'} || "100";
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
  my $sort_htmlb = "";
  foreach $s ( sort {$a cmp $b} keys %$sorts ) {
    $sort_html .=  "<option value=\"$s\"";
    $sort_htmlb .=  "<option value=\"$s\"";
    if ( $s eq $param{'sorta'} ) { 
      $sort_html .= " selected"; 
    }
    if ( $s eq $param{'sortb'} ) { 
      $sort_htmlb .= " selected"; 
    }
    $sort_html .= ">$s</option>\n";
    $sort_htmlb .= ">$s</option>\n";
  }

  print << "HERE";
<form>
<input type="hidden" name="run" value="yes"/>


<table class="outer">
<tr><td>
<table class="mainform">
<tr>
<td id="projecta" class="toprow"><b>First project</b><br/>
  <table class="subform">
    <tr><td>Project name</td>
      <td><input type="text" value="$projecta" name="projecta"/></td></tr>
    <tr><td>Page name</td>
      <td><input type="text" value="$pagename" name="pagename"/></td></tr>
    <tr><td>Quality</td>
      <td><input type="text" value="$quality" name="quality"/></td></tr>
    <tr><td>Importance</td>
      <td><input type=\"text\" value="$importance" name="importance"/></td></tr>
    <tr><td colspan="2"><input type="checkbox" $pagename_wc_checked  name="pagenameWC" />
      Treat page name as a 
      <a href="http://en.wikipedia.org/wiki/Regular_expression">regular expression</a></td></tr>
    <tr><td colspan="2" class="note">Note: leave any field blank to 
                       select all values.</td></tr>
  </table>
</td>
</tr>
<tr>
<td class="bottomrow"><b>Output options</b><br/>
<table class="subform">
  <tr><td>Results per page</td>
      <td><input type="text" value="$limit" name="limit"/></td></tr>
  <tr><td>Start with result #</td>
      <td><input type="text" value="$offset" name="offset"/></td></tr>
  <tr><td>Primary sort by</td><td><select name="sorta">
      $sort_html
      </select></td></tr>
  <tr><td>Secondary sort by</td><td><select name="sortb">
      $sort_htmlb
      </select></td></tr>
  <tr><td colspan="2" class="note">Note: sorting is done 
            relative to the first project. </td></tr>
</table>
<div style="text-align: center;"><input type="submit" value="Generate list"/></div>
</td>
</tr>
</table>
</td>
<td style="vertical-align: top;">
<table class="mainform">
<td id="projectb" class="toprow"><input type="checkbox" 
        $intersect_checked  name="intersect"  rel="secondproj"/>
       <b>Specify second project</b><br/>
  <table class=\"subform\" rel="secondproj">
    <tr><td>Project name</td>
      <td><input type="text" value="$projectb" name="projectb"/></td></tr>
    <tr><td>Quality</td>
      <td><input type="text" value="$qualityb" name="qualityb"/></td></tr>
    <tr><td>Importance</td>
      <td><input type=\"text\" value="$importanceb" name="importanceb"/></td></tr>
    <tr><td colspan="2"><input type="checkbox" name="diffonly" $diffonly_checked>
       Show only pages with differing quality ratings</input></td></tr>
  </table>
</td></tr>


  <tr>
    <td class="bottomrow">
     <input type="checkbox" $intersect_checked  name="intersect"  rel="release"/>
     <b>Filter release / review data</b><br/>
     <table class=\"subform\" rel="release">
       <tr><td>Not yet implemented</td></tr>
      </table>
  </td></tr>
  </table>
</td></tr>



</tr></table>

</td></tr>

</table>




</form>

HERE

}

###########################################################################

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
  # FIXME: use get_conf('class-suffix'); 
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
  my $baseURL = get_conf('base_url');
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
  my $tableURL = get_conf('table-url');
  my $logURL = get_conf('log-url');

  if ( $project =~ /\w|\d/ ) { 
    $tableURL = $tableURL . "project=" . $project;
    $logURL = $logURL . "project=" . $project;

    ($project, $timestamp, $wikipage, $parent, $shortname) = 
      get_project_data($project);

	# If the project is defined, show the project's navbar
    if ( ! defined $wikipage) {
      print "Data for <b>$project</b> "; 	
    } elsif ( ! defined $shortname) {
      print "Data for <b>" . get_link_from_api("[[$wikipage]]") . "</b> "; 
    } else {
      print "Data for <b>" . get_link_from_api("[[$wikipage|$shortname]]") . "</b> ";
    }
  } else { 
    print " Data for all projects ";
  }

  print "(<b>list</b> \| <a href=\"" . $tableURL 
        . "\">summary table</a> | <a href=\"" . $logURL . "\">assessment log</a>)\n";
}

###########################################################################

sub make_article_link {
  my $server_uri = get_conf('server-url');
  my $ns = shift;
  my $title = shift;

  if ( ! defined $Namespaces ) { 
      $Namespaces = init_namespaces();
  }

  my $a = $Namespaces->{$ns} . $title;
  my $b = $Namespaces->{$ns+1} . $title;		# talk page namespace


  return "<a href=\"$server_uri?title=" . uri_escape($a) . "\">$a</a>"
         . " (<a href=\"$server_uri?title=" . uri_escape($b) 
         . "\">t</a> &middot; "
         . "<a href=\"$server_uri?title=" . uri_escape($a) 
         . "&action=history\">h</a>)";
}

###########################################################################

sub make_history_link { 
  my $ns = shift;
  my $art = shift;
  my $ts = shift;
  my $loadversionURL = get_conf('loadversion-url');

  if ( ! defined $Namespaces ) { 
      $Namespaces = init_namespaces();
  }

  my $art = $Namespaces->{$ns} . $art;

  my $d = $ts;
  $d =~ s/T.*//;

  return "<a href=\"" . $loadversionURL . "?article=" . uri_escape($art) 
       . "&timestamp=" . uri_escape($ts) . "\">$d</a>&nbsp;";
}

###########################################################################
# TODO: i18n
sub make_wp05_link { 
  my $cat = shift;
  my $linka = "http://en.wikipedia.org/wiki/Wikipedia:Wikipedia_0.5";
  my $linkb = "http://en.wikipedia.org/wiki/Wikipedia:Version_0.5";
  my $abbrev = {  'Arts' => 'A',
		  'Engineering, applied sciences, and technology' => 'ET',
		  'Everyday life' => 'EL',
		  'Geography' => 'G',
		  'History' => 'H',
		  'Language and literature' => 'LL',
		  'Mathematics' => 'Ma',
		  'Natural sciences' => 'NS',
		  'Philosophy and religion' => 'PR',
		  'Social sciences and society' => 'SS',
		  'Uncategorized'  => 'U'};

  return "<a href=\"$linka\">0.5</a> " .
        "(<a href=\"$linkb/" . uri_escape($cat) . "\">" . $abbrev->{$cat} . "</a>)";
}


###########################################################################

sub make_review_link { 
  my $type = shift;

  return get_cached_review_icon($type);
	#return get_cached_td_background($type . get_conf('class-suffix')) ;
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
            'Release status' => 'rel_0p5_category',
            'Importance' => 'r_importance',
	    'Review status' => 'rev_value',
          };
}

###########################################################################

sub sort_key { 
  my $sort = shift;
  my $which = shift;
  my $prefix = shift;

  if ( defined $prefix && $prefix ne "") {
    $prefix .= ".";
  }

  my $query = "";

  if (   $sort eq 'Quality' || $sort eq 'Quality (reverse)'
      || $sort eq 'Importance' || $sort eq 'Importance (reverse)' ) { 
    $query .= " c$which.c_ranking";
  } elsif ( $sort eq 'Release status' )  { 
    $query .= " null_rel ASC, rel_0p5_category";
  } elsif ( $sort eq 'Review status' )  { 
    $query .= " null_rev ASC, rev_value";
  } else {
    $query .= " " . $prefix . "r_project";
  }

  if ( $sort =~ /reverse/ ) { 
    if ( $sort =~ /Project/ ) { 
      $query .= ' DESC';
    } else {
      # no
    }
  } else {
    if ( $sort =~ /Project/ ) { 
      #no
    } else {
      $query .= ' DESC';
    }
  }

  return $query;

}

##########################################################################

sub sort_sql { 
  my $sort = shift;
  my $which = shift;
  my $ratings = shift;

  if ( defined $ratings && $ratings ne "" ) { 
    $ratings .= ".";
  }
  
  my $query = "";
  if ( $sort eq 'Project' || $sort eq 'Project (reverse)' 
       || $sort eq 'Release status' || $sort eq 'Review status') { 
    # No additional SQL needed
  } elsif ( $sort eq 'Importance' || $sort eq 'Importance (reverse)' ) { 
    $query .=   " JOIN categories AS c$which
                     ON " . $ratings . "r_project = c$which.c_project
                     AND c$which.c_type = 'importance'
                     AND c$which.c_rating = " . $ratings ."r_importance\n ";
  } elsif ( $sort eq 'Quality' || $sort eq 'Quality (reverse)' ) { 
    $query .=   " JOIN categories AS c$which
                     ON " . $ratings . "r_project = c$which.c_project
                     AND c$which.c_type = 'quality'
                     AND c$which.c_rating = " . $ratings . "r_quality\n ";
  }
  return $query;
}

##########################################################################

sub init_namespaces {

  # Initialize hash of namespace prefixes
  my $r = $api->site_info();
  $r = $r->{'namespaces'}->{'ns'};
  
  my $namespaces ={};
  my $n;
  foreach $n ( keys %$r ) { 
    if (  $r->{$n}->{'content'} ne "" ) { 
      $namespaces->{$n}= $r->{$n}->{'content'} . ":";
    } else { 
      $namespaces->{$n} = "";
    }
  }
  
  return $namespaces;

}

###########################################################################

sub get_cached_review_icon { 
	my $class = shift;
	
	if ( defined $cacheMem->{$class . "-icon"} ) { 
		print " <!-- hit {$class}-icon in memory cache --> ";
		return $cacheMem->{$class . "-icon"};
	}
	
	my $key = "CLASS:" . $class . "-icon";
	my $data;
	
	if ( $cacheFile->exists($key) ) { 
		print " <!-- hit {$class}-icon in file cache, expires " 
		. strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($cacheFile->expiry($key)))
		. " --> ";
		$data = $cacheFile->get($key);
		$cacheMem->{$class} = $data;
		return $data;
	}
	
	$data = get_review_icon($class);
	
	$cacheFile->set($key, $data, '12 hours');
	$cacheMem->{$class . "-icon"} = $data;
	return $data;
}

###########################################################################

sub get_review_icon { 
	my $class = shift;
	my $r =  $api->parse('{{' . $class . get_conf('class_suffix') . '}}');
	my $t = $r->{'text'};
	my $f =  $api->parse('{{' . $class . get_conf('icon_suffix') . '}}');
	my $g = $f->{'text'};
	
	$t =~ s/\|.*//s;
	$t =~ s!^<p>!!;
	$g =~ s/<\/p.*//;
	$g =~ s!^<p>!!;
	# Perl doesn't want to get rid of the rest of the lines in the 
	# multi-line string, so remove them the hard way
	my @str = split(/\n/,$g);
	$g = @str[0];
	undef(@str);
	# FIXME: use get_conf('class-suffix') here again
	$class =~ s/-Class//;
	$t = "<td $t><b>$g&nbsp;$class</b></td>";
	
	return $t;
}

