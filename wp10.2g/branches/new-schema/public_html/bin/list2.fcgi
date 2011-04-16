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

our $dbh = db_connect_rw($Opts);  # needs read-write access for cache

my $cgi;
my $loop_counter = 0;
if ( $Opts->{'use_fastcgi'} ) {
  require CGI::Fast;
  while ( $cgi = CGI::Fast->new() ) { 
    main_loop($cgi);
  }
} else {
  $cgi = new CGI;
  $loop_counter = -5;
  main_loop($cgi);
}

exit;

############################################################

sub main_loop { 
  my $cgi = shift;
  my $Namespaces;

  my %param = %{$cgi->Vars()};

  if ( ! defined $param{'limit'} ) { $param{'limit'} = 250; } 

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

  print CGI::header(-type=>'text/html', -charset=>'utf-8');      

  layout_header("Article lists");

  my $projects = list_projects($dbh);
  query_form(\%param, $projects);

  if ( defined $param{'run'} || defined $ARGV[0]) { 
    ratings_table(\%param, $projects);
  }

  $loop_counter++;
  layout_footer("Debug: PID $$ has served $loop_counter requests");

  exit if ( $loop_counter >= $Opts->{'max-requests'});
}

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
    ratings_table_intersect($params, $projects);
    return;
  } 
  
  my $project = $params->{'projecta'};
  $project =~ s/ /_/g;
  
  my $limit = $params->{'limit'} || 100;
  my $offset = $params->{'offset'} || 0;
  if ( $offset > 0 ) { $offset --; }

  my $query;
  my $queryc;
  my @qparam;
  my @qparamc;

  $queryc = "SELECT count(r_article) FROM " . db_table_prefix() 
           . "ratings as ra";
  $queryc .= " \n   LEFT JOIN " . db_table_prefix() 
                  . "reviews ON r_namespace = 0 
                         AND r_article = rev_article ";
  $queryc .= "  RELEASE-MARKER  ";

  $query = << "HERE";
SELECT /* LIMIT:15 */ r_project, r_namespace, 
       r_article, r_importance, 
       r_importance_timestamp, r_quality, 
       r_quality_timestamp, rel_0p5_category, 
       rev_value, ISNULL(rel_0p5_category) as null_rel,
       ISNULL(rev_value) as null_rev, r_score, ws_revid as wsel
HERE



my $show_external = ($params->{'showExternal'} eq "on");

if ( $show_external ) { 
  $query .= "      , sd_pagelinks, sd_langlinks, sd_hitcount, sd_external \n";
}

  $query .= "FROM " . db_table_prefix() . "ratings as ra ";

  if ( $show_external ) { 
    $query .="LEFT JOIN " . db_table_prefix() 
            . "selection_data ON r_namespace = 0 AND r_article = sd_article ";

  }

  my $sort = $params->{'sorta'};
  my $sortb = $params->{'sortb'};
  $query .= sort_sql($sort, "a", "") . " " . sort_sql($sortb, "b", "") ." ";

  $query .= " LEFT JOIN " . db_table_prefix() . "releases ON r_namespace = 0 
                     AND r_article = rel_article ";
  $query .= " \n   LEFT JOIN " . db_table_prefix() . "reviews ON r_namespace = 0 
                      AND r_article = rev_article ";

  $query .= " \n LEFT JOIN " . db_table_prefix() . "workingselection ON  r_namespace = 0
                       AND ws_article = r_article ";

  my $acategory;

  my $tcategory;

  my $filter_cats = $params->{'filterCategory'} || 0;
  if ( $filter_cats eq 'on' ) { 
    $filter_cats = 1;

#    if ( ! ( defined $params->{'projecta'} && $params->{'projecta'} =~ /\w|\d/ ) ) { 
#      $filter_cats = -3;
#    }
#    if ( ! ( defined $params->{'namespace'} && $params->{'namespace'} =~ /^\d+$/ ) ) { 
#      $filter_cats = -4;
#    }

  }

  if ( $filter_cats > 0) { 
    $acategory = $params->{'category'};
    $tcategory = $params->{'categoryt'};
  }

  if ( ! $acategory =~ /\w|\d/ ) { $acategory = undef; }
  if ( ! $tcategory =~ /\w|\d/ ) { $tcategory = undef; }


  my $aquery;

  if ( defined $acategory) { 
     $acategory =~ s/ /_/g;

     $aquery = "\n join enwiki_p.page as apage on r_namespace = apage.page_namespace 
                   and r_article  = apage.page_title
                   join enwiki_p.categorylinks as acat on apage.page_id = acat.cl_from ";

     $queryc .= $aquery;
     $query .= $aquery;
  }

  if ( defined $tcategory ) { 
     $tcategory =~ s/ /_/g;
     $aquery  = "\n join enwiki_p.page as tpage on (1+r_namespace) = tpage.page_namespace 
                   and r_article = tpage.page_title
                   join enwiki_p.categorylinks as tcat on tpage.page_id = tcat.cl_from ";

     $queryc .= $aquery;
     $query .= $aquery;
  }


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

  my $namespace = $params->{'namespace'};

  if ( defined $namespace and $namespace =~ /^\d+/ ) { 
      $query .= " AND r_namespace = ?";
      $queryc .= " AND r_namespace = ?";
      push @qparam, $namespace;
      push @qparamc, $namespace;
  }

  my $importance =  $params->{'importance'};
  if ( defined $importance && $importance =~ /\w|\d/) {
    $query .= " AND r_importance = ?";
    $queryc .= " AND r_importance = ?";
    push @qparam, $importance;
    push @qparamc, $importance;
  }

  if ( defined $acategory ) { 
    $query .= " AND acat.cl_to = ? ";
    $queryc .= " AND acat.cl_to = ? ";
    push @qparam, $acategory;
    push @qparamc, $acategory;
  }

  if ( defined $tcategory ) { 
    $query .= " AND tcat.cl_to = ? ";
    $queryc .= " AND tcat.cl_to = ? ";
    push @qparam, $tcategory;
    push @qparamc, $tcategory;
  }

  my $score = $params->{'score'};
  if ( defined $score && $score =~ /\d/ ) { 
    $score =~ s/[^\d]//;
    $query .= " AND r_score >= ?";
    $queryc .= " AND r_score >= ?";
    push @qparam, $score;
    push @qparamc, $score;
  }

  my $review_filter = normalize_review_filter($params->{'reviewFilter'});
  my $release_filter = normalize_release_filter($params->{'releaseFilter'});
  my ($review_sql, $review_msg) = review_sql($review_filter);
  my ($release_sql, $release_msg, $release_join) = release_sql($release_filter);

  $query .= $review_sql;
  $queryc .= $review_sql;

  $query .= $release_sql;
  $queryc .= $release_sql;
  $queryc =~ s/RELEASE-MARKER/$release_join/;


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

  if ( defined $params->{'debug'} ) { 
    print "R: " . $release_filter . "\n";

     print "<pre>QQ:\n$query</pre>\n";
     print join "<br/>", @qparam;
  }

# print "QC: $queryc<br/>\n";
# print join "<br/>", @qparamc;

  my $catmsg = ""; # FC: '$filter_cats'<br/>";

  if ( $filter_cats < 0 ) { 
    $catmsg = " <b>Warning:</b> ignoring category filters in this query. Due to performance problems, 
                       category filtering is only enabled when both a project and page namespace are specified. $filter_cats <br/>\n";
  }

  if ( defined $acategory || defined $tcategory ) { 
    $catmsg = "<br/>Data limited to";
    my $link;

    if ( defined $acategory ) { 
      $link = $acategory;
      $link =~ s/_/ /g;
      $link = "<a href=\"" . $Opts->{'server-url'} . "?title=Category:" . uri_escape($link) . "\">Category:$link</a>";
      $catmsg .= " articles in $link";
      if ( defined $tcategory ) { 
        $catmsg .= " and ";
      }
    }
    if ( defined $tcategory ) { 
      $link = $tcategory;
      $link =~ s/_/ /g;

      $link = "<a href=\"" . $Opts->{'server-url'} . "?title=Category:" . uri_escape($link) . "\">Category:$link</a>";
      $catmsg .= " articles with talk pages in $link";
    }
    $catmsg .= ".<br/>";
  }

  my $disable_count = $params->{'disableCount'} || "";
  if ( $disable_count eq 'on' ) { $disable_count = 1; }
  my $total = 'Disabled';
  my @row;

  if ( ! $disable_count ) { 
    my $sthcount = $dbh->prepare($queryc);
    $sthcount->execute(@qparamc);
    
    @row = $sthcount->fetchrow_array() ;
    $total = $row[0] || 'Error';
  }  

  print "<div class=\"navbox\">\n";
  print_header_text($project);
  print  $catmsg . $review_msg . $release_msg 
      . "<b>Total results:&nbsp;" . $total . "</b>&nbsp;&nbsp;&nbsp;" 
        . " Displaying up to $limit results beginning with #" 
        . ($offset +1) . "\n";
  print "</div>\n";

  print_bignotice();

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
          <span>Number of incoming wikilinks</span>
        </a>
    </th>  
    <th><a class="info">LL
          <span>Number of interlanguage links</span>
        </a>
    </th>  
    <th><a class="info">Hits
          <span>Estimated daily hitcount (page views).</span>
        </a>
    </th>  
    <th><a class="info">EI
          <span>The combined "external interest score" (see the Guide for details)</span>
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

    $row[2] =~ s/_/ /g;

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
      my ( $external_pl, $external_ll, $external_hc, $external_ei );
      $external_pl = $row[13] || "0";
      $external_ll = $row[14] || "0";
      $external_hc = $row[15] || "0";
      $external_ei = $row[16] || "0";
      print << "HERE";
       <td class="external">$external_pl</td>
       <td class="external">$external_ll</td>
       <td class="external">$external_hc</td>
       <td class="external">$external_ei</td>
HERE
    }

    print "<td class=\"score\">" . $row[11] 
             . make_workingselection_html($row[12], $row[2]) . "</td>\n";

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
    my $newURL = make_list_link() . $params_enc   # removed "?" 2010-12-30
              . "&offset=" . ($limit + $offset + 1);    
    print "<a href=\"" . $newURL . "\">Next $limit entries</a>";
  }
  print "\n";
}
  

###########################################################################

sub ratings_table_intersect { 
  my $params = shift;
  my $projects = shift;

  my $projecta = $params->{'projecta'};
  return if ( ! defined $projecta);
  $projecta =~ s/ /_/g;

  my $projectb = $params->{'projectb'};
  return if ( ! defined $projectb);
  $projectb =~ s/ /_/g;

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
                FROM " . db_table_prefix() . "ratings as ra 
                JOIN " . db_table_prefix() . "ratings as rb 
                    on rb.r_article = ra.r_article
                              AND ra.r_namespace = rb.r_namespace
                LEFT JOIN " . db_table_prefix() . "workingselection 
                            ON  ra.r_namespace = 0
                              AND ws_article = ra.r_article 
                WHERE ra.r_project = ? AND rb.r_project = ?";

  my @qparam = ($projecta, $projectb);
  my @qparamc = ($projecta, $projectb);

  $query = "SELECT ra.r_namespace, ra.r_article, ra.r_importance, ra.r_quality,
       rb.r_importance, rb.r_quality, rel_0p5_category,
       rev_value, ISNULL(rel_0p5_category) as null_rel,
       ISNULL(rev_value) as null_rev, ra.r_score, rb.r_score, ws_revid as wsel ";

  my $show_external = ($params->{'showExternal'} eq "on");
  if ( $show_external ) {
    $query .= "      , sd_pagelinks, sd_langlinks, sd_hitcount, sd_external \n";
  }

  $query .= "FROM " . db_table_prefix() . "ratings as ra ";


  if ( $show_external ) {
    $query .= "   LEFT JOIN " . db_table_prefix() . "selection_data 
             ON ra.r_namespace = 0 AND ra.r_article = sd_article ";
  }
  
  $query .= " JOIN " . db_table_prefix() . "ratings as rb ON rb.r_article = ra.r_article 
                      AND ra.r_namespace = rb.r_namespace ";

  my $sort = $params->{'sorta'};
  my $sortb = $params->{'sortb'};
  $query .= sort_sql($sort, "a", "ra") . " " 
      . sort_sql($sortb, "b", "ra") ." ";

  $query .= " LEFT JOIN " . db_table_prefix() . "releases ON ra.r_namespace = 0 
                  AND ra.r_article = rel_article ";
  $query .= " \n   LEFT JOIN " . db_table_prefix() . "reviews ON ra.r_namespace = 0 
                     AND ra.r_article = rev_article ";

  $query .= " \n LEFT JOIN " . db_table_prefix() . "workingselection ON  ra.r_namespace = 0
                       AND ws_article = ra.r_article ";

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
    $query .= " AND ra.r_score >= ?";
    $queryc .= " AND ra.r_score >= ?";
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

  my $review_filter = normalize_review_filter($params->{'reviewFilter'});
  my $release_filter = normalize_release_filter($params->{'releaseFilter'});
  my ($review_sql, $review_msg) = review_sql($review_filter);
  my ($release_sql, $release_msg, $release_join) = release_sql($release_filter);

  $query .= $review_sql;
  $queryc .= $review_sql;

  $query .= $release_sql;
  $queryc .= $release_sql;
  $queryc =~ s/RELEASE-MARKER/$release_join/;

  if ( defined $params->{'diffonly'} ) { 
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

  if ( defined $params->{'debug'} ) { 
     print "<pre>QQ:\n$query</pre>\n";
     print join "<br/>", @qparam;
  }

  $query .= " OFFSET ?";
  push @qparam, $offset;

# print "<pre>QC: $queryc</pre><br/>\n";
#   print join "<br/>", @qparam;

  my $sthcount = $dbh->prepare($queryc);
  $_ = $sthcount->execute(@qparamc);
  my @row = $sthcount->fetchrow_array()  ;

  print "<div class=\"navbox\">\n";
  print_header_text($projecta);
  print_header_text($projectb);

  my $total = $row[0];
  print  $review_msg . $release_msg ;
  print  "<b>Total results: " . $total . "</b>&nbsp;&nbsp;&nbsp;\n";
  print " Displaying up to $limit results beginning with #"  
        . ($offset +1);
  print "</div>\n";

  print_bignotice();

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
  <th colspan="1" class="spacer">&nbsp;</th>
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
          <span>Estimated average daily hitcount of this page.</span>
        </a>
    </th>
    <th><a class="info">EI
          <span>The combined "external interest score" (see the Guide for details).</span>
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
    print "<td class=\"score\">$row[10]"
             . make_workingselection_html($row[12], $row[1]) . "</td>\n";
    print "<td class=\"spacer\">&nbsp;</td>\n";
    print "    " . get_cached_td_background($row[4]) . "\n";
    print "    " . get_cached_td_background($row[5]) . "\n";
    print "<td class=\"score\">$row[11]"
             . make_workingselection_html($row[12], $row[1]) . "</td>\n";
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
      my ( $external_pl, $external_ll, $external_hc, $external_ei );
      $external_pl = $row[13] || "0";
      $external_ll = $row[14] || "0";
      $external_hc = $row[15] || "0";
      $external_ei = $row[16] || "0";
      print << "HERE";
       <td class="external">$external_pl</td>
       <td class="external">$external_ll</td>
       <td class="external">$external_hc</td>
       <td class="external">$external_ei</td>
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
  my $filter_category = $params->{'filterCategory'} || "";

  my $review_filter = $params->{'reviewFilter'} || 0;
  if ( ! (    $review_filter =~ /^\d+$/ 
           && $review_filter >= 0 
           && $review_filter <= 5 ) ) { 
    $review_filter = 0;
  }

  my $release_filter = $params->{'releaseFilter'} || 0;
  if ( ! (    $release_filter =~ /^\d+$/ 
           && $release_filter >= 0 
           && $release_filter <= 5 ) ) { 
    $release_filter = 0;
  }

  my $review_html = review_filter_html($review_filter);
  my $release_html = release_filter_html($release_filter);

  my $namespace = defined($params->{'namespace'}) ? $params->{'namespace'} : "";

  my $category = $params->{'category'} || "";
  my $tcategory = $params->{'categoryt'} || "";

  my $disable_count = $params->{'disableCount'} || "";

  my $disable_count_checked = "";
  if ( $disable_count eq 'on' ) { 
    $disable_count_checked = "checked=\"yes\" ";
  }

  my $intersect_checked = "";
  if ( $intersect eq 'on' ) { 
    $intersect_checked = "checked=\"yes\" ";
  } 

  my $filter_release_checked = "";
  if ( $filter_release eq 'on' ) { 
    $filter_release_checked = "checked=\"yes\" ";
  }

  my $filter_category_checked = "";
  if ( $filter_category eq 'on' ) { 
    $filter_category_checked = "checked=\"yes\" ";
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
  if ( defined $params->{'diffonly'} ) {
    $diffonly_checked = "checked";
  }

  my $sorts = sort_orders();
  my $s;
  my $sort_html = "";
  my $sort_htmlb = "";
  foreach $s ( sort {$a cmp $b} keys %$sorts ) {
    $sort_html .=  "<option value=\"$s\"";
    $sort_htmlb .=  "<option value=\"$s\"";
    if ( $s eq $params->{'sorta'} ) { 
      $sort_html .= " selected"; 
    }
    if ( $s eq $params->{'sortb'} ) { 
      $sort_htmlb .= " selected"; 
    }
    $sort_html .= ">$s</option>\n";
    $sort_htmlb .= ">$s</option>\n";
  }

  print << "HERE";
<form>
  <input type="hidden" name="run" value="yes"/>

<div class="formfirstcolumn">
<fieldset class="inner">
  <legend>First project</legend>
  Project: <input type="text" value="$projecta" name="projecta"/><br/>
  <a class="info">
    Page namespace
        <span>The numeric namespace of the page. The main article 
              namespace is number 0. Use even numbers only. 
        </span>
  </a> <input type="text" value="$namespace" name="namespace"/><br/>
  Page title: <input type="text" value="$pagename" name="pagename"/><br/>

  <a class="info">
    Quality
        <span>For example: FA-Class, FL-Class, A-Class, B-Class, 
Start-Class, Stub-Class, List-Class. Only one value can be specified. 
</span>
  </a>  <input type="text" value="$quality" name="quality"/><br/>
  <a class="info">
    Importance:
        <span>For example: Top-Class, High-Class, Mid-Class, Low-Class. Only one value can be specified. </span>
  </a>   <input type="text" value="$importance" name="importance"/><br/>
  <a class="info">
    Score
        <span>A numeric score used to select articles for release 
versions. Typical values range from 0 to 3000. 
     </span>
  </a> &ge; <input size="5" type="text" value="$score" name="score"/><br/>
  <input type="checkbox" $pagename_wc_checked name="pagenameWC" />
      Treat page title as a
      <a href="http://en.wikipedia.org/wiki/Regular_expression">regular 
           expression</a><br/>
  <input type="checkbox"  name="showExternal" $show_external_checked />
      Show external interest data<br/>
  <div class="note">Note: leave any field blank to select all values. 
Move your mouse over <a class="info">underlined terms
<span>This is an example</span></a> for additional information.
</div>
  <div class="submit">
    <input type="submit"  value="Generate list"/>
  </div>
</fieldset>

<fieldset class="inner">
  <legend>Second project</legend>
  <input type="checkbox"  name="intersect"  $intersect_checked rel="secondproj"/>
    <b>Specify second project</b><br/>
  <div rel="secondproj">
    Project name <input type="text" value="$projectb" name="projectb"/><br/>
    Quality <input type="text" value="$qualityb" name="qualityb"/><br/>
    Importance <input type="text" value="$importanceb" 
                      name="importanceb"/><br/>
    <input type="checkbox" name="diffonly" $diffonly_checked>
       Show only pages with differing quality ratings</input><br/>
  </div>
</fieldset>

</div> <!-- formfirstcolumn -->
<div class="formsecondcolumn">

<fieldset class="inner">
  <legend>Output options</legend>
  Results per page: <input type="text" value="$limit" name="limit"/><br/>
  Start with result # <input type="text" value="$offset" name="offset"/><br/>
  Primary sort by <select name="sorta">
      $sort_html
      </select><br/>
  Secondary sort by <select name="sortb">
      $sort_htmlb
      </select><br/>
  <div class="note">
  Note: sorting is done relative to the first project.</div>
</fieldset>

<fieldset class="inner">
  <legend>Release / review data</legend>
  <input type="checkbox"  $filter_release_checked name="filterRelease" 
          rel="release"/>
  <b>Filter release / review data</b><br/>
  <div rel="release">
    Review status $review_html<br/>
<!--     <div class="note">Filtering by release is not yet implemented</div> -->
Release status $release_html<br/>
  </div>
</fieldset>

<fieldset class="inner">
  <legend>Category filter</legend>
  <input type="checkbox"  $filter_category_checked name="filterCategory" 
          rel="category"/>
  <b>Filter by category</b>
  <div rel="category">
  Article category: <input type="text" value="$category" name="category"/><br/>
  Talk category: <input type="text" value="$tcategory" name="categoryt"/><br/>
  </div>
</fieldset>


<br/>
</div> <!-- formsecondcolumn -->
</form>
<div class="bottomcontent">&nbsp;</div>
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
      print "Data for <b>" . get_cached_link_from_api("[[$wikipage]]") . "</b> "; 
    } else {
      print "Data for <b>" . get_cached_link_from_api("[[$wikipage|$shortname]]") . "</b> ";
    }
  } else { 
    print " Data for all projects ";
  }

  print "(<b>list</b> \| <a href=\"" 
  . $tableURL . "\">summary table</a>)<br/>\n";
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
            'Article title' => 'r_namespace asc, r_article asc'
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
  } elsif ( $sort eq 'Article title' ) { 
    $query .= ' ra.r_namespace asc, ra.r_article ';
  } else {
    $query .= " " . $prefix . "r_project";
  }

  if ( $sort =~ /reverse/ ) { 
    if ( ($sort =~ /Project/) || ($sort eq 'Article title') || ($sort =~ /Review/) ) { 
      $query .= ' DESC';
    } else {
      # no
    }
  } else {
    if ( ($sort =~ /Project/) || ($sort =~ /Review/) || ($sort eq 'Article title') ) { 
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
       || $sort eq 'Score'  || $sort eq 'Article title') { 
    # No additional SQL needed
  } elsif ( $sort eq 'Importance' || $sort eq 'Importance (reverse)' ) { 
    $query .=   "   JOIN " . db_table_prefix() . "categories AS c$which
                     ON " . $ratings . "r_project = c$which.c_project
                     AND c$which.c_type = 'importance'
                     AND c$which.c_rating = " . $ratings ."r_importance\n ";
  } elsif ( $sort eq 'Quality' || $sort eq 'Quality (reverse)' ) { 
    $query .=   " JOIN " . db_table_prefix() . "categories AS c$which
                     ON " . $ratings . "r_project = c$which.c_project
                     AND c$which.c_type = 'quality'
                     AND c$which.c_rating = " . $ratings . "r_quality\n ";
  } else { 
    die "Unrecognized sort key in sort_sql\n";
  }
  
  return $query;
}

##########################################################################

sub release_filter_html {

  my $which = shift;
  my @types = ( 'All articles',             # 0 
                '0.8 provisional selection',  # 1
                );                    

  my $html = "<select name=\"releaseFilter\">\n";
  for ( my $i = 0; $i < scalar @types; $i++ ) { 
    $html .= "<option value=\"$i\"";
    if ( $which == $i ) { 
      $html .= " selected ";
    }
    $html .= ">" . $types[$i] . "</option>\n";
  }
  $html .= "</select>\n";

  return $html;

}

sub review_filter_html { 
  my $which = shift;
  my @types = ( 'All articles',             # 0 
                'FA, FL, and GA',           # 1
                'FA and FL' ,               # 2
                'FA',                       # 3
                'FL',                       # 4
                'GA' );                     # 5

  my $html = "<select name=\"reviewFilter\">\n";
  for ( my $i = 0; $i < scalar @types; $i++ ) { 
    $html .= "<option value=\"$i\"";
    if ( $which == $i ) { 
      $html .= " selected ";
    }
    $html .= ">" . $types[$i] . "</option>\n";
  }
  $html .= "</select>\n";

}

##########################################################################

sub release_sql { 
  my $release_filter = shift;
  my $msg;
  my $sql;
  my $join;

  if ($release_filter == 1 ) { 
    $msg = "<i>Showing only articles in the 0.8 provisional selection</i><br/>\n";
    $sql = " and not isnull(ws_article)";
    $join= " \n LEFT JOIN " . db_table_prefix(). "workingselection ON  r_namespace = 0
                       AND ws_article = r_article ";

  } else {
    $msg = "";
    $sql = "";
    $join = "";
  } 

  return ($sql, $msg, $join);
}


sub review_sql { 
  my $review_filter = shift;
  my $msg;
  my $sql;

  if ( $review_filter == 0 )  {
    # All articles - relax
    $msg = "";
    $sql = "";  
  } elsif ( $review_filter == 1 )  {
    # FA FL and GA
    $sql = " AND NOT ISNULL(rev_value) ";
    $msg = "Showing FA, FL, and GA articles only.<br/>\n";
  } elsif ( $review_filter == 2 )  {
    # FA and FL
    $sql = " AND (rev_value = 'FA' OR rev_value = 'FL') ";
    $msg = "Showing FA and FL articles only.<br/>\n";
  } elsif ( $review_filter == 3 )  {
    # FA
    $sql = " AND (rev_value = 'FA') ";
    $msg = "Showing FA articles only.<br/>\n";
  } elsif ( $review_filter == 4 )  {
    # FL
    $sql = " AND (rev_value = 'FL') ";
    $msg = "Showing FL articles only.<br/>\n";
  } elsif ( $review_filter == 5 )  {
    # GA
    $msg = "Showing GA articles only.<br/>\n";
    $sql = " AND (rev_value = 'GA') ";
  }
  return ($sql, $msg);
}

##########################################################################

sub normalize_review_filter { 
  my $review_filter = shift || 0;
  if ( ! (    $review_filter =~ /^\d+$/ 
           && $review_filter >= 0 
           && $review_filter <= 5 ) ) { 
    $review_filter = 0;
  }
  return $review_filter;
}

sub normalize_release_filter { 
  my $release_filter = shift || 0;
  if ( ! (    $release_filter =~ /^\d+$/ 
           && $release_filter >= 0 
           && $release_filter <= 1 ) ) { 
    $release_filter = 0;
  }
  return $release_filter;
}

##########################################################################

sub print_bignotice { 
  print "<div class=\"bignotice\">\n";
  print $Opts->{'list2-bignotice'};
  print "</div>\n";
}

