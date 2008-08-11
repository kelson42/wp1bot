#!/usr/bin/perl
use strict;

use Math::Round;

#### Tie databases

use BerkeleyDB;
my %iwCount;
my %hitCount;
my %plCount;

tie %hitCount, 'BerkeleyDB::Hash', -Flags => DB_RDONLY,  
               -Filename => "../DB/HC.db"
   or die "Couldn't tie file hc: $!; aborting";

tie %iwCount, 'BerkeleyDB::Hash', -Flags => DB_RDONLY, 
              -Filename => '../DB/IW.db'
 or die "Couldn't tie file iw: $!; aborting";

tie %plCount, 'BerkeleyDB::Hash', -Flags => DB_RDONLY, 
              -Filename => '../DB/PL.db'
 or die "Couldn't tie file pl: $!; aborting";


#### Read project data

open IN, "<", $ARGV[0] or die;

my $projects = read_project_articles();

#my $proj = $ARGV[0];
#
#if ( ! defined $projects->{$proj} ) { 
#  print "No info for project '$proj'\n";
#  exit;
#}

open OUT, ">", "table.html";
print OUT << "HERE";
<html>
<head>
<meta http-equiv="Content-Type" CONTENT="text/html; charset=utf-8">
</head>
<body>
<table border="1">
<tr>
<td>Project</td>
<td>Article(s)</td>
<td>Hitcount</td>
<td>IW links</td>
<td>PL links</td>
<td>Score</td>
</tr>
HERE

open OUTC, ">", "table.csv";
print OUTC << "HERE";
Project	Articles	Hitcount	PL count	IW count	Score
HERE

my $proj;

foreach $proj ( sort keys %$projects ) { 

  print "Project: $proj\n";
  my @arts = split / /, $projects->{$proj};

  my $hits = 0;
  my $iw_links = 0;
  my $pl_links = 0;

  my $art;
  foreach $art ( @arts ) { 
    print "Art: $art";
    $hits += $hitCount{$art};
    $pl_links += $plCount{$art};
    $iw_links += $iwCount{$art};
    print "\tHits: $hits\tPL $pl_links\tLL $iw_links\n";
  }

  print "Final: \tHits: $hits\tPL $pl_links\tLL $iw_links\n";

## From Martin: 
## 50*log_{10}(hits) + 100*log_{10}(linksin) + 250*log_{10}(interwikis)

  my $score = round(50*logten($hits) 
                  + 100 * logten($pl_links) 
                  + 250*logten($iw_links));

  print "$proj $score\n";

  print OUT "<tr>\n<td>$proj</td><td>\n";
  print OUT join "<br/>", @arts;
  print OUT "</td>\n<td>$hits</td>\n<td>$pl_links</td>\n<td>$iw_links</td>\n";
  print OUT "<td>$score</td>\n</tr>\n";

  print OUTC join "\t", ($proj, (join "; ", @arts), $hits, $pl_links,
                         $iw_links, $score);
  print OUTC "\n";

}

print OUT "</table>\n</body>\n</html>";
close OUT;
exit;

################################################

sub read_project_articles {
  my $projects = {};

  my ($line, $proj, $arts);

  while ( $line = <IN> ) {
    chomp $line;
    ($proj, $arts) = split / /, $line, 2;
    $projects->{$proj} = $arts;   
  }

  return $projects;
}

################################################

sub logten {
  my $n = shift;
  if ( $n < 1) { return 0; }
  return log($n)/log(10);
}

