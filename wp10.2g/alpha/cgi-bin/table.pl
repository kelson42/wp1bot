#!/usr/bin/perl
use strict;

# WP 1.0 bot - second generation
# CGI to display table of ratings information


require 'read_conf.pl';
our $Opts = read_conf();

require Mediawiki::API;

use Data::Dumper;
use URI::Escape;

require POSIX;
POSIX->import('strftime');

require 'layout.pl';

my $timestamp = strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time()));

my $script_url = 'http://toolserver.org/~cbm//cgi-bin/wp10.2g/alpha/cgi-bin/list.pl?';

########################

require 'init_cache.pl';
my $cache = init_cache();
my $cache_sep = "<hr/><!-- cache separator -->\n";

########################

require CGI;
CGI::Carp->import('fatalsToBrowser');

my $cgi = new CGI;
my %param = %{$cgi->Vars()};

print CGI::header(-type=>'text/html', -charset=>'utf-8');      

my $proj = $param{'project'} || $ARGV[0];

use DBI;
require "database_www.pl";

my $dbh = db_connect($Opts);


layout_header('Summary tables');
my $projects = query_form($proj);

if ( defined $proj && defined $projects->{$proj} ) {
  cached_ratings_table($proj);
}	
layout_footer();
exit;

#######################

sub cached_ratings_table { 

  my $proj = shift;

  my $sth = $dbh->prepare("select p_timestamp from projects "
                        . "where p_project = ?");
  
  $sth->execute($proj);
  my @row = $sth->fetchrow_array();
  my $proj_timestamp = $row[0];

  print "<div class=\"indent\">\n";
  print "<b>Debugging output</b><br/>\n";
  print "Current time: $timestamp<br/>\n";
  print "Data for project $proj was last updated '$proj_timestamp'<br/>\n";

  my $key = "TABLE:" . $proj;
  my $data;

  if ( defined $cgi->{'purge'} ) { 
    print "Purging cached output<br/>\n";
  } elsif ( $cache->exists($key) ) { 
    my $expiry = $cache->expiry($key);
    print "Cached output expires: " . strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($expiry)) 
        . "<br/>\n";

    $data = $cache->get($key);
    my ($c_key, $c_timestamp, $c_proj_timestamp, $c_html, $c_wikicode) 
      = split /\Q$cache_sep\E/, $data, 5;

    if ( $c_proj_timestamp eq $proj_timestamp ) {
      print "Cached output valid<br/>\n";

      print "</div><hr/><center>\n";
      print $c_html;
      print "</center>\n";
      print "\n";
      print "<hr/><div class=\"indent\"><pre>";
      print $c_wikicode;
      print "</pre></div>\n";

      return;
    } else {
      print "Cached output must be regenerated<br/>\n";
    }
  } else {
    print "No cached output available<br/>\n";
  }

  print "Regenerating output<br/>\n";

  my ($html, $wikicode) = ratings_table($proj);

  print "</div><hr/><center>\n";
  print $html;
  print "</center>\n";
  print "\n";
  print "<hr/><div class=\"indent\"><pre>";
  print $wikicode;
  print "</pre></div>\n";

  $data = "TABLE:$proj" . $cache_sep 
        . $timestamp . $cache_sep
        . $proj_timestamp . $cache_sep 
        . $html . $cache_sep 
        . $wikicode;

  $cache->set($key, $data, '1 hour');
}


sub ratings_table { 
  my $proj = shift;

  # Step 1: fetch totals from DB and load them into the $data hash

  my $sth = $dbh->prepare(
    "select count(r_article), r_quality, r_importance, r_project from ratings" .
    " where r_project = ? group by r_quality, r_importance, r_project");

  $sth->execute($proj);

  my ($SortQual, $SortImp, $QualityLabels, $ImportanceLabels) = get_categories($proj);

  my $data = {};
  my $cols = {};
  my @row;

  while ( @row = $sth->fetchrow_array ) {
    if ( ! defined $row[1] ) { $row[1] = 'Unassessed-Class'; }
    if ( ! defined $row[2] ) { $row[2] = 'Unassessed-Class'; }
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

  # The 'Assessed' classification is dynamically generated as we go. 
  $data->{'Assessed'} = {};

  # These, along with the totals, will appear in the final table. 
  # The important step here is the sorting. 
  my @PriorityRatings = sort { $SortImp->{$a} <=> $SortImp->{$b} } keys %$cols;
  my @QualityRatings = sort { $SortQual->{$a} <=> $SortQual->{$b} } keys %$data; 

  use RatingsTable;
  my $table = RatingsTable::new();

  $QualityLabels->{'Total'} = "'''Total'''";
  $ImportanceLabels->{'Total'} = "'''Total'''";

  $table->title("$proj pages by quality and importance");
  $table->columnlabels($ImportanceLabels);
  $table->rowlabels($QualityLabels);
  $table->columntitle("'''Importance'''");
  $table->rowtitle("'''Quality'''");

  # Temporary arrays used to hold lists of row resp. column names
  my @P = (@PriorityRatings, "Total");
  my @Q = (@QualityRatings, "Total");

  $table->rows(\@Q);
  $table->columns(\@P);

  my $priocounts = {};  # Used to count total articles for each priority rating
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

      if ( $data->{$qual}->{$prio} > 0 ) { 
         $table->data($qual, $prio, 
                   '[' . $script_url . "project=" . uri_escape($proj) 
                    . "&importance=" . uri_escape($prio) 
                    . "&quality=" . uri_escape($qual)  . ' ' 
                    . $data->{$qual}->{$prio} . "]");
      } else { 
         $table->data($qual, $prio, "");
      }

      $qualcounts->{$qual} += $data->{$qual}->{$prio};    
      $priocounts->{$prio} += $data->{$qual}->{$prio};    
      $total += $data->{$qual}->{$prio};    

      if ( ! ($qual eq 'Unassessed-Class' ) ) { 
        $totalAssessed->{$prio} += $data->{$qual}->{$prio};
        $totalAssessed->{'Total'} += $data->{$qual}->{$prio};
      }
    }
  }

  foreach $qual ( @QualityRatings ) {
    $table->data($qual, "Total", "'''[" 
                   . $script_url . "project=" . uri_escape($proj) 
#                    . "&importance=" . uri_escape($prio) 
                    . "&quality=" . uri_escape($qual)  . ' ' 
                    . $qualcounts->{$qual} . "]'''");
  }

  foreach $prio ( @PriorityRatings ) { 
    $table->data("Total", $prio, 
                "'''[" . $script_url . "project=" . uri_escape($proj) 
                    . "&importance=" . uri_escape($prio) 
#                    . "&quality=" . uri_escape($qual)  
                   . ' ' . $priocounts->{$prio} . "]'''");

    $table->data("Assessed", $prio, 
                "'''[" . $script_url . "project=" . uri_escape($proj) 
                    . "&importance=" . uri_escape($prio) 
                    . "&quality=Assessed" 
                   . ' ' . $totalAssessed->{$prio} . "]'''" );
  }

  $table->data("Total", "Total", "'''[" 
                   . $script_url . "project=" . uri_escape($proj) 
                   . ' ' . $total . "]'''");

  $table->data("Assessed", "Total", 
                "'''[" . $script_url . "project=" . uri_escape($proj) 
                    . "&quality=Assessed" 
                   . ' ' . $totalAssessed->{'Total'} . "]'''" );

  my $api = new Mediawiki::API;
  $api->debug_level(0); # no output at all 
  $api->base_url('http://en.wikipedia.org/w/api.php');

  my $code = $table->wikicode();
  my $r =  $api->parse($code);

  return ($r->{'text'}, $code);
}

###################################

sub get_categories { 
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
      $qualityLabels->{$row[1]} = "{{$row[1]|category=$row[3]}}";
    } elsif ( $row[0] eq 'importance' ) { 
      $sortImp->{$row[1]} = $row[2];
      $importanceLabels->{$row[1]} = "{{$row[1]|category=$row[3]}}";
    }
  }

  if ( ! defined $sortImp->{'Unassessed-Class'} ) { 
    $sortImp->{'Unassessed-Class'} = 1000;
    $importanceLabels->{'Unassessed-Class'} = "'''None'''";
  } else { 
    $importanceLabels->{'Unassessed-Class'} =~ s/Unassessed-Class/No-Class/;
  }

  if ( ! defined $sortQual->{'Unassessed-Class'} ) { 
    $sortQual->{'Unassessed-Class'} = 1100;
    $qualityLabels->{'Unassessed-Class'} = "'''Unassessed'''";
  }

  if ( ! defined $sortQual->{'Assessed'} ) { 
    $sortQual->{'Assessed'} = 1000;
    $qualityLabels->{'Assessed'} = "'''Assessed'''";
  }

  return ($sortQual, $sortImp, $qualityLabels, $importanceLabels);

}


#################################

sub query_form {

  my $projSelected = shift;

  my $projects = {};
  my @row;

  my $sth = $dbh->prepare("SELECT p_project FROM projects");
  $sth->execute();

  while ( @row = $sth->fetchrow_array ) { 
    $projects->{$row[0]} = 1;
  }

  print "<form>\n";
  print "<select name=\"project\">\n";

  my $p;
  foreach $p ( sort { $a cmp $b} keys %$projects) { 
    if ( $p eq $projSelected ) { 
      print "<option value=\"" . $p . "\" selected>" . $p ."</option>\n";
    } else {
      print "<option value=\"" . $p . "\">" . $p . "</option>\n";
    }
  }

  print "</select>\n";
  print "<input type=\"submit\" value=\"Make table\"/>\n";
  print "</form>\n";
  print "<hr/>\n";

  return $projects;
}

##############


sub html_header { 
print << "HERE";
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr">
  <head>
  <base href="http://en.wikipedia.org">
  <style type="text/css" media="screen, projection">/*<![CDATA[*/
    \@import url("http://en.wikipedia.org/skins-1.5/common/shared.css?162");
    \@import url("http://en.wikipedia.org/skins-1.5/simple/main.css?162");
    \@import url("/w/index.php?title=MediaWiki:Common.css&usemsgcache=yes&action=raw&ctype=text/css&smaxage=2678400");
    \@import url("/w/index.php?title=MediaWiki:Monobook.css&usemsgcache=yes&action=raw&ctype=text/css&smaxage=2678400");

		/*]]>*/</style>
  </head>
  <body>
HERE

}

######################33

sub html_footer { 
print << "HERE";
  </body>
</html>
HERE
}


#################3


