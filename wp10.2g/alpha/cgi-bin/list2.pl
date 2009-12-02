#!/usr/bin/perl

# list2.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for more information

=head1 SYNOPSIS

CGI program to display lists of assessed articles

=cut

use strict;
use Encode;
use URI::Escape;

require 'read_conf.pl';
our $Opts = read_conf();

require 'database_www.pl';
require 'layout.pl';

require CGI;
require CGI::Carp; 
CGI::Carp->import('fatalsToBrowser');

require DBI;
require POSIX;
POSIX->import('strftime');

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


if ( defined $Opts->{'log-dir'} 
     && -d $Opts->{'log-dir'} ) { 
  open LOG, ">", $Opts->{'log-dir'} . "/" . $logFile;
  print LOG $logEntry . "\n";
  close LOG;
}

my $proj = $param{'project'} || $ARGV[0];

our $dbh = db_connect_rw($Opts);  # needs read-write access for cache

print CGI::header(-type=>'text/html', -charset=>'utf-8');      

layout_header("Article lists");

my $projects = list_projects($dbh);
query_form(\%param, $projects);


if ( defined $param{'run'} || defined $ARGV[0]) { 
  ratings_table(\%param, $projects);
}

layout_footer();

exit;
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
	
  my $limit = $params->{'limit'} || 100;
  my $offset = $params->{'offset'} || 0;
  if ( $offset > 0 ) { $offset --; }

  my $query;
  my $queryc;
  my @qparam;
  my @qparamc;


  $queryc = "SELECT count(r_article) FROM ratings as ra";

  $query = << "HERE";
SELECT r_project, r_namespace, r_article, r_importance, 
       r_importance_timestamp, r_quality, 
       r_quality_timestamp, rel_0p5_category, 
       rev_value, ISNULL(rel_0p5_category) as null_rel,
       ISNULL(rev_value) as null_rev, r_score
HERE

my $show_external = ($params->{'showExternal'} eq "on");

if ( $show_external ) { 
  $query .= "      , sd_pagelinks, sd_langlinks, sd_hitcount \n";
}

  $query .= << "HERE";
   FROM ratings as ra
HERE

  if ( $show_external ) { 
    $query .= << "HERE";
   LEFT JOIN selection_data ON r_namespace = 0 AND r_article = sd_article
HERE
  }

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
      print << "HERE";
        <div class="navbox">
         Project '$project' is not in the database.
        </div>
HERE
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

  my $score = $params->{'score'};
  if ( defined $score && $score =~ /\d/ ) { 
    $score =~ s/[^\d]//;
    $query .= " AND r_score >= ?";
    $queryc .= " AND r_score >= ?";
    push @qparam, $score;
    push @qparamc, $score;
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

# print "<pre>QQ:\n$query</pre>\n";
# print join "<br/>", @qparam;

#  print "QC: $queryc<br/>\n";

  my $sthcount = $dbh->prepare($queryc);
  $sthcount->execute(@qparamc);
  	
  my @row = $sthcount->fetchrow_array() ;
  my $total = $row[0];
  
  print "<div class=\"navbox\">\n";
  print_header_text($project);
  print "<br/><b>Total results:&nbsp;" . $total 
        . "</b>. Displaying up to $limit results beginning with #" 
        . ($offset +1) . "\n";
  print "</div>\n";

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
    <th colspan="2">
      <a class="info">
        <b>Review</b><br/><b>Release</b>
        <span>Shows whether this article has been reviewed as a featured 
              article or good article, and whether the article has been 
              included in a release version of Wikipedia.
        </span>
      </a>
    </th>
HERE

if ( $show_external ) { 
  print << "HERE";
    <th><a class="info">PL
          <span>Number of pages that link to this page.</span>
        </a>
    </th>  
    <th><a class="info">LL
          <span>Number of pages that link to this page.</span>
        </a>
    </th>  
    <th><a class="info">Hits
          <span>Number of pages that link to this page.</span>
        </a>
    </th>  
HERE
  }

print << "HERE";
    <th colspan="1">
      <a class="info">
        <b>Score</b>
        <span>This number is used to automatically select articles for 
              release versions of Wikipedia.
        </span>
    </th>
  </tr>
HERE

  my $evenodd;

  while ( @row = $sth->fetchrow_array ) {
    $i++;

    if ( 0 == $i % 2 ) { $evenodd = "list-even"; } 
    else { $evenodd = "list-odd"; }    

    print "<tr class=\"$evenodd\">";
    print "    <td class=\"resultnum\">" . $i . "</td>\n";

    if (  ! ( $project =~ /\w|\d/ ) ) { 
      print "    <td>" . $row[0] . "</td>\n";
    }

    print "    <td>" . make_article_link($row[1], $row[2]) . "</td>\n";
    print "    " . get_cached_td_background($row[3]) . "\n";
    print "    <td>" . make_history_link($row[1],$row[2],$row[4],0,1) 
                     . "</td>\n";
    print "    " . get_cached_td_background($row[5]) . "\n";
    print "    <td>" . make_history_link($row[1],$row[2],$row[6],0,1) 
                     . "</td>";


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

    if ( $show_external ) { 
      my ( $external_pl, $external_ll, $external_hc );
      $external_pl = $row[12] || "0";
      $external_ll = $row[13] || "0";
      $external_hc = $row[14] || "0";
      print << "HERE";
       <td class="external">$external_pl</td>
       <td class="external">$external_ll</td>
       <td class="external">$external_hc</td>
HERE
    }

    print "<td class=\"score\">" . $row[11] . "</td>\n";

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
    my $newURL = make_list_link() . "?" . $params_enc
		      . "&offset=" . ($offset - $limit + 1);	  
    print "<a href=\"" . $newURL . "\">Previous $limit entries</a>";
    $prev = 1;
  }
	
  if ($limit + $offset < $total)  {
    if ($prev == 1)  {
      print " | ";
    }
    my $newURL = make_list_link() . "?" . $params_enc 
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
       ISNULL(rev_value) as null_rev, ra.r_score, rb.r_score
HERE

  my $show_external = ($params->{'showExternal'} eq "on");
  if ( $show_external ) {
    $query .= "      , sd_pagelinks, sd_langlinks, sd_hitcount \n";
  }

  $query .= << "HERE";
  FROM ratings as ra
HERE

  if ( $show_external ) {
    $query .= << "HERE";
   LEFT JOIN selection_data ON r_namespace = 0 AND r_article = sd_article
HERE
  }
  
$query .= << "HERE";
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

  my $score = $params->{'score'};
  if ( defined $score && $score =~ /\d/ ) { 
    $score =~ s/[^\d]//;
    $query .= " AND r_score >= ?";
    $queryc .= " AND r_score >= ?";
    push @qparam, $score;
    push @qparamc, $score;
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

#  print "<pre>QQ: $query</pre><br/>\n";
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
  <th colspan="3"><b>$projecta</b></th>
  <th colspan="1" class="spacer">&nbsp;</th>
  <th colspan="3"><b>$projectb</b></th>
  <th colspan="2">
    <a class="info">
      <b>Review</b><br/><b>Release</b>
        <span>Shows whether this article has been reviewed as a featured
              article or good article, and whether the article has been
              included in a release version of Wikipedia.
        </span>
      </a>
  </th>
HERE

if ( $show_external ) {
  print << "HERE";
    <th><a class="info">PL
          <span>Number of pages that link to this page.</span>
        </a>
    </th>
    <th><a class="info">LL
          <span>Number of interlanguage links to this page.</span>
        </a>
    </th>
    <th><a class="info">Hits
          <span>A measure of the average daily hitcount of this page, including redirects..</span>
        </a>
    </th>
HERE
  }

  print "</tr>\n";

  my $evenodd;
     
  while ( @row = $sth->fetchrow_array ) {
    $i++;

    if ( 0 == $i % 2 ) { $evenodd = "list-even"; } 
    else { $evenodd = "list-odd"; }    

    print "<tr class=\"$evenodd\">\n";
    print "    <td class=\"resultnum\">" . $i . "</td>\n";
    print "    <td>" . make_article_link($row[0], $row[1]) . "</td>\n";
    print "    " . get_cached_td_background($row[2]) . "\n";
    print "    " . get_cached_td_background($row[3]) . "\n";
    print "<td class=\"score\">$row[10]</td\n";
    print "<td class=\"spacer\">&nbsp;</td>\n";
    print "    " . get_cached_td_background($row[4]) . "\n";
    print "    " . get_cached_td_background($row[5]) . "\n";
    print "<td class=\"score\">$row[11]</td\n";
    print "<td class=\"spacer\">&nbsp;</td>\n";

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

    if ( $show_external ) {
      my ( $external_pl, $external_ll, $external_hc );
      $external_pl = $row[12] || "0";
      $external_ll = $row[13] || "0";
      $external_hc = $row[14] || "0";
      print << "HERE";
       <td class="external">$external_pl</td>
       <td class="external">$external_ll</td>
       <td class="external">$external_hc</td>
HERE
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
    my $newURL =  $Opts->{'list2-url'} . "?" . $params_enc
               . "offset=" . ($offset - $limit + 1);	  
		
    print "<a href=\"" . $newURL . "\">Previous $limit entries</a>";
    $prev = 1;
  }
	
  if ($limit + $offset < $total){ 
    if ($prev == 1) {
 	print " | ";
    }
    my $newURL =  $Opts->{'list2-url'}  . "?" . $params_enc
                 . "&offset=" . ($offset + $limit + 1);	  

    print "<a href=\"" . $newURL . "\">Next $limit entries</a>";
  }
  print "\n";	
}

###########################################################################

sub query_form {
  my $params = shift;

  my $projecta = $params->{'projecta'} || '';
  my $projectb = $params->{'projectb'} || '';

  my $quality = $params->{'quality'} || "";
  my $importance = $params->{'importance'} || "";
  my $score = $params->{'score'} || "";
  
  my $qualityb = $params->{'qualityb'} || "";
  my $importanceb = $params->{'importanceb'} || "";
  my $limit = $params->{'limit'} || "100";
  my $offset = $params->{'offset'} || "1";
  my $intersect = $params->{'intersect'} || "";
  my $pagename = $params->{'pagename'} || "";
  my $pagenameWC = $params->{'pagenameWC'} || "";
  my $show_external = $params->{'showExternal'} || "";
  my $filter_release = $params->{'filterRelease'} || "";

  my $intersect_checked = "";
  if ( $intersect eq 'on' ) { 
    $intersect_checked = "checked=\"yes\" ";
  }

  my $filter_release_checked = "";
  if ( $filter_release eq 'on' ) { 
    $filter_release_checked = "checked=\"yes\" ";
  }

  my $pagename_wc_checked = "";
  if ( $pagenameWC eq 'on' ) { 
    $pagename_wc_checked = "checked=\"yes\" ";
  }

  my $show_external_checked = "";
  if ( $show_external eq 'on' ) { 
    $show_external_checked = "checked=\"yes\" ";
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
    <tr><td>Score</td>
      <td>\&ge; <input size=\"5\" type=\"text\" value="$score" name="score"/></td></tr>
    <tr><td colspan="2"><input type="checkbox" $pagename_wc_checked  name="pagenameWC" />
      Treat page name as a 
      <a href="http://en.wikipedia.org/wiki/Regular_expression">regular expression</a></td></tr>
    <tr><td colspan="2"><input type="checkbox" $show_external_checked  name="showExternal" />
      Show external interest data
    <tr><td colspan="2" class="note">Note: leave any field blank to 
                       select all values.</td></tr>
  </table>
</td></tr>	
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
     <input type="checkbox" $filter_release_checked  name="filterRelease"  
        rel="release"/>
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

sub print_header_text {
  my $project = shift;
  my ($timestamp, $wikipage, $parent, $shortname);
  my $tableURL =  $Opts->{'table-url'};

  if ( $project =~ /\w|\d/ ) { 
    $tableURL = $tableURL . "?project=" . $project;

    ($project, $timestamp, $wikipage, $parent, $shortname) = 
      get_project_data($project);

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

  print "(<b>list</b> \| <a href=\"" 
  . $Opts->{'table-url'} . "\">summary table</a>)\n";
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
            'Score' => 'r_score',
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
  } elsif ( $sort eq 'Score' )  { 
    $query .= ' ra.r_score';
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
    if ( ($sort =~ /Project/) || ($sort =~ /Review/)) { 
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
       || $sort eq 'Release status' || $sort eq 'Review status'
       || $sort eq 'Score'  ) { 
    # No additional SQL needed
  } elsif ( $sort eq 'Importance' || $sort eq 'Importance (reverse)' ) { 
    $query .=   "   JOIN categories AS c$which
                     ON " . $ratings . "r_project = c$which.c_project
                     AND c$which.c_type = 'importance'
                     AND c$which.c_rating = " . $ratings ."r_importance\n ";
  } elsif ( $sort eq 'Quality' || $sort eq 'Quality (reverse)' ) { 
    $query .=   " JOIN categories AS c$which
                     ON " . $ratings . "r_project = c$which.c_project
                     AND c$which.c_type = 'quality'
                     AND c$which.c_rating = " . $ratings . "r_quality\n ";
  } else { 
    die "Unknown sort key in sort_sql\n";
  }
  
  return $query;
}

