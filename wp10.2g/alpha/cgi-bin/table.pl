#!/usr/bin/perl

# WP 1.0 bot - second generation
# CGI to display table of ratings information
# 

use lib '/home/veblen/VeblenBot';

use strict;
use Data::Dumper;

use DBI;
use CGI;
use CGI::Carp qw(fatalsToBrowser);

my $cgi = new CGI;
my %param = %{$cgi->Vars()};

print CGI::header(-type=>'text/html', -charset=>'utf-8');      

my $proj = $param{'project'} || $ARGV[0];

my $pw= `/home/veblen/pw-db.sh`;
my $dbh = DBI->connect('DBI:mysql:wp10', 'wp10user', $pw)
                or die "Couldn't connect to database: " . DBI->errstr;

html_header();
my $projects = query_form($proj);

if ( defined $proj && defined $projects->{$proj} ) {
  ratings_table($proj);
}	
html_footer();
exit;

#######################

sub ratings_table { 
  my $proj = shift;

  print "Project: '$proj'<br/>\n";

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
      $table->data($qual, $prio, $data->{$qual}->{$prio});    
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
    $table->data($qual, "Total", "'''" . $qualcounts->{$qual} . "'''") ;
  }

  foreach $prio ( @PriorityRatings ) { 
    $table->data("Total", $prio, "'''" . $priocounts->{$prio} . "'''");
    $table->data("Assessed", $prio, $totalAssessed->{$prio});
  }

  $table->data("Total", "Total", "'''$total'''");
  $table->data("Assessed", "Total", "'''" . $totalAssessed->{'Total'} . "'''");

  use Mediawiki::API;
  my $api = new Mediawiki::API;
  $api->debug_level(0); # no output at all 
  $api->base_url('http://en.wikipedia.org/w/api.php');

  my $code = $table->wikicode();
  my $r =  $api->parse($code);

  print "<center>\n";
  print $r->{'text'};
  print "</center>\n";
  print "\n";
  print "<hr/><pre>";
  print $code;
  print "</pre>\n";

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
    "SELECT c_type, c_rating, c_ranking, c_category FROM categories 
" . 
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
