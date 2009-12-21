#!/usr/bin/perl

# table_lib.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for additional information

=head1 SYNOPSIS

Library routines to create assessment summary tables

=cut

use strict;
use Encode;

require 'read_conf.pl';
our $Opts = read_conf();
my $NotAClass = $Opts->{'not-a-class'};

require Mediawiki::API;
my $api = new Mediawiki::API;
$api->debug_level(0); # no output at all 
$api->base_url($Opts->{'api-url'});

use Data::Dumper;
use URI::Escape;

require POSIX;
POSIX->import('strftime');

require 'layout.pl' or die;

my $timestamp = strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time()));

my $list_url = $Opts->{'list2-url'} 
  or die "No 'list2-url' specified in configuration.\n";

my $log_url = $Opts->{'log-url'} 
  or die "No 'list2-url' specified in configuration.\n";

require 'layout.pl';

use DBI;
require "database_www.pl";
our $dbh = db_connect_rw($Opts);

require 'cache.pl';
my $cache_sep = "<!-- cache separator -->\n";

############################################################

sub cached_project_table { 
  my $proj = shift;
  my $purge = shift;

  my $sth = $dbh->prepare("select p_timestamp from projects "
                        . "where p_project = ?");
  
  $sth->execute($proj);
  my @row = $sth->fetchrow_array();
  my $proj_timestamp = $row[0];

  print "<!-- cache debugging  -->\n";
  print "<!-- Debugging output -->\n";
  print "<!-- Current time: $timestamp -->\n";
  print "<!-- Data for project $proj was last updated '$proj_timestamp'-->\n";

  my $key = "TABLE:" . $proj;
  my $data;
  my $expiry = cache_exists($key);

  if ( (defined $purge) && $expiry )  { 
    print "<!-- Purging cached output -->\n";
  } elsif ( $expiry ) { 
    print "<!-- Cached output expires " 
        . strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($expiry)) 
        . "-->\n";

    $data = cache_get($key);
    my ($c_key, $c_timestamp, $c_proj_timestamp, $c_html, $c_wikicode) = 
    split /\Q$cache_sep\E/, $data, 5;

    if ( $c_proj_timestamp eq $proj_timestamp ) {
      print "<!-- Cached output valid -->\n";
      print "<!-- end cache debugging -->\n ";
      return ($c_html, $c_wikicode);
    } else {
      print "<!-- Cached output must be regenerated -->\n";
    }
  } else {
    print "<!-- No cached output available --> \n";
  }

  print "<!-- Regenerating output --> \n";
  print "<!-- end cache debugging --> \n ";

  my ($html, $wikicode) = make_project_table($proj);
  
  $data = "TABLE:$proj" . $cache_sep 
        . $timestamp . $cache_sep
        . $proj_timestamp . $cache_sep 
        . $html . $cache_sep 
        . $wikicode;

  cache_set($key, $data, 12*60*60); # expires in 12 hours

  return ($html, $wikicode, $timestamp);
}


############################################################

sub make_project_table { 
  my $proj = shift;
  my $tdata = fetch_project_table_data($proj);
  my $code = make_project_table_wikicode($tdata, 
                                 "$proj articles by quality and importance",
                                 \&format_cell_pqi );
  my $r =  $api->parse($code);
  return ($r->{'text'}->{'content'}, $code);
}

############################################################

sub make_global_table { 
  my $proj = shift;
  my $tdata = fetch_global_table_data($proj);
  my $code = make_project_table_wikicode($tdata, 
                            "All rated articles by quality and importance",
                            \&format_cell_pqi );
  my $r =  $api->parse($code);
  my $created = time();
  return ($r->{'text'}->{'content'}, $code, $created);
}

############################################################

sub fetch_project_table_data { 
  my $proj = shift;

  print "<!-- Fetch data for '$proj' -->\n";

  # Step 1: fetch totals from DB and load them into the $data hash

  my $sth = $dbh->prepare(
     "select count(r_article), r_quality, r_importance, r_project 
      from ratings
      where r_project = ? group by r_quality, r_importance, r_project");

  $sth->execute($proj);

  my ($SortQual, $SortImp, $QualityLabels, $ImportanceLabels) 
    = get_project_categories($proj);

  my $data = {};
  my $cols = {};
  my @row;

  while ( @row = $sth->fetchrow_array ) {
    if ( ! defined $row[1] ) { $row[1] = 'Unassessed-Class'; }
    if ( ! defined $row[2] ) { $row[2] = 'Unknown-Class'; }
    if ( ! defined $data->{$row[1]} ) { $data->{$row[1]} = {} };

    # The += here is for 'Unssessed-Class' classifications, which 
    # could happen either as a result of an actual category or as 
    # the result of the if statements above
    $data->{$row[1]}->{$row[2]} += $row[0];
    $cols->{$row[2]} = 1;
  }

  # Step 2 - remove any rows or columns that shouldn't be displayed

  my $col;
  foreach $col ( keys %$cols ) {
    if ( ! defined $SortImp->{$col} ) { 
      print "skip col $col\n";
      delete $cols->{$col};
    }
  }

  my $row;
  foreach $row ( keys %$data ) { 
    if ( ! defined $SortQual->{$row} ) { 
      print "skip row $row\n";
      delete $data->{$row};
    }
  }

  return { 'proj' => $proj, 
           'cols' => $cols,
           'data' => $data,
           'SortImp' => $SortImp,
           'SortQual' => $SortQual,
           'ImportanceLabels' => $ImportanceLabels,
           'QualityLabels' => $QualityLabels };

} 

##############################################################

sub make_project_table_wikicode { 
  my $tdata = shift;
  my $title = shift;
  my $format_cell = shift;

  my $proj = $tdata->{'proj'};
  my $cols = $tdata->{'cols'};
  my $data = $tdata->{'data'};
  my $SortImp = $tdata->{'SortImp'};
  my $SortQual = $tdata->{'SortQual'};
  my $ImportanceLabels = $tdata->{'ImportanceLabels'};
  my $QualityLabels = $tdata->{'QualityLabels'};


  # The 'assessed' data is generated dynamically
  $data->{'Assessed'} = {};

  # These, along with the totals, will appear in the final table. 
  # The important step here is the sorting. 
  my @PriorityRatings = sort { $SortImp->{$b} <=> $SortImp->{$a} } 
                             keys %$cols;
  my @QualityRatings =  sort { $SortQual->{$b} <=> $SortQual->{$a} } 
                             keys %$data; 

  use RatingsTable;
  my $table = RatingsTable::new();

  my $TotalWikicode = "style=\"text-align: center;\" | '''Total'''";
  $QualityLabels->{'Total'} = $TotalWikicode;
  $ImportanceLabels->{'Total'} = $TotalWikicode;

  $table->title($title);
  $table->columnlabels($ImportanceLabels);  
  $table->rowlabels($QualityLabels);
  $table->columntitle("'''Importance'''");
  $table->rowtitle("'''Quality'''");

  # Temporary arrays used to hold lists of row resp. column names
  my @P = (@PriorityRatings, "Total");
  my @Q = (@QualityRatings,"Total");

  $table->rows(\@Q);

  # If there are just two colums, they have the same data
  # So just show the totals

  if ( 2 < scalar @P ) { 
      $table->columns(\@P);
  } else { 
      $table->columns(["Total"]);
      $table->title("$proj pages by quality");
      $table->unset_columntitle();
      $TotalWikicode = "style=\"text-align: center;\" | '''Total pages'''";
      $ImportanceLabels->{'Total'} = $TotalWikicode;
  }

  my $priocounts = {};  # Used to count total articles by priority rating
  my $qualcounts = {};  # same, for each quality rating
  my $cells;

  my $total;
  
  $table->clear();

  my $qual;
  my $prio;
  my $total = 0;
  my $totalAssessed = {};  # To count 'Assessed' articles

  # Next step: fill in table data using the $data hash

  foreach $qual ( @QualityRatings ) {
      $qualcounts->{$qual}=0;
  }

  foreach $prio ( @PriorityRatings ) { 
      $priocounts->{$prio} = 0;
  }

  foreach $qual ( @QualityRatings ) {
      next if ( $qual eq 'Assessed' );  # nothing in $data for this

      foreach $prio ( @PriorityRatings ) { 
#      print "<!-- q '$qual' p '$prio' -->\n";

	  if (  (defined $data->{$qual}->{$prio}) 
              && $data->{$qual}->{$prio} > 0 ) { 
            $table->data($qual, $prio, 
                         &{$format_cell}($proj, $qual, $prio, 
                                         $data->{$qual}->{$prio}) );

	  } else { 
	      $table->data($qual, $prio, "");
	  }
# print "<!-- qual '$qual' prio '$prio' -->\n";
	  if ( defined $data->{$qual}->{$prio} ) { 
	      $qualcounts->{$qual} += $data->{$qual}->{$prio};
	      $priocounts->{$prio} += $data->{$qual}->{$prio};    
	      $total += $data->{$qual}->{$prio};    
	  }

	  if ( ! ($qual eq 'Unassessed-Class' ) ) { 

             if ( ! defined $data->{$qual}->{$prio}  ) { 
 		 $data->{$qual}->{$prio}  = 0;
	     }

             if ( ! defined $totalAssessed->{$prio} ) { 
                 $totalAssessed->{$prio} = 0;
             }

             $totalAssessed->{$prio} += $data->{$qual}->{$prio};
             $totalAssessed->{'Total'} += $data->{$qual}->{$prio};
	  }
      }
  }

  foreach $qual ( @QualityRatings ) {
    $table->data($qual,  "Total",
                 &{$format_cell}($proj, $qual, undef, $qualcounts->{$qual}));
  }

  foreach $prio ( @PriorityRatings ) { 
    $table->data("Total", $prio, 
                 &{$format_cell}($proj, undef, $prio, $priocounts->{$prio}));

    $table->data("Assessed", $prio, 
                 &{$format_cell}($proj, "Assessed", $prio, 
                                 $totalAssessed->{$prio}));
  }

  $table->data("Total", "Total", format_cell_pqi($proj, undef, undef, $total));

  $table->data("Assessed", "Total", 
               &{$format_cell}($proj, "Assessed", undef, 
                               $totalAssessed->{'Total'}));

  my $code = $table->wikicode();

  return $code;
}

################################################################

sub get_project_categories { 
  my $project = shift;

  my $MA = "$project articles";

  my $data = {};

  my $sortQual = {};
  my $sortImp = {};
  my $qualityLabels = {};
  my $importanceLabels = {};
  my $categories = {};

  my $sth = $dbh->prepare(
      "SELECT c_type, c_rating, c_ranking, c_category FROM categories " . 
      "WHERE c_project = ?" );

  $sth->execute($project);

  my @row;

  while ( @row = $sth->fetchrow_array() ) {
    if ( $row[0] eq 'quality' ) { 
      $sortQual->{$row[1]} = $row[2];
      if ( $row[1] eq $NotAClass ) { 
        $qualityLabels->{$row[1]} = 
               " style=\"text-align: center;\" | '''Other'''";
      } else { 
        $qualityLabels->{$row[1]} = "{{$row[1]|category=$row[3]}}";
      }
    } elsif ( $row[0] eq 'importance' ) { 
      $sortImp->{$row[1]} = $row[2];

      if ( $row[1] eq $NotAClass ) { 
        $importanceLabels->{$row[1]} = "Other";
      } else { 
        $importanceLabels->{$row[1]} = "{{$row[1]|category=$row[3]}}";
      }
    }
  }

  if ( ! defined $sortImp->{'Unassessed-Class'} ) { 
    $sortImp->{'Unassessed-Class'} = 0;
    $importanceLabels->{'Unassessed-Class'} = "'''None'''";
  } else { 
    $importanceLabels->{'Unassessed-Class'} =~ s/Unassessed-Class/No-Class/;
  }

  if ( ! defined $sortQual->{'Unassessed-Class'} ) { 
    $sortQual->{'Unassessed-Class'} = 0;
    $qualityLabels->{'Unassessed-Class'} = "'''Unassessed'''";
  }

  if ( ! defined $sortQual->{'Assessed'} ) { 
    $sortQual->{'Assessed'} = 20;
    $qualityLabels->{'Assessed'} = "{{Assessed-Class}}";
  }

  return ($sortQual, $sortImp, $qualityLabels, $importanceLabels);
}

################################################################

sub fetch_global_table_data { 

  # Step 1: fetch totals from DB and load them into the $data hash

  my $query = <<"  HERE";
select count(distinct a_article), grq.gr_rating, gri.gr_rating
from global_articles
join global_rankings as grq 
  on grq.gr_type = 'quality' and grq.gr_ranking= a_quality
join global_rankings as gri 
  on gri.gr_type = 'importance' and gri.gr_ranking= a_importance
group by grq.gr_rating, gri.gr_rating /* SLOW_OK */
  HERE

  my $sth = $dbh->prepare($query);
  
  $sth->execute();

  my ($SortQual, $SortImp, $QualityLabels, $ImportanceLabels) 
    = get_global_categories();

  my $data = {};
  my $cols = {};
  my @row;

  while ( @row = $sth->fetchrow_array ) {
    if ( ! defined $row[1] ) { $row[1] = $NotAClass; }
    if ( ! defined $row[2] ) { $row[2] = $NotAClass; }
    if ( ! defined $data->{$row[1]} ) { $data->{$row[1]} = {} };

    # The += here is for 'NotA-Class' classifications, which 
    # could happen either as a result of an actual category or as 
    # the result of the if statements above
    $data->{$row[1]}->{$row[2]} += $row[0];
    $cols->{$row[2]} = 1;
  }

  # Step 2 - remove any rows or columns that shouldn't be displayed

  my $col;
  foreach $col ( keys %$cols ) {
    if ( ! defined $SortImp->{$col} ) { 
      print "skip col $col\n";
      delete $cols->{$col};
    }
  }

  my $row;
  foreach $row ( keys %$data ) { 
    if ( ! defined $SortQual->{$row} ) { 
      print "skip row $row\n";
      delete $data->{$row};
    }
  }

  return { 'proj' => undef, 
           'cols' => $cols,
           'data' => $data,
           'SortImp' => $SortImp,
           'SortQual' => $SortQual,
           'ImportanceLabels' => $ImportanceLabels,
           'QualityLabels' => $QualityLabels };
}

################################################################

sub get_global_categories { 

  my $Assessed = "Assessed";
  my $Assessed_Class = "Assessed-Class";
  my $Unassessed_Class = "Unassessed-Class";
  my $Unknown_Class = "Unknown-Class";

  my $sortQual = { 'FA-Class' => 500, 'FL-Class' => 480, 'A-Class' => 425, 
                   'GA-Class' => 400, 'B-Class' => 300, 'C-Class' => 225, 
              'Start-Class'=>150, 'Stub-Class' => 100, 'List-Class' => 80, 
              $Assessed => 20, $NotAClass => '11', 
              'Unknown-Class' => '10',  $Unassessed_Class => 0};

  my $sortImp= { 'Top-Class' => 400, 'High-Class' => 300, 
                 'Mid-Class' => 200, 'Low-Class' => 100, 
                 $NotAClass => 11, $Unknown_Class => 10, 
                  $Unassessed_Class => 0};

  my $qualityLabels = {};
  my $importanceLabels = {};

  my $k;
  foreach $k ( keys %$sortQual ) { 
    $qualityLabels->{$k} = "{{$k}}";
  }

  $qualityLabels->{$Assessed} = "'''$Assessed'''";

  foreach $k ( keys %$sortImp ) { 
    $importanceLabels->{$k} = "{{$k}}";
  }

  $importanceLabels->{'Unassessed-Class'} =~ s/Unassessed-Class/No-Class/;

  return ($sortQual, $sortImp, $qualityLabels, $importanceLabels);
}

################################################################

sub cached_global_ratings_table { 
  my $force_regenerate = shift || 0;

  print "<!-- global table - purge: '$force_regenerate' -->\n";

  my $key = "GLOBAL:TABLE";
  my ($expiry, $data);

  if ( ($expiry = cache_exists($key)) && ! $force_regenerate ) { 
    print "<!-- Debugging output -->\n";
    print "<!-- Current time: $timestamp --> \n";

    $expiry =~ s/\0//g;

    print "<!-- Cached output expires: " 
       . strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($expiry)) 
       . " -->\n";

    $data = cache_get($key);

    my ($c_key, $c_html, $c_wikicode, $c_created) = 
          split /\Q$cache_sep\E/, $data, 4;

    return ($c_html, $c_wikicode, $c_created);
  }

  if ( ! $force_regenerate ) { 
# no data available
      return;
  }

  print "Regenerating global table\n";
  print "Current time: $timestamp\n";
  my $ts = time();
  
  my ($html, $wikicode, $createdtime) = make_global_table();

  $ts = time() - $ts;
  $ts = int(0.5 + $ts / 60);
  print "Regenerated in $ts minutes\n";

  $data = "GLOBAL:TABLE" 
        . $cache_sep . $html 
        . $cache_sep . $wikicode
        . $cache_sep . $createdtime;

  cache_set($key, $data, 7*24*60*60); # expires in 1 week

  return ($html, $wikicode, $createdtime);
}

################################################################

sub format_cell_pqi { 
  my $proj = shift;
  my $qual = shift;
  my $prio = shift;
  my $value = shift;

  my $bold = "";
  if ( (! defined $qual) || (! defined $prio ) ) { 
    $bold = "'''";
  }

  my $str = $bold . '[' . $list_url . "?run=yes";

  if ( defined $proj ) { 
    $str .= "&projecta=" . uri_escape($proj) ;
  }

  if ( defined $prio ) { 
    $str .= "&importance=" . uri_escape($prio) ;
  }

  if ( defined $qual ) { 
    $str .= "&quality=" . uri_escape($qual)  ;
  }

  $str .=  ' ' . commify($value) . "]" . $bold ;

  return $str;
}

################################################################
#Load successfully
1;
