#!/usr/bin/perl

my $ignoreWhitelist = 0;

use strict;

use BerkeleyDB;
use Encode;
use Data::Dumper;
use Math::Round;
use URI::Escape;

use lib '/home/veblen/VeblenBot';
use Mediawiki::API;

binmode STDOUT, ":utf8";

#####################################################################
# Global vars
my $Data = ();
my %ProjectToQualityCategory;
my %ProjectToImportanceCategory;

my %ClassDesc =  ( "Stub-Class" => "{{Stub-Class}}",
       "Start-Class" => "{{Start-Class}}",
       "B-Class" => "{{B-Class}}",
       "GA-Class" => "{{GA-Class}}",
       "A-Class" => "{{A-Class}}",
       "FA-Class" =>"{{FA-Class}}" );

 my %ImpDesc =  ( "Top-importance" => '{{Top-Class}}',,
       "High-importance" => '{{High-Class}}',
       "Mid-importance" => '{{Mid-Class}}',
       "Low-importance" => '{{Low-Class}}'  );

## Params for naive multiplicative score

my %QualityMultiplier = ( 'FA-Class' => 2,
                          'A-Class' => 2,
                          'GA-Class' => 2,
                          'B-Class' => 2,
                          'Start-Class' => 2,
                          'Stub-Class' => 2 );

my %ImportanceMultiplier = ( 'Top-importance' => 1,
                               'High-importance' => 1,
                               'Mid-importance' => 1,
                               'Low-importance' => 1,
                               'Unused-importance' => 1 );



## Parameters for the score7 formula

my %QualityAdditive = ( 'FA-Class' => 500,
                        'A-Class' => 400,
                        'GA-Class' => 400,
                        'B-Class' => 300,
                        'Start-Class' => 150 ) ;

my %ImportanceAdditive = ( 'Top-importance' => 400,
                           'High-importance' => 300,
                           'Mid-importance' => 200,
                           'Unassessed' => 200,
                           'Low-importance' => 100);

my $HitcountMultiplier = 50;
my $PagelinkMultiplier = 100;
my $InterwikiMultiplier = 250;
my $NoImportanceMultiplier = 4/3;

#####################################################################
# Connect to databases for hitcount, interwiki count, pagelinks count
# and redirects

my %iwCount;
my %hitCount;
my %plCount;
my %Redirects;

tie %hitCount, 'BerkeleyDB::Hash', -Flags => DB_RDONLY,  -Filename => 'DBm/HC.db'
  or die "Couldn't tie file hc: $!; aborting";
tie %iwCount, 'BerkeleyDB::Hash', -Flags => DB_RDONLY, -Filename => 'DBm/IW.db'
 or die "Couldn't tie file iw: $!; aborting";
tie %plCount, 'BerkeleyDB::Hash', -Flags => DB_RDONLY, -Filename => 'DBm/PL.db'
 or die "Couldn't tie file pl: $!; aborting";
tie %Redirects, 'BerkeleyDB::Hash', -Flags => DB_RDONLY, -Filename => 'DBm/RD.db'
 or die "Couldn't tie file rd: $!; aborting";

# Convert article name to database key
sub encode_article {
  my $art = shift;
  $art =~ s/ /_/g;
  return encode('utf8', $art);
}

# Access the redirects database
sub redirected {
  my $art = shift;
  return $Redirects{encode_article($art)};
}

#####################################################################
# Load WikiProject importance scores

my %projectScore;
my @parts;
open IN, "<", "project-scores.csv";

while ( <IN> ) {
  chomp;
  @parts = split /\t/, $_, 6;
  $parts[0] =~ s/_/ /g;
  $projectScore{$parts[0]} = 1000 - $parts[5];
}
close IN;

#####################################################################
# Start running, init api client

my $startTime = time();
my $api = new Mediawiki::API;
$api->base_url('http://en.wikipedia.org/w/api.php');
$api->maxlag(20);
$api->debug_level(3);
$api->login_from_file("/home/veblen/api.credentials");
$api->max_retries(40);

#####################################################################
# Get list of projects with ratings

my $categoryNS = 14;
my $talkNS = 1;

my $pages = $api->pages_in_category('Wikipedia 1.0 assessments', $categoryNS);

my $page;
foreach $page ( @$pages) { 
 if ( $page =~ /^Category:(.*) articles by quality$/) { 
   $ProjectToQualityCategory{$1} = $page;
 } elsif ( $page =~ /^Category:(.*) articles by importance$/) { 
   $ProjectToImportanceCategory{$1} = $page;
 }
}

#####################################################################
# The whitelist limits which projects are considered
my %WhitelistProjects;

open IN, "<ProjectWhitelist";
while ( <IN> ) { 
 chomp;
 $WhitelistProjects{$_} = 1;
}
close IN;

#####################################################################
##############################################
# Get data for projects
my $project;
my $article;

open PR, ">Projects";
foreach $project (sort keys %ProjectToQualityCategory ) { 

  print "Project $project\n";
  my $projenc = $project;
  $projenc =~ s/ /_/g;
  $projenc .= '.txt';

  next unless ( $ignoreWhitelist || defined $WhitelistProjects{$project});
  next if ( -e "CSV/$projenc"); # Don't overwrite
  print PR "$project\n";

  download_ratings_for_project($api, $project);

  ##############################################
  # Make ratings for articles

  my $article;

  foreach $article (keys %{$Data->{$project}}) { 
    $Data->{$project}->{$article}->{'score'} = 
          make_score($article, $project,
                     $Data->{$project}->{$article}->{'quality'},
                     $Data->{$project}->{$article}->{'importance'});
    ($Data->{$project}->{$article}->{'score7'}, 
     $Data->{$project}->{$article}->{'score7i'} ) = 
          make_score7($article, $project,
                     $Data->{$project}->{$article}->{'quality'},
                     $Data->{$project}->{$article}->{'importance'});
  } 

  open OUT, ">CSV/$projenc";
  binmode OUT, ":utf8";

  my $sortf = sort_by_rating_alt($project);

  my $quality_wc;
  my $importance_wc;
  my $score_wc;

  my $iw_wc;
  my $hc_wc;
  my $pl_wc;

  my $threshold = 1;
  my ($score, $scorei, $artenc);

  foreach $article ( sort $sortf keys %{$Data->{$project}}  ) { 
    next unless ($Data->{$project}->{$article}->{'score'} > $threshold);

    $quality_wc = $Data->{$project}->{$article}->{'quality'};
    $quality_wc =~ s/-Class//;

    $importance_wc = $Data->{$project}->{$article}->{'importance'};
    $importance_wc =~ s/-importance//;

    $score = $Data->{$project}->{$article}->{'score7'};
    $scorei = $Data->{$project}->{$article}->{'score7i'};

    $artenc = encode_article($article);

    if ( defined $iwCount{$artenc} ) { 
      $iw_wc = $iwCount{$artenc};
    } else { 
      $iw_wc = 0;
      print "Bad iw $article $artenc\n";
    }

    if ( defined $hitCount{$artenc} ) { 
      $hc_wc = $hitCount{$artenc};
    } else { 
      $hc_wc = 0;
      print "Bad hc $article $artenc\n";
    }

    if ( defined $plCount{$artenc} ) { 
      $pl_wc = $plCount{$artenc};
    } else { 
      $pl_wc = 0;
      print "Bad pl $article $artenc\n";
    }

    print STDOUT "Write $article\n";

    print OUT $article . "|" . $project . "|" 
                 . $quality_wc . "|" . $importance_wc . "|" 
                 . $pl_wc . "|" . $iw_wc . "|" .   $hc_wc 
                 . "|" . $scorei . "|" . $score . "\n";

  }
  close OUT; 
  print "Done with $project\n";
  sleep 3;
}

close PR;

print "Done\n";
exit;

#####################################################################
#####################################################################
# Download all rating info (quality and importance) for a wikiproject

sub download_ratings_for_project {
  my $api = shift;
  my $project = shift;
    
  $Data->{$project} = ();

  my $page;
  my $articles;
  my $article; 
  my $rating;
  my $redir;

  open ERRLOG, ">>Logs/$project.error";
  binmode ERRLOG, ":utf8";

  my $pages = $api->pages_in_category(                      
                      encode('utf8',$ProjectToQualityCategory{$project}),
                      $categoryNS);

  foreach $page ( @$pages) { 
    next unless ($page =~ /^Category:(.*) \Q$project\E articles/i);
    $rating = $1;
    print "Rating: $rating\n";

    $articles = $api->pages_in_category(encode('utf8',$page), $talkNS);
    foreach $article ( @$articles ) { 
      next unless ( $article =~ /^Talk:(.*)$/);	
      $article = $1;
      $article =~ s/&#039;/'/g;

      $redir = redirected($article);
      if ( defined $redir ) {
        print ERRLOG "$project -- $article -- redirects to -- $redir\n";
        next;
      } else { 
        print ERRLOG "OK $article $page\n";
      }

#     print "$article: $project $rating\n";
      $Data->{$project}->{$article}->{'quality'} = $rating;
     
      if ( ! defined $ProjectToImportanceCategory{$project}) { 
        $Data->{$project}->{$article}->{'importance'} = 'Unused-importance';
      } else { 
        $Data->{$project}->{$article}->{'importance'} = 'Unassessed';
      }
    }      
  }

  my $importance;
  if ( defined $ProjectToImportanceCategory{$project}) { 
    $pages = $api->pages_in_category(
                  encode('utf8',$ProjectToImportanceCategory{$project}),
                  $categoryNS);

    foreach $page ( @$pages) { 
    print "Scan $page\n";
      next unless ($page =~ /^Category:(.*) \Q$project\E articles/i);
      $importance = $1;
      print "importance $importance\n";

      $articles = $api->pages_in_category(encode('utf8',$page), $talkNS );
      foreach $article ( @$articles ) { 
#        print "$article: $project $importance\n";
       next unless ( $article =~ /^Talk:(.*)$/);
       $article = $1;
       $article =~ s/&#039;/'/g;

       $redir = redirected($article);
       if ( defined $redir ) {
         print ERRLOG "$project -- $article -- redirects to -- $redir\n";
         next;
       } else { 
         print ERRLOG "OK $article $page\n";
       }

       $Data->{$project}->{$article}->{'importance'} = 
                                  normalize_importance($importance);
      }      
    }
  } else { 
    print "No importance cat\n";    
  }

  close ERRLOG;
}

#####################################################################
# Some projects use nonstandard importance names (e.g. Mathematics)
# Switch the importance names to standard ones.
# Basically, this is a list of special cases

sub normalize_importance {
  my $importance = shift;
  $importance =~s/Priority/importance/;
  return $importance;
}


#####################################################################
# Make a numeric score for an article. This one is only used internally

sub make_score {
  my $article = shift;
  my $project = shift;
  my $quality = shift;
  my $importance = shift;
  my $score = 1;

  if ( defined $QualityMultiplier{$quality}){ 
    $score = $score * $QualityMultiplier{$quality};
  }

  if ( defined $ImportanceMultiplier{$importance}){
    $score = $score * $ImportanceMultiplier{$importance};
  }

  return $score;
}

#####################################################################
# integer logarithm base ten
sub logten {
  my $n = shift;
  if ( $n < 1) { return 0; }
  return log($n)/log(10);
}

#####################################################################
# This is the real score, as documented at
# en:Wikipedia:Version 1.0 Editorial Team/SelectionBot

sub make_score7 {
  my $article = shift;
  my $project = shift;
  my $quality = shift;
  my $importance = shift;
  my $artenc = encode_article($article);

  open SLOG, ">>", "Logs/$project.score";

  my $hitcount;
  my $pagelinks;
  my $interwikis;

  my $overall_score = 0;
  my $importance_score = 0;
  my $assessed_importance_points = 0;
  my $external_interest_points = 0;
  my $quality_score = 0;
  my $base_importance_points;
  
  my $score = 0;

  my $projectUsesImportance = 1;

  my $proj_score = $projectScore{$project};

  print SLOG "\nScoring $article for $project ($proj_score)\n";

  if ( defined $QualityAdditive{$quality} ) { 
    $quality_score +=  $QualityAdditive{$quality};
  }
  print SLOG "Quality_score: $quality $quality_score\n";

  if ( $importance eq 'Unused' ) { 
    print "Project doesn't use importance ratings\n";
    $projectUsesImportance = 0;
  } elsif ( defined $ImportanceAdditive{$importance}) {
    $base_importance_points = $ImportanceAdditive{$importance};
  }
  print SLOG "Base importance points: $importance $assessed_importance_points\n";

  if ( defined $hitCount{$artenc}) { 
    $external_interest_points += $HitcountMultiplier 
                               * logten($hitCount{$artenc});
    print SLOG "Hitcount: " . $hitCount{$artenc} . "\n";
  }

  if ( defined $plCount{$artenc} ) { 
    $external_interest_points += $PagelinkMultiplier 
                              * logten($plCount{$artenc});
    print SLOG "Page links: " . $plCount{$artenc} . "\n";
  }

  if ( defined $iwCount{$artenc} ) { 
     $external_interest_points += $InterwikiMultiplier 
                                * logten($iwCount{$artenc});
     print SLOG "Interwiki count: " . $iwCount{$artenc} . "\n";
  }

  print SLOG "External interest points: $external_interest_points\n";

  $assessed_importance_points = $base_importance_points + $proj_score;
  print SLOG "Assessed importance points: $assessed_importance_points\n";
  
  if ( $projectUsesImportance) { 
    $importance_score = $external_interest_points 
                      + $assessed_importance_points; 
  } else { 
    $importance_score = $external_interest_points 
                      * $NoImportanceMultiplier;
  }

  print SLOG "Importance score: $importance_score\n";

  $overall_score = $importance_score + $quality_score;
  print SLOG "Overall score: $overall_score\n";

  close SLOG;
  return (round($overall_score), round($importance_score));
}

#####################################################################
# Sort functions for the output tables

sub sort_by_rating {
  my $project = shift;
  return sub {
      my $project_c = $project;
      if ( $Data->{$project_c}->{$a}->{'score'} 
           <=> $Data->{$project_c}->{$b}->{'score'} ) 
      { 
        return     $Data->{$project_c}->{$b}->{'score'} 
               <=> $Data->{$project_c}->{$a}->{'score'};
      }             
      return $a cmp $b;
  }
}

sub sort_by_rating_alt {
  my $project = shift;
  return sub {
      my $project_c = $project;
      if ( $Data->{$project_c}->{$a}->{'score7'} 
           <=> $Data->{$project_c}->{$b}->{'score7'} ) 
      { 
        return     $Data->{$project_c}->{$b}->{'score7'} 
               <=> $Data->{$project_c}->{$a}->{'score7'};
      }             
      return $a cmp $b;
  }
}
