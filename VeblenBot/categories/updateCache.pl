#!/usr/bin/perl
# Keep a cache of category members and when they were added, 
# so that a transient removal/reinsertion will be concealed
#
# Carl Beckhorn, 2008
# Copyright: GPL 2.0

use strict;               

binmode STDOUT, ":utf8";  # So that non-ASCII characters are 
                          # correctly encoded in the output

use Date::Parse;
use POSIX qw(strftime);
use Data::Dumper;

my %Cutoffs;  # Global hash indexed by category name 
              # tells how long to remember
              # when a page was added to a given category


my $nowtime = time();   # Seconds since epoch
my $nowdate = `/bin/date --rfc-3339=seconds`;
chomp $nowdate;

my %Reverse; # Categires that should be reverse sorted

################################################

sub handleCat  {
  # Given a catgory name, read the old cache
  # and the current list of contents, update
  # the cache and the timestamps in the list
  # of contents, and write everything to disk

my ($cat, $format, $page, $time, $ns, $line, $key, $extra, $headline);
my (%Formats, %Namespaces, %PageNames, %Timestamps, %Extras,
              %NTimestamps, %LastSeen, %Added, %PreviousRun);

my $cat = shift;

############# Read current contents, populate several hashes
### %PageNames - the name of the page 
### %Namespaces - the namespace of the page
### %Formats - the 'format' used to fill in the template code
### %Timestamps - the timestamp when the page was added to the category
###               (stored as text)
### %NTimestamps - timestamps for each page as an integer (used for sorting)
### %Extras - additional parameters in template

my $catesc = $cat;
$catesc =~ s/\//|/g;

open DATA, "<Data/$catesc";

$headline = <DATA>;
return unless ( $headline =~ /^Success/); 
  # First line of file is magic word used to detect transmission problems

while ( $line = <DATA> ) { 
  chomp $line;         # Remove trailing newline
  $line =~ s/^\{\{//;  # Remove wiki template syntax
  $line =~ s/\}\}$//;  
  ($format, $page, $ns, $time, $extra) = split /\|/, $line, 5;
  $key = $ns . ":" . $page;    # Unique identifier
  $Formats{$key} = $format;
  $Namespaces{$key} = $ns;
  $PageNames{$key} = $page;
  $Timestamps{$key} = $time; 
  $Extras{$key} = $extra;
}
close DATA;

################## Load caches from disk
###   %Added - when page was added to category
###   %LastSeen - last time page was known to be in the category
###   %PreviousRun - pages in the category last time this was run

open CACHE, "Cache/seen.$catesc";
while ( $line = <CACHE> ) { 
  chomp $line;
  ($time, $key) = split /\s+/, $line, 2;
  $LastSeen{$key} = $time;
}
close CACHE;

open CACHE, "Cache/added.$catesc";
while ( $line = <CACHE> ) { 
  chomp $line;
  ($time, $key) = split / -- /, $line, 2;
  $Added{$key} = $time;
}
close CACHE;

open CACHE, "Cache/previous.$catesc";
while ( $line = <CACHE> ) { 
  chomp $line;
  $PreviousRun{$line} = 1;
}
close CACHE;


########## Update caches (%LastSeen and %Added)

### Ensure that %LastSeen includes data for all pages currently
### in the category, so that we never query undefined values 
foreach $key ( keys %PageNames ) {
  if ( ! defined $LastSeen{$key} ) { 
    $LastSeen{$key} = $nowtime;
  }
}

### Update cache data for when pages were added to category
my $diff;
foreach $key ( keys %PageNames ) {
  if ( ! defined $Added{$key}) {
      # If this is the first time a page was seen, add it to cache
    $Added{$key} = $Timestamps{$key};
    next;   # move on to next key
  }

  $diff = $nowtime - $LastSeen{$key};
  if ( $diff > $Cutoffs{$cat} ) { 
      # If page was last seen longer in the past than the cutoff, 
      # then update the cache to reflect the current data
    $Added{$key} = $Timestamps{$key};
  }
}

### Update timestamps for pages currently in category
foreach $key ( keys %PageNames ) {
#  print "key '$key'\n";   
  if ( ! ( $Timestamps{$key} == $Added{$key} )) { 
    print STDERR "$key timestamps differ\n";
  }

  $diff = $nowtime - $LastSeen{$key};
#  print "$key $diff $nowtime $LastSeen{$key} $Cutoffs{$cat}\n";

  if ( $diff <= $Cutoffs{$cat} ) {
      #If page was recently seen in category, used cached timestap
    $Timestamps{$key} = $Added{$key};
  }

  $NTimestamps{$key} = str2time($Timestamps{$key});
}

### Update %LastSeen now so that is reflects the fact that
### all pages in the category right now were seen right now
foreach $key ( keys %PageNames ) {
    $LastSeen{$key} = $nowtime;
}


############  Update log 

open LOG, ">>Log";
foreach $key ( keys %PageNames ) { 
  if ( ! defined $PreviousRun{$key}) { 
    print LOG "$nowdate -- add -- $key\n";
  }
}

foreach $key ( keys %PreviousRun ) { 
  if ( ! defined $PageNames{$key} ) { 
    print LOG "$nowdate -- remove -- $key\n";
  }
}

close LOG;


open CACHEOUT, ">Cache/previous.$catesc";
foreach $key ( keys %PageNames ) { 
  print CACHEOUT "$key\n";
}
close CACHEOUT;


############# Write back the caches

open CACHEOUT, ">Cache/seen.$catesc";
foreach $key ( keys %LastSeen ) { 
  print CACHEOUT $LastSeen{$key} .  "\t" . $key . "\n";
}
close CACHEOUT;

open CACHEOUT, ">Cache/added.$catesc";
foreach $key ( keys %Added ) { 
  print CACHEOUT $Added{$key} . " -- " . $key . "\n";
}
close CACHEOUT;

########### Write back the category page

# my $timef;

open DATAOUT, ">Data/$catesc";
print DATAOUT $headline;   # Saved from when it was originally input

my @names = sort { $NTimestamps{$b} <=> $NTimestamps{$a} } keys %PageNames;

if ( defined $Reverse{$cat} ) { 
  @names = reverse @names;
  print STDOUT "Reverse $cat\n";
}

foreach $key ( @names ) {
#  $timef = strftime('%F %H:%M:%S', localtime($Timestamps{$key}));
  print DATAOUT "{{" . $Formats{$key} 
               . "|" . $PageNames{$key}
               . "|" . $Namespaces{$key} 
               . "|" . $Timestamps{$key}
               . "|" . $Extras{$key} 
               . "}}\n" ;
}

close DATAOUT;

}  ## End subroutine


################################################
### Main routine

my ($line, $time, $cat);

#### Read list of categories to list in reverse order 
open IN, "ReverseList";
while ( <IN> ) { 
  chomp;
  $Reverse{$_} = 1;
}
close IN;

##### Read the cutoff for each category
open IN, "CacheList";
while ( $line = <IN> ) { 
  chomp $line;
  ($time, $cat) = split /\s+/, $line, 2;
  $Cutoffs{$cat} = $time * 60 * 60;  
}
close IN;

####Handle each category that has a cutoff set
print "Updating caches and category listings\n";
foreach $cat ( keys %Cutoffs ) { 
  print "\t$cat\n";
  handleCat($cat);  
}

### End
