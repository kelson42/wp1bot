#!/usr/bin/perl

use Data::Dumper;
use URI::Escape;
use strict;

use lib '/home/veblen/perl/share/perl/5.8.8';
use Tie::Comma;  # $comma{'3432523'} is '3,432,523'

use POSIX 'ceil';


select STDOUT; 
$| = 1; #Turn off output buffering 

#####################################################################
## Global vars

my $threshold = 1300;  # Score at which articles are selected
my %projCount;         # Count all articles per project
my %projCountOver;     # Count selected articles per project
my %projPages;         # Count how many html pages each project uses

my $data = {};         # Database of all articles
my $dataSelected = {}; # Database of all selected articles by project
my %uniqarts;          # Database of selected articles by name
my %artsOver;
my %arts;

my $date = `/bin/date +'%A, %d %B %Y, %R %Z'`;
chomp $date;

#####################################################################
# Main routine

my @projects;
my $project;
my $i = 0;

open FIND, "find CSV/ -type f -print|";
while ( $project = <FIND> ) { 
  chomp $project;
  $project =~ s/^CSV\///;
  $project =~ s/.txt$//;

  # Selected.csv is made by this script, it isn't an input
  next if ( $project eq 'Selected'); 
   
#  next unless ($project eq 'Album'); 
  $i++;
  print "Project $i: $project\n";
  make_table($project);
  push @projects, $project;
}
close FIND;

@projects = sort {$a cmp $b;} @projects;

#####################################################################
##############################################################
##############################################################
### Make tables and csv for selected articles

my $page;
my $sortf;
my $i;
my @selArts;

open CSV, ">CSV/Selected.txt";

print "Reading selected articles\n";
foreach $project (@projects)  {
  $i = 0;
  if ( defined $dataSelected->{$project} ) { 
    $sortf = byname($project);
    foreach $page ( sort $sortf values %{$dataSelected->{$project}} ) { 
      $i++;
      push @selArts, $page;
      print_csv_line($page);
    }
  }
}
close CSV;


#####################################################################
# Tables of selected articles

do_pagination('selected', 'project', \@selArts);

$sortf = byscore();
my @a = sort $sortf values %uniqarts;
do_pagination('selected', 'score', \@a );

#####################################################################
# Make overall index

open OUT, ">HTML/index.html";

my $total = scalar keys %arts;
my $totalOver = scalar keys %uniqarts;
my $totalDups = 0;

&print_header("Wikipedia release version selection data");
&print_selection_info();
&print_index_table_header($project);

my $projenc;
foreach $project ( sort {$a cmp $b} keys %projCount ) { 
  next if ( $projCount{$project} == 0);

  $projenc = $project;
  $projenc =~ s/_/ /g;
  $projenc =~ s/WikiProject Massively multiplayer online games/WikiProject MMOG/;
  $projenc = "<span class=\"projname\">$projenc</span><br/>". 
             "&nbsp;<a href=\"CSV/$projenc.txt\">csv</a>," .
             " <a href=\"http://en.wikipedia.org/wiki/Wikipedia:Version_1.0_Editorial_Team/" . $project . "_articles_by_quality_statistics\">stats</a>, <a href=\"http://en.wikipedia.org/wiki/Wikipedia:WikiProject $projenc\">home</a>";

  print OUT << "EOF";
<tr>
  <td class="project">$projenc</td>
  <td class="projcount">$projCount{$project}</td>
  <td class="projcountover">$projCountOver{$project}</td>
EOF
$totalDups += $projCountOver{$project};

$projenc = "<a href=\"$project.s0.html\">Selected articles</a><br/>";
$projenc .= "<a href=\"$project.0.html\">All articles</a>";

if ( $projPages{$project} > 2) { 
  $projenc .= " (";
  for (my $i = 1; $i <= $projPages{$project}; $i++) { 
    $projenc .= "<a href=\"$project.$i.html\">$i</a>";
    if ( $i < $projPages{$project} ) { 
      $projenc .= " ";
    }
  }
  $projenc .= ")";
}

print OUT << "EOF";
  <td class="lists">$projenc</td>
</tr>
EOF
}

print OUT << "EOF";
<tr>
  <td class="project total">Total</td>
  <td class="projcount total">$total</td>
  <td class="projcountover total">$totalOver</td>
  <td/>
</tr>
EOF

print "\nTotal: $total / selected: $totalOver , $totalDups\n";

print_footer();
close OUT;

print "Done.\n";

exit;

#####################################################################
#####################################################################

sub make_table {
  my $project = shift;
  my $count = 0;
  my $countover = 0;

  my @parts;
  my @articles;
  my @selArticles;

  open IN, "<CSV/$project.txt";
  while ( <IN> ) { 
    chomp;
    $count++;

# CSV format cheat sheet:
# Mathematics|Mathematics|A|Top|11430|145|249765|2016|2216
#  0           1          2 3    4    5    6      7    8

    @parts =  split /\|/, $_, 9;

    if ( $parts[8] >= $threshold) { 
       $countover++; 
       if ( ! defined $dataSelected->{$project} ) {
         $dataSelected->{$project} = {};
       }
       $dataSelected->{$project}->{$parts[0]} = [@parts];
       if ( ! defined $uniqarts{$parts[0]}) { 
         $uniqarts{$parts[0]} =  [@parts];
       } else { 
         if ( $parts[8] > ${$uniqarts{$parts[0]}}[7] ) {
           $uniqarts{$parts[0]} =  [@parts];
        }
      }
      push @selArticles, [@parts];
    }

    if ( ! defined $data->{$project} ) {
      $data->{$project} = {};
    }
    push @articles, [@parts];
  }
  close IN;

  $projCount{$project} = $count;
  $projCountOver{$project} = $countover;

  my $sortf = byscore();
  @articles = sort $sortf @articles;
  do_pagination('project', $project, \@articles);
  make_project_html_page('project', "Selected articles for WikiProject:$project",
                         $project, 's0', 0, \@selArticles);
  print "\n";
}

#####################################################################
# Create paginated sequeqnce of pages for a project

sub do_pagination  { 
  my $type = shift;
  my $project = shift;
  my $articles = shift;

  my $pageSize = 1000;
  my $pageNum = 0;
  my $pageCount = ceil((scalar @$articles) / $pageSize);  
  $projPages{$project} = $pageCount;
  my @pages;
  my $line;
  my $header;

  if ( $type eq 'project' ) { 
    $header = "Selection data for WikiProject:$project";
  } elsif ( $type eq 'selected' ) { 
    if ( $project eq 'project' ) { 
      $header = "Selected articles by project";
    } elsif ( $project eq 'score' ) { 
      $header = "Selected articles by score";
    } else {
      die "Bad type: $project";
    }
    $project = $type . "." . $project;
  }

  if ( $pageCount > 2) { 
    make_project_html_page($type, $header, $project, 0, $pageCount, $articles);

    while ( $line = shift @$articles ) { 
      push @pages, $line;
      if ( scalar @pages >= $pageSize) { 
        $pageNum++;
        make_project_html_page($type, $header, $project, $pageNum, 
                                      $pageCount, \@pages);
        @pages = ();
      }
    }   
    $pageNum++;
    make_project_html_page($type, $header, $project, $pageNum, 
                           $pageCount, \@pages);
  } else { 
    make_project_html_page($type, $header, $project, 0, 0, $articles);
  }
}

#####################################################################

sub make_project_html_page { 
  my $type = shift;
  my $header = shift;
  my $project = shift;
  my $pagenum = shift;
  my $maxpagenum = shift;
  my $projData = shift;
  my $line;

  print ".";

  open OUT, ">HTML/$project.$pagenum.html";
  &print_header($header);

  if ( $type eq 'project' ) { 
    &print_project_table_header($project, $header, $pagenum, $maxpagenum);
  } elsif ( $type eq 'selected' ) { 
    print_selected_table_header($project, $header, $pagenum, $maxpagenum);
  } else { 
    die "Bad type: $type";
  }

  foreach $line ( @$projData ) { 
    &print_line($line);
  }
  &print_footer();
  close OUT;
}

###############################################################

sub print_footer { 
  my $count = shift;
  my $countover = shift;

  print OUT << "EOF";
</tbody>
</table>
</div>
</body>
</html>
EOF
}

################################################################

sub print_csv_line { 
  my $line = shift;
 print CSV (join "|", @$line) . "\n";
}

#################################################################

sub print_line {

#CSV format cheat sheet
#Mathematics|Mathematics|A|Top|11430|145|249765|2016|2216
#  0           1          2 3    4    5    6      7    8

  my $line = shift;
  my ($article, $proj, $quality, $importance,
      $pl_count, $iw_count, $hit_count, $scorei, $score) = @$line;

  my $thresholdClass = "under";
  my $icons = "";

  if ( $score >= $threshold ) { 
    $thresholdClass = "over";
    $artsOver{$article} = 1;
    $icons .= "<span class=\"selected\">S</span>";
  }

  $arts{$article} = 1;
  $importance =~ s/Unassessed importance/Unassessed/;
  my $link = make_link($article);

  print OUT << "EOF";
<tr class="$thresholdClass">
  <td class="icons">$icons</td>
  <td class="article">$link</td>
  <td class="project">$proj</td>
  <td class="quality $quality">$quality</td>
  <td class="importance $importance">$importance</td>
  <td class="pagelinks">$comma{$pl_count}</td>
  <td class="interwikis">$comma{$iw_count}</td>
  <td class="hitcount">$comma{$hit_count}</td>
  <td class="impscore">$comma{$scorei}</td>
  <td class="score $thresholdClass">$comma{$score}</td>
</tr>
EOF
}

################################################################

sub print_header {
  my $title = shift;
  print OUT << "EOF";
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" 
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" 
dir="ltr">
        <head>
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8" />
<script type="text/javascript" src="table.js"></script>
<link rel="stylesheet" type="text/css" href="table.css" media="all" />
<title>$title</title>
</head>
<body>
<div class="headline">
Wikipedia release version ratings data
</div>

EOF
}

################################################################

sub print_project_table_header {
  my $project = shift;
  my $header = shift;
  my $projenc = $project;
  my $pagenum = shift;
  my $maxpagenum = shift;
  $projenc =~ s/_/ /g;

  print_messagebox($project, 1);

  print OUT << "EOF";
<div class="content">
<table class="project">
<tr>
<td class="projectdata">$header</td>
EOF

  if ( $maxpagenum > 2 && $pagenum > 0) { 
    my $pagetmp;

    if ( $pagenum > 1) { 
      $pagetmp = $pagenum - 1;
      print OUT << "EOF";
  <td class="spacer" />
  <td class="index"><a href="$project.$pagetmp.html">&larr; $pagetmp</a></td>
EOF
    }

    print OUT << "EOF";
  <td class="spacer" />
  <td class="curpage">Page $pagenum of $maxpagenum</td>
EOF

    if ( $pagenum < $maxpagenum) { 
      $pagetmp = $pagenum + 1;
      print OUT << "EOF";
  <td class="spacer" />
  <td class="index"><a href="$project.$pagetmp.html">$pagetmp &rarr;</a></td>
EOF
    }
  }

  if ( $pagenum != 0) { 
    print OUT << "EOF";
  <td class="spacer" />
  <td class="index"><a href="$project.0.html">All articles ($projCount{$project})</a></td>
EOF
  }

  if ( $pagenum =~ /^s/) {  
    print OUT << "EOF";
  <td class="spacer" />
  <td class="index"><a href="$project.0.html">All ($projCount{$project})</a></td>
EOF
  } else { 
    print OUT << "EOF";
  <td class="spacer" />
  <td class="index"><a href="$project.s0.html">Selected ($projCountOver{$project})</a></td>
EOF
  }

  print OUT << "EOF";
<td class="spacer" />
<td class="index"><a href="index.html">Index</a></td>
</tr></table>

<table class="table-autosort results table-stripeclass:alternate table-autostripe">
<thead>
<tr class="header">
  <th class="icons"/>
  <th class="table-sortable:default article">Article<br/></th>
  <th class="table-sortable:default project">Project<br/></th>
  <th class="table-sortable:default quality">Quality<br/></th>
  <th class="table-sortable:default importance">Importance<br/></th>
  <th class="table-sortable:numeric pagelinks">Page<br/>links<br/></th>
  <th class="table-sortable:numeric interwikis">Interwiki<br/>links<br/></th>
  <th class="table-sortable:numeric hitcount">Hit<br/>count<br/></th>
  <th class="table-sortable:numeric impscore">Importance<br/>Score</th>
  <th class="table-sortable:numeric score">Overall<br/>Score</th>
</tr>
</thead>
<tbody>
EOF
}

################################################################

sub print_selected_table_header {
  my $type = shift;
  my $header = shift;
  my $pagenum = shift;
  my $maxpagenum = shift;

  print_messagebox();

  print OUT << "EOF";

<div class="content">
<table class="project">
<tr>
  <td class="projectdata">$header</td>
EOF

  if ( $maxpagenum > 2 && $pagenum > 0) { 
    my $pagetmp;

    if ( $pagenum > 1) { 
      $pagetmp = $pagenum - 1;
      print OUT << "EOF";
  <td class="spacer" />
  <td class="index"><a href="$type.$pagetmp.html">&larr; $pagetmp</a></td>
EOF
    }

    print OUT << "EOF";
  <td class="spacer" />
  <td class="curpage">Page $pagenum of $maxpagenum</td>
EOF

    if ( $pagenum < $maxpagenum) { 
      $pagetmp = $pagenum + 1;
      print OUT << "EOF";
  <td class="spacer" />
  <td class="index"><a href="$type.$pagetmp.html">$pagetmp &rarr;</a></td>
EOF
    }
  }

  if ( $type eq 'selected.project') { 
    print OUT << "EOF";
  <td class="spacer"/>
  <td class="index"><a href="selected.project.0.html">All</a></td>
  <td class="spacer"/>
  <td class="index"><a href="selected.score.0.html">Selected articles by score</a></td>
EOF
  } elsif ( $type eq 'selected.score') { 
    print OUT << "EOF";
  <td class="spacer"/>
  <td class="index"><a href="selected.score.0.html">All</a></td>
  <td class="spacer"/>
  <td class="index"><a href="selected.project.0.html">Selected articles by project</a></td>
EOF
  } else { 
    die "Bad type: $type";
  }
	
  print OUT << "EOF";
  <td class="spacer"/>
  <td class="index"><a href="index.html">Index</a></td>
</tr>
</table>

<table class="table-autosort results table-stripeclass:alternate table-autostripe">
<thead>
<tr class="header">
  <th class="icons"/>
  <th class="table-sortable:default article">Article<br/></th>
  <th class="table-sortable:default project">Project<br/></th>
  <th class="table-sortable:default quality">Quality<br/></th>
  <th class="table-sortable:default importance">Importance<br/></th>
  <th class="table-sortable:numeric pagelinks">Page<br/>links<br/></th>
  <th class="table-sortable:numeric interwikis">Interwiki<br/>links<br/></th>
  <th class="table-sortable:numeric hitcount">Hit<br/>count<br/></th>
  <th class="table-sortable:numeric score">Importance<br/>Score</th>
  <th class="table-sortable:numeric score">Overall<br/>Score</th>
</tr>
</thead>
<tbody>
EOF
}

######################################################################

sub print_messagebox { 
  my $project = shift;
  my $key = shift;

  my $lnk = "";

  if ( defined $project && ! $project eq '') { 
    $lnk = " Project-specific discussion is at the <a href=\"http://en.wikipedia.org/wiki/Wikipedia talk:WikiProject_$project\">WikiProject's discussion page</a>."
  }

  if ( defined $key ) { 
    $key = "\n<li><span class=\"messageb\">Key:</span> <span class=\"selected\">S</span>: selected article."
  } else { 
    $key = "";
  }

  print OUT << "EOF";
<div class="messagebox">
<ul>
<li><span class="messageb">Questions or comments?</span> Centralized discussion is at the <a href="http://en.wikipedia.org/wiki/Wikipedia talk:Version 1.0 Editorial Team/SelectionBot">Release Version discussion page</a>.$lnk</li>
<li><span class="messageb">Warning:</span> pages that list more than a few hundred articles may be very slow to load or sort.</li>
<li><span class="messageb">Last updated:</span> $date.</li>$key
</ul>
</div>
EOF
}

#################################################################

sub print_index_table_header {

  print OUT << "EOF";

<div class="content">
<table class="project">
<tr><td class="projectdata">Index of selection data by WikiProject</td>
</tr></table>


<table class="table-autosort results table-stripeclass:alternate table-autostripe results">
<thead>
<tr class="header">
  <th class="table-sortable:default project">Project<br/></th>
  <th class="table-sortable:numeric count">Articles<br/></th>
  <th class="table-sortable:numeric countover">Selected<br/></th>
  <th class="lists">Lists</th>
</tr>
</thead>
<tbody>

EOF
}

#####################################################################

sub make_link { 
  my $article = shift;
  return "<a href=\"http://en.wikipedia.org/wiki/" 
      . uri_escape($article) . "\">$article</a>" .
  " (<a href=\"http://en.wikipedia.org/wiki/Talk:" 
 . uri_escape($article) . "\">talk</a>)";

}

#####################################################################

sub byname {
  my $project = shift;
  return sub { 
    $_ = ${$a}[0] cmp ${$b}[0];
    return $_;
  }
}

sub byscore {
  return sub { 
#  0           1          2 3    4    5    6      7   8
# Mathematics|Mathematics|A|Top|11430|145|249765|2016|2216
   
    #Backwards by score
    $_ = ${$b}[8] <=> ${$a}[8];
    if ( $_ != 0) { return $_; } 

    #Then forewards by name
    $_ = ${$a}[0] cmp ${$b}[0];
    return $_;
  }

}

#####################################################################

sub print_selection_info {
  my $i;

  my $count = $comma{scalar keys %arts};
  my $countOver = $comma{scalar keys %uniqarts};
  my $countOverDups = 0;

  foreach $i ( keys %projCountOver ) {
    $countOverDups += $projCountOver{$i};
  }
  $countOverDups = $comma{$countOverDups};

  print OUT << "EOF";

<div class="selectiondata">

<p class="first"> This page contains data used to select articles for 
the
next <a href="http://en.wikipedia.org/wiki/Wikipedia:Release_Version">release
version</a> of English Wikipedia.
The discussion page for the data collection project (known as 
<b>SelectionBot</b>) is at <a 
href="http://en.wikipedia.org/wiki/Wikipedia%20talk:Version%201.0%20Editorial%20Team/SelectionBot">en:Wikipedia talk:Version 1.0 Editorial Team/SelectionBot</a>.
</p>

<p class="headline">How articles are collated and scored</p>

<p>All data here has been automatically generated. First, a list of 
$count articles was generated using the 
<a href="http://en.wikipedia.org/wiki/Wikipedia:Version_1.0_Editorial_Team"
>Wikipedia 1.0 article assessments</a>. This list includes all articles
that are assessed Start-Class or higher. Additional information about 
the the number of incoming internal links, incoming interwiki links, and 
<a href="http://stats.grok.se">hitcount</a> of the articles is used to 
generate a <b><a 
href="http://en.wikipedia.org/wiki/
Wikipedia:Version_1.0_Editorial_Team/SelectionBot">score</a></b> 
for each article. This score will be used to assist with the choice of 
articles for a release version of Wikipedia.</p>

<p class="headline">Data on selected articles</p>

<p>The list of <b>selected articles by project</b> details all articles 
with score over the threshold of <b>$comma{$threshold}</b>. 
Each article is listed once for each 
WikiProject that assigns it a score meeting the threshold. The list of 
<b>selected articles by score</b> details all the articles with scores 
meeting the threshold, along with a WikiProject that assigns the highest 
score to article.  The <b>CSV data</b> file contains the list of 
selected articles by project in a text format that can be imported into 
a spreadsheet.</p>

<ul>
EOF

  print OUT "<li>Selected articles by score:";
  print OUT "<b>$countOver</b> articles.<br/>";
  print OUT "<a href=\"selected.score.0.html\">All</a>\n (";
  for ( $i = 1; $i <= $projPages{'score'}; $i++) { 
    print OUT "<a href=\"selected.score.$i.html\">$i</a>\n";
    if ( $i < $projPages{'score'} ) { 
      print OUT " ";
    } 
  }
  print OUT ")</li>\n";

  print OUT "<li>Selected articles by project:";
  print OUT " <b>$countOverDups</b> articles with duplicates.<br/>";
  print OUT "<a href=\"selected.project.0.html\">All</a>\n (";
  for ( $i = 1; $i <= $projPages{'project'}; $i++) { 
    print OUT "<a href=\"selected.project.$i.html\">$i</a>\n";
    if ( $i < $projPages{'project'} ) { 
      print OUT " ";
    } 
  }
  print OUT ")</li>\n";


  print OUT << "EOF";
<li><a href="CSV/Selected.txt">CSV data</a>
</ul>

<p>
Additional data about all scored articles for all participating 
WikiProjects is available through the table below.
</p>

<p class="headline">Warning</p>
<p>Some of the pages generated are very large. The data is also 
available in numbered subpages each containing 1,000 or fewer 
articles. Pages larger than 1,000 articles may load and display very 
slowly. Tables can be sorted by clicking the appropriate cell of the 
header, but large tables may sort very slowly and may freeze the 
browser while the sorting is carried out.</p>

<p class="headline">Last update</p>
<p>The data here was generated on $date.</p>
</div>
EOF
}

#####################################################################

__END__
