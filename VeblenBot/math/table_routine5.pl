#!/usr/bin/perl
# table_routine5.pl
# $Revision: 1.4 $
# part of VeblenBot
# Carl Beckhorn, 2008
# Copyright: GPL 2.0
#
# General description:   Make pretty tables and lists that summarize
#    ratings data for the mathematics wikiproject.  Originally based 
#    on code by Oleg Alexandrov, but since then completely rewritten 
#    from scratch

use strict;          # 'strict' insists that all variables be declared
use diagnostics;     # 'diagnostics' expands the cryptic warnings

use Data::Dumper;    # for debugging

  # This script uses my Mediawiki::API class to get data from the wiki
use lib '/home/veblen/VeblenBot';
use Mediawiki::API;
my $api = new Mediawiki::API;  # global object 
$api->maxlag(`/home/veblen/maxlag.sh`);
my $startTime = time();

$api->base_url('http://en.wikipedia.org/w/api.php');
$api->debug_level(3);
$api->login_from_file("/home/veblen/api.credentials");

  # These help make the debugging output legible
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my $art;       #  for article names, temp variable
my $tmp_arts;  #  list of article names, temp variable

my $data = {};   #master databases - keys are article names 
my $fields = {}; # $data holds quality and priority. 
                 # $fields holds fields, and 'MATHEMATICS' master field.

my @FieldList;   # List of all fields


  # Used for the 'last updated' line in output
my $date;
$date = `/bin/date --utc`;
chop $date;
my $dateline = "<div style=\"text-align: right;\">Last updated: $date</div>\n";

#####################################################
###
### Project data - customized heavily 
###

  # The possible quality ratings
my @QualityRatings = ( 'FA-Class', 'A-Class', 'GA-Class', 'Bplus-Class',
                          'B-Class', 'Start-Class', 
                          'Stub-Class', 'Unassessed-Class'); 

  # Precedence of quality ratings
my %QualityOrder = ( 'FA-Class' => 1, 
                     'A-Class'=> 2, 
                     'GA-Class' => 3,
                     'Bplus-Class' => 4,
                     'B-Class' => 5, 
                     'Start-Class' => 6,
                     'Stub-Class' => 7, 
                     'Unassessed-Class' =>8); 


  # The possible priority ratings
my @PriorityRatings = ('Top', 'High', 'Mid', 'Low', 'Unassessed') ;

  # Precedence of priority ratings
my %PriorityOrder = ( 'Top' => 1, 'High' => 2, 
                     'Mid' => 3, 'Low' => 4, 
                     'Unassessed' => 5);


  # Field names that can be selected as parameters in the
  # maths rating template
my @FieldsInTemplate = ( 'General', 'Basics', 'Analysis', 'Algebra', 
                 'Applied mathematics', 'Discrete mathematics',
                 'Foundations, logic, and set theory',
                 'Geometry', 'Mathematical physics',
                 'Number theory', 'Mathematicians', 
                 'Probability and statistics', 'Topology');

@FieldsInTemplate = sort @FieldsInTemplate;

my $baseURL = "Wikipedia:WikiProject Mathematics/Wikipedia 1.0";
                #used for constructing links inside tables

my $MA = "mathematics articles";   # an abbreviation

  ## Hash maps class name to wiki code for table cell
my %ClassDesc =
     ( "Unassessed-Class" =>
         "width=35 | '''[[$baseURL/Unassessed-Class $MA|UA]]'''",
       "Stub-Class" =>
          "width=35 {{Stub-Class|category=$baseURL/Stub-Class $MA}}",
       "Start-Class" =>
          "width=35 {{Start-Class|category=$baseURL/Start-Class $MA}}",
       "B-Class" =>
          "width=35 {{B-Class|category=$baseURL/B-Class $MA}}",
       "Bplus-Class" =>
          "width=35 {{Bplus-Class|category=$baseURL/Bplus-Class $MA}}",
       "GA-Class" =>
          "width=35 {{GA-Class|category=$baseURL/GA-Class $MA}}",
       "A-Class" =>
          "width=35 {{A-Class|category=$baseURL/A-Class $MA}}",
       "FA-Class" =>
          "width=35 {{FA-Class|category=$baseURL/FA-Class $MA}}",
       "Total"=>          "width=35 | '''Total'''"
    );

  ## Hash maps importance to wiki code for table cell
my %ImpDesc =  
     ( "Top" => '{{Top-Class|category=Category:Top-Priority mathematics articles|Top}}',
       "High" => '{{High-Class|category=Category:High-Priority mathematics articles|High}}', 
       "Mid" => '{{Mid-Class|category=Category:Mid-Priority mathematics articles|Mid}}',
       "Low" => '{{Low-Class|category=Category:Low-Priority mathematics articles|Low}}',
       "Unassessed"  => "'''[[:Category:Unassessed-Priority mathematics articles|UA]]'''",
       "Total" => "'''Total'''" 
     );

my %FieldDesc = 
     ( 'Algebra' => '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Algebra|Algebra]]',
       'Analysis' => '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Analysis|Analysis]]',
       'Applied mathematics' => '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Applied mathematics|Applied mathematics]]',
       'Basics' => '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Basics|Basics]]',
       'Discrete mathematics' => '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Discrete mathematics|Discrete mathematics]]',
       'Foundations, logic, and set theory' => '[[Wikipedia:WikiProject Mathematics/Wikipedia 1.0/Foundations, logic, and set theory|Foundations, logic, and set theory]]',
       'General' => '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/General|General]]',
       'Geometry' =>'[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Geometry|Geometry]]',
       'MATHEMATICS' => 'Mathematics', 
       'Mathematical physics' => '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Mathematical physics|Mathematical physics]]',
       'Mathematicians' =>'[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Mathematicians|Mathematicians]]',
       'Number theory' => '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Number theory|Number theory]]',
       'Probability and statistics'=> '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Probability and statistics|Probability and statistics]]',
       'Frequently viewed' => '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Frequently viewed|Frequently viewed]]',
       'Theorems and conjectures' => '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Theorems and conjectures|Theorems and conjectures]]',
       'Vital' => '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Vital articles|Vital articles]]',
       'History'=> '[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/History|History]]',
       'Topology' =>'[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/Topology|Topology]]',
       'UnassessedField' => "Unassessed field"
     );

  ## background colors for each importance rating
my %PriorityBG =
     ( "Top" => '#ff00ff',
       "High" => '#ff88ff',
       "Mid" => '#ffccff',
       "Low" => '#ffeeff',
       "Unassessed" => 'none');

  # hash maps field (area) name to keyword telling how to format table row
my %TableRowFormat = (
    'Algebra' => 'field',
    'Analysis' => 'field',
    'Applied mathematics' => 'field',
    'Basics' => 'field',
    'Discrete mathematics' => 'field',
    'Foundations, logic, and set theory' => 'field',
    'General' => 'field',
    'Geometry' => 'field',
    'History' => 'field2',
    'Mathematical physics' => 'field',
    'Mathematicians' => 'field',
    'Number theory' => 'field',
    'Probability and statistics' => 'field',
    'Theorems and conjectures' => 'field2',
    'Frequently viewed' => 'field2',
    'Topology'         => 'field',   
    'UnassessedField'         => 'field',   
    'Vital' => 'field2',
    'priority:Unassessed' => 'priority',
    'priority:Low' => 'priority',
    'priority:Mid' => 'priority',
    'priority:High' => 'priority',
    'priority:Top' => 'priority',
    'quality:Unassessed-Class' => 'quality',
    'quality:Stub-Class' => 'quality',
    'quality:Start-Class' => 'quality',
    'quality:B-Class' => 'quality',
    'quality:Bplus-Class' => 'quality',
    'quality:GA-Class' => 'quality',
    'quality:A-Class' => 'quality',
    'quality:FA-Class' => 'quality'
);


  # hash maps field (area) name to keyword telling how to format table row
my %FieldWikiPageName = (
    'Algebra' => 'Algebra',
    'Analysis' => 'Analysis',
    'Applied mathematics' => 'Applied mathematics',
    'Basics' => 'Basics',
    'Discrete mathematics' => 'Discrete mathematics',
    'Foundations, logic, and set theory' => 'Foundations, logic, and set theory',
    'General' => 'General',
    'Geometry' => 'Geometry',
    'History' => 'History',
    'Mathematical physics' => 'Mathematical physics',
    'Mathematicians' => 'Mathematicians',
    'Number theory' => 'Number theory',
    'Probability and statistics' => 'Probability and statistics',
    'Theorems and conjectures' => 'Theorems and conjectures',
    'Frequently viewed' => 'Frequently viewed',
    'Topology'         => 'Topology',   
    'UnassessedField'         => 'Unassessed-field',   
    'Vital' => 'Vital articles',
    'priority:Unassessed' => 'Unassessed-priority',
    'priority:Low' => 'Low-priority',
    'priority:Mid' => 'Mid-priority',
    'priority:High' => 'High-priority',
    'priority:Top' => 'Top-priority',
    'quality:Unassessed-Class' => 'Unassessed mathematics articles',
    'quality:Stub-Class' => 'Stub-Class mathematics articles',
    'quality:Start-Class' => 'Start-Class mathematics articles',
    'quality:B-Class' => 'B-Class mathematics articles',
    'quality:Bplus-Class' => 'Bplus-Class mathematics articles',
    'quality:GA-Class' => 'GA-Class mathematics articles',
    'quality:A-Class' => 'A-Class mathematics articles',
    'quality:FA-Class' => 'FA-Class matheamtics articles'
);


#########################################################3

  # Initialize data hashes for a new article name
sub initdata {
  my $art = shift;
  if ( ! defined $data->{$art}) { 
    $data->{$art} = {};
    $data->{$art}->{PRIORITY} = 'Initialized';  # for catching errors
    $data->{$art}->{QUALITY} = 'Initalized';
  }
  
  if ( ! defined $fields->{$art}) {
    $fields->{$art} = {};
  }
}

  # Utility function for debugging
sub dumpart {
  my $art = shift;
  my $field;
  printf "%s\n\t%s\t%s\n", 
          $art, $data->{$art}->{QUALITY}, $data->{$art}->{PRIORITY};
  foreach $field ( sort keys %{$fields->{$art}}) {
     print "\t$field\n";
  }
  print "\t.\n";
}


######################################

  # Some articles are simply ignored
sub blacklisted {
  my $art = shift;

  return 1 if ( $art =~ /^List of/);
  return 1 if ( $art =~ /^Table of/);
  return 1 if ( $art =~ /\/Data$/);
  return 0;
}


#####################################

## Fetch quality ratings

my $qual;
my $cat;
my $qfield; # all articles with a given quality are assigned to 
            # a 'field' so that we can list them later

foreach $qual ( @QualityRatings ) {
  print "\nFetching for quality $qual\n";
  $cat = "Category:$qual mathematics articles";
  if ( $qual eq 'Unassessed-Class') { 
      $cat = "Category:Unassessed quality mathematics articles";
  }

  $qfield = "quality:$qual";
  $tmp_arts = $api->pages_in_category($cat);

  print "Count: " . (scalar @$tmp_arts) . "\n";

  push @FieldList, $qfield;
  foreach $art ( @$tmp_arts) {
     next unless ( $art =~ /^Talk:/);
     $art =~ s/^Talk://;
     next if ( blacklisted($art));
     initdata($art);
     $data->{$art}->{QUALITY} = $qual;
     $fields->{$art}->{MATHEMATICS} = 1;
     $fields->{$art}->{$qfield} = 1;
  }
}

push @FieldList, 'MATHEMATICS';  # This is now a valid field

######################################

  ## Fetch priority ratings

my $prio;
my $pfield;

foreach $prio ( @PriorityRatings) {
  print "\nFetching for $prio priority\n";
  $cat = "Category:$prio-Priority_mathematics_articles";
  if ( $prio eq 'Unassessed') { 
    $cat = "Category:Unassessed importance mathematics articles";
  }
  $pfield = "priority:$prio";
  push @FieldList, $pfield;

  $tmp_arts = $api->pages_in_category($cat);
  print "Count: " . (scalar @$tmp_arts) . "\n";

  foreach $art ( @$tmp_arts) { 
     next unless ( $art =~ /^Talk:/); 
     $art =~ s/^Talk://;
     next if ( blacklisted($art));
     initdata($art);
     $data->{$art}->{PRIORITY} = $prio;
     $fields->{$art}->{MATHEMATICS} = 1;
     $fields->{$art}->{$pfield} = 1;
  }
}

### correct for the fact that all Bplus articles are also in the GA category

foreach $art ( keys %$fields ) { 
  if ( defined $fields->{$art}->{'quality:Bplus-Class'}) { 
    delete $fields->{$art}->{'quality:GA-Class'};
  }
}

########### Fetch field assignments made using the template
# This is a kludge; we should use categories for this 
# purpose rather than backlinks

my $field;
foreach $field ( @FieldsInTemplate) { 
  print "\nFetching field $field\n";
  $cat = "Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/$field";
  $tmp_arts = $api->backlinks($cat);
  print "Count: " . (scalar @$tmp_arts) . "\n";
  push @FieldList, $field;    

  foreach $art ( @$tmp_arts) { 
    next unless ( $art->{'ns'}== 1 );
    $art = $art->{'title'};
    $art =~ s/^Talk://;
    next if ( blacklisted($art));

    if ( ! defined $data->{$art}) { 
      print "Not defined: $art\n";
      next;
    }

    $fields->{$art}->{$field} = 1;
    $data->{$art}->{MAINFIELD} = $field;
  }
}

########### Fetch articles with unassessed field

print "\nFetching for unassessed field\n";
$cat = "Category:Unassessed field mathematics articles";
$tmp_arts = $api->pages_in_category($cat);

print "Count: " . (scalar @$tmp_arts) . "\n";
$field = 'UnassessedField';   
push @FieldList, $field;    

foreach $art ( @$tmp_arts) { 
  next unless ( $art =~ /^Talk:/); 
  $art =~ s/^Talk://;
  next if ( blacklisted($art));
  $fields->{$art}->{$field} = 1;
  $data->{$art}->{MAINFIELD} = $field;
}


##################### Fetch articles tagged as theorems and conjectures

print "\nFetching for theorems and conjectures field\n";

$field = 'Theorems and conjectures';  
push @FieldList, $field;    

foreach $cat (("Category:Mathematical theorems", 
               "Category:Conjectures")) {
  $tmp_arts = $api->pages_in_category($cat);
  print "Count: " . (scalar @$tmp_arts) . "\n";
  foreach $art ( @$tmp_arts) { 
    $fields->{$art}->{$field} =1;
  }
}

##################### Fetch articles tagged as frequently viewed

print "\nFetching for frequently viewed articles\n";

$field = 'Frequently viewed';  
push @FieldList, $field;    

foreach $cat (("Category:Frequently viewed mathematics articles")) { 
  $tmp_arts = $api->pages_in_category($cat);
  print "Count: " . (scalar @$tmp_arts) . "\n";
  foreach $art ( @$tmp_arts) { 
    $art =~ s/^Talk://;
    print "TC $art\n";
    $fields->{$art}->{$field} =1;
  }
}

##################### Fetch articles tagged vital

print "\nFetching vital articles\n";
$field = 'Vital';  
push @FieldList, $field;    

$cat = "Category:Vital mathematics articles";
$tmp_arts = $api->pages_in_category($cat);
print "Count: " . (scalar @$tmp_arts) . "\n";

foreach $art ( @$tmp_arts) { 
   next unless ( $art =~ /^Talk/);
   $art =~ s/^Talk://;
   $fields->{$art}->{$field} =1;
}

##################### Fetch articles tagged as history-related

print "\nFetching for history field\n";
$field = 'History';
push @FieldList, $field;    

$cat = "Category:History of subject mathematics articles";
$tmp_arts = $api->pages_in_category($cat);
print "Count: " . (scalar @$tmp_arts) . "\n";
foreach $art ( @$tmp_arts) { 
  next unless ( $art =~ /^Talk:/); 
  $art =~ s/^Talk://;
  $fields->{$art}->{$field} = 1;
}


#################### Dump data, very useful for debugging

print "Total count: " . (scalar keys %$data) ."\n";

foreach $art ( sort keys %$data ) {
  dumpart($art);
}

###################################################################
###################################################################
############## Now we can start writing tables


  # This class abstracts the process of writing 
  # wiki code for a table
use RatingsTable;
my $table = RatingsTable::new();

##########  Phase 1:  tables with quality on cols and priority on rows

$table->title("Math articles by quality and priority");
$table->rowlabels(\%ImpDesc);
$table->columnlabels(\%ClassDesc);
$table->rowtitle("'''Priority'''");
$table->columntitle("'''Quality'''");

  # Temporary arrays used to hold lists of row resp. column names
my @P = (@PriorityRatings, ("Total"));
my @Q = (@QualityRatings, ("Total"));

$table->rows(\@P);
$table->columns(\@Q);

my $priocounts;  # Used to count total articles for each priority rating
my $qualcounts;  # same, for each quality rating
my $cells;

  # Make one table for each field. 
  # The field MATHEMATICS will include all rated articles
foreach $field ( @FieldList) { 
  next if ($field =~ /^priority:/);
  next if ($field =~ /^quality:/);
 
  $priocounts = {};
  $qualcounts = {};
  my $total;
  
  $table->clear();

  print "Field: $field $FieldDesc{$field}\n";

  $table->title($FieldDesc{$field} . " article ratings");

  foreach $qual ( @QualityRatings ) {
    $qualcounts->{$qual}=0;
    foreach $prio ( @PriorityRatings ) { 
      $table->data($prio, $qual, 0);    
      $priocounts->{$prio} = 0;
    }
  }

  foreach $art ( keys %$data) { 
    next unless ( defined $fields->{$art}->{$field} );
     $table->incrdata($data->{$art}->{PRIORITY}, $data->{$art}->{QUALITY});
     $priocounts->{$data->{$art}->{PRIORITY}}++;
     $qualcounts->{$data->{$art}->{QUALITY}}++;
     $total++
  }

  foreach $qual ( @QualityRatings ) {
    $table->data("Total", $qual, "'''" . $qualcounts->{$qual} . "'''") ;
  }

  foreach $prio ( @PriorityRatings ) { 
    $table->data($prio, "Total", "'''" . $priocounts->{$prio} . "'''");
  }


    # Make the table cells link to the correct place.
    # The wiki page names are not uniform, so there are cases to consider
  if ( $field eq 'MATHEMATICS' ) { 
    foreach $qual ( @QualityRatings ) {
      foreach $prio ( @PriorityRatings ) { 
        $table->data($prio, $qual, 
           "[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/" 
             . $qual . " mathematics articles/" 
             . $prio . "|" .  $table->data($prio, $qual) .  "]]");
      }
    }
  } else {
    foreach $qual ( @QualityRatings ) {
      foreach $prio ( @PriorityRatings ) { 
        $table->data($prio, $qual, 
           "[[Wikipedia:WikiProject_Mathematics/Wikipedia_1.0/" 
              . $FieldWikiPageName{$field} . "#" . $prio 
              . "|" .  $table->data($prio, $qual) .  "]]");
      }
    }
  }

  $table->data("Total", "Total", "'''$total'''");

  open OUT, ">output/table:$field";
  print OUT $table->wikicode();
  print OUT $dateline;
  close OUT;
}

#########################################################
###########  Phase 2a: single table of articles by field and quality

$table->title("Math articles by field and quality");
$table->rowlabels(\%FieldDesc);
$table->columnlabels(\%ClassDesc);
$table->rowtitle("'''Field'''");
$table->columntitle("'''Quality'''");

@P = (keys %FieldDesc);
@Q = (@QualityRatings, ("Total"));
my %FieldsUsed;

$table->rows(\@P);
$table->columns(\@Q);

my %fieldcounts;

### fill in table data 
$table->clear();

foreach $field ( @P) { 
  foreach $qual ( @Q) { 
    $table->data($field, $qual, 0);
  }
 }

foreach $art ( keys %$data) { 
  foreach $field ( keys %{$fields->{$art}}) { 
    next if ($field eq 'MATHEMATICS');
    next if ($field eq 'UnassessedField');
    next if ($field =~ /^priority:/);
    next if ($field =~ /^quality:/);
    $FieldsUsed{$field} = 1;
    $table->incrdata($field, $data->{$art}->{QUALITY});
    $fieldcounts{$field}++;
  }
}

@P = sort keys %FieldsUsed;
$table->rows(\@P);

foreach $field (@P) { 
  $table->data($field, "Total", "'''" . $fieldcounts{$field} . "'''");
}

# For debugging
# $table->dump();

open OUT, ">output/table:FIELDS.QUALITY";
print OUT $table->wikicode();
print OUT $dateline;
close OUT;

#########################################################
###########  Phase 2b: single table of articles by field and priority

$table->title("Math articles by field and priority");
$table->rowlabels(\%FieldDesc);
$table->columnlabels(\%ImpDesc); 
$table->rowtitle("'''Field'''");
$table->columntitle("'''Priority'''");

@P = (keys %FieldDesc);
@Q = (@PriorityRatings, ("Total"));

%FieldsUsed = ();

$table->rows(\@P);
$table->columns(\@Q);

%fieldcounts = ();

### fill in table data 
$table->clear();

foreach $field ( @P) { 
  foreach $prio ( @Q) { 
    $table->data($field, $prio, 0);
  }
}

foreach $art ( keys %$data) { 
  foreach $field ( keys %{$fields->{$art}}) { 
    next if ($field eq 'MATHEMATICS');
    next if ($field eq 'UnassessedField');
    next if ($field =~ /^priority:/);
    next if ($field =~ /^quality:/);
    $FieldsUsed{$field} = 1;
    $table->incrdata($field, $data->{$art}->{PRIORITY});
    $fieldcounts{$field}++;
  }
}

@P = sort keys %FieldsUsed;
$table->rows(\@P);

foreach $field (@P) { 
  $table->data($field, "Total", "'''" . $fieldcounts{$field} . "'''");
}

# For debugging
# $table->dump();

open OUT, ">output/table:FIELDS.PRIORITY";
print OUT $table->wikicode();
print OUT $dateline;
close OUT;


####################################################################
###########  Phase 3:  lists of articles by field and quality

my $FieldData = {};

foreach $field (@FieldList) { 
  $FieldData->{$field} = {};
}

foreach $art ( keys %$data) { 
  foreach $field ( keys %{$fields->{$art}}) {
    if ( ! defined $FieldData->{$field}->{$data->{$art}->{PRIORITY}} ) { 
      $FieldData->{$field}->{$data->{$art}->{PRIORITY}} = [];
    } 
    push @{$FieldData->{$field}->{$data->{$art}->{PRIORITY}}}, $art;

    if ( ! defined $FieldData->{$field}->{$data->{$art}->{QUALITY}} ) { 
      $FieldData->{$field}->{$data->{$art}->{QUALITY}} = [];
    } 
    push @{$FieldData->{$field}->{$data->{$art}->{QUALITY}}}, $art;
  }
}


my @articlesTemp;
my $prefix;

foreach $field ( keys %$FieldData) { 
  next if ($field eq 'Mathematicians');
  next if ($field eq 'MATHEMATICS');
  next if ($field =~ /^priority:/); # handled separately below

  print "Field: $field\n";

  foreach $prio ( ('Top', 'High', 'Mid', 'Low', 'Unassessed') ) { 
    if ( defined $FieldData->{$field}->{$prio} ) { 
      @articlesTemp = @{$FieldData->{$field}->{$prio}}; 
    } else {
      @articlesTemp = ();
    }

    $prefix = "";
    if ( ! ( $field =~ /^(quality|priority):/) ) { 
      $prefix = "field:";
    }

    open OUT, ">output/$prefix$field-$prio";
    binmode OUT, ":utf8";

    if ( scalar @articlesTemp == 0 ) { 
      my $tprio = $prio;
      $tprio =~ tr/[A-Z]/[a-z]/;
      my $tfield = $field;
      $tfield =~ s/^quality://;
      $tfield =~ s/-Class/-quality/;
      $tfield =~ s/UnassessedField/Unassessed-field/;
      print OUT "There are currently no $tprio-priority $tfield articles.\n";
      print OUT "$dateline\n";
      close OUT;
      next;  # move to next importance
    }

    print OUT << "HERE";
<span id="$prio"></span>
{| class="wikitable sortable" width="100%"
HERE

    if ( $TableRowFormat{$field} eq 'field') {            
      print OUT "{{Wikipedia:WikiProject Mathematics/Wikipedia 1.0/Table row header}}\n";
    } elsif ( $TableRowFormat{$field} eq 'field2') {           
      print OUT "{{Wikipedia:WikiProject Mathematics/Wikipedia 1.0/Table row header long}}\n";
    } elsif ( $TableRowFormat{$field} eq 'quality') {
      print OUT "{{Wikipedia:WikiProject Mathematics/Wikipedia 1.0/Class table row header}}\n";
    } else { 
      print STDERR "ERROR: format $field $TableRowFormat{$field}\n";
    }
   
    my $art;
    my $artenc;
    foreach $art ( sort { $_ = $QualityOrder{$data->{$a}->{QUALITY}}
                               <=>$QualityOrder{$data->{$b}->{QUALITY}};
                          if ( $_ != 0) { return $_; }
                          $_ = $data->{$a}->{MAINFIELD} cmp $data->{$b}->{MAINFIELD};
                          if ( $_ != 0) { return $_; }
                          return $a cmp $b; 
                        }
                     @articlesTemp) {

        $artenc = $art;
        $artenc =~ s/=/%3D/g;

        if ( $TableRowFormat{$field} eq 'field') {
            print OUT "{{Wikipedia:WikiProject Mathematics/Wikipedia 1.0/Table row format";
            print OUT "|" . $artenc;
            print OUT "|" . $data->{$art}->{PRIORITY};
            print OUT "|" . $data->{$art}->{QUALITY};
            print OUT "}}\n";
        } elsif ( $TableRowFormat{$field} eq 'field2') {
            print OUT "{{Wikipedia:WikiProject Mathematics/Wikipedia 1.0/Table row format long";
            print OUT "|" . $artenc;
            print OUT "|" . $data->{$art}->{PRIORITY};
            print OUT "|" . $data->{$art}->{QUALITY};
            print OUT "|" . $FieldDesc{$data->{$art}->{MAINFIELD}};
            print OUT "}}\n";
        } elsif ( $TableRowFormat{$field} eq 'quality') {
            print OUT "{{Wikipedia:WikiProject Mathematics/Wikipedia 1.0/Class table row format";
            print OUT "|" . $artenc;
            print OUT "|" . $data->{$art}->{PRIORITY};
            print OUT "|" . $FieldDesc{$data->{$art}->{MAINFIELD}};
            print OUT "}}\n";
        } else { 
            die "Bad field type: $field $TableRowFormat{$field}";
        }
    }
    print OUT "|}\n";
    print OUT "$dateline\n";
    close OUT;
  }
}

#################################################################
#### Make lists of articles that have a particular priority

foreach $field ( keys %$FieldData) { 
  next unless ($field =~ /^priority:/); # only remaining case

  print "Field: $field\n";

  foreach $qual ( @QualityRatings ) { 
    if ( defined $FieldData->{$field}->{$qual} ) { 
      @articlesTemp = @{$FieldData->{$field}->{$qual}}; 
    } else {
      @articlesTemp = ();
    }

    open OUT, ">output/$field-$qual";
    binmode OUT, ":utf8";

    if ( scalar @articlesTemp == 0 ) { 
      my $tprio = $field;
      $tprio =~ tr/[A-Z]/[a-z]/;
      my $tqual = $qual;
      $tqual =~ s/-Class/-quality/;
      print OUT "There are currently no $tprio-priority $tqual articles.\n";
      print OUT "$dateline\n";
      close OUT;
      next;  # move to next importance
    }

    print OUT << "HERE";
<span id="$qual"></span>
{| class="wikitable sortable" width="100%"
HERE

    print OUT "{{Wikipedia:WikiProject Mathematics/Wikipedia 1.0/Priority table row header}}\n";
   
    my $art;
    foreach $art ( sort { $_ = $data->{$a}->{MAINFIELD} cmp $data->{$b}->{MAINFIELD};
                          if ( $_ != 0) { return $_; }
                          return $a cmp $b; 
                        }
                     @articlesTemp) {

       if ( $TableRowFormat{$field} eq 'priority') {  
               # double-check for sanity
            print OUT "{{Wikipedia:WikiProject Mathematics/Wikipedia 1.0/Priority table row format";
            print OUT "|" . $art;
            print OUT "|" . $data->{$art}->{QUALITY};
            print OUT "|" . $FieldDesc{$data->{$art}->{MAINFIELD}};
            print OUT "}}\n";
        } else { 
            die "Bad field type: $field $TableRowFormat{$field}";
        }
    }
    print OUT "|}\n";
    print OUT "$dateline\n";
    close OUT;
  }
}

#################################################################
### Make lists for biographical articles

my @Mathematicians;

foreach $art ( keys %$data ) { 
  if ( defined $fields->{$art}->{'Mathematicians'} ) { 
    push @Mathematicians, $art;
  }
}

open OUT, ">output/field:Mathematicians";
binmode OUT, ":utf8";

print OUT << "HERE";
== Mathematicians ==
{| class="wikitable sortable" width="100%"
! Name
! Dates
! Class
! Field and comments
! Imp. 
HERE

foreach $art ( sort  { $_ = $PriorityOrder{$data->{$a}->{PRIORITY}}
                              <=> $PriorityOrder{$data->{$b}->{PRIORITY}};
                       if ( $_ != 0) { return $_; }
                       $_ = $QualityOrder{$data->{$a}->{QUALITY}}
                              <=> $QualityOrder{$data->{$b}->{QUALITY}};
                       if ( $_ != 0) { return $_; }
                       return $a cmp $b; }
                 @Mathematicians ) {
  print OUT "{{Wikipedia:WikiProject Mathematics/Wikipedia 1.0/Mathematician row format";
  print OUT "|" . $art;
  print OUT "|" . $data->{$art}->{PRIORITY};
  print OUT "|" . $data->{$art}->{QUALITY};
  print OUT "}}\n";
}
print OUT "|}\n";
print OUT "$dateline\n";
close OUT;



###########################################################################################



