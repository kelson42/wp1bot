#!/usr/bin/perl
use strict;


# make a list of all projects in a particular wp 1.0 cat and how many
# articles they have

use Data::Dumper;

#print "Phase 1\n";


my $AllArts;
my @parts;
my @cats;
my $Projs;
my $proj;
my $p;
my $cat;
my $pages;
my $page;
my $k;
my $count;
my $arts;
my $c;

my $seen;

open IN, "<", "CombinedList-0.7.txt" or die;
while ( <IN> ) { 
  chomp;
  @parts = split /\t/;
  $AllArts->{$parts[0]} = 1;
}
close IN;

open IN, "<", "Selected.txt";
while ( <IN> ) { 
  chomp;
  @parts = split /\|/;
  if ( ! defined $Projs->{$parts[1]} ) { 
    $Projs->{$parts[1]} = {};
  }
  $Projs->{$parts[1]}->{$parts[0]} = 1;
#  print "Add " . $parts[0] . " to " . $parts[1] . "\n";
#  print Dumper($Projs->{".NET"});
}
close IN;


open IN, "<", "Manual.arts" or die;
while ( <IN> ) { 
  chomp;
  @parts = split /\|/;
  if ( ! defined $Projs->{$parts[1]} ) { 
    $Projs->{$parts[1]} = {};
  }
  $Projs->{$parts[1]}->{$parts[0]} = 1;
#  print "Add " . $parts[0] . " to " . $parts[1] . "\n";
#  print Dumper($Projs->{".NET"});
}
close IN;


#foreach $proj ( sort {$a cmp $b} keys %$Projs ) { 
#  print "$proj " . (scalar keys %{$Projs->{$proj}}) . "\n";
#}
#	exit;


my %Keys = ( 
  'Arts' => 'Arts, langauge, and literature',
  'LL' => 'Arts, langauge, and literature',
  'PR' => 'Philosophy and religion',
  'EL' => 'Everyday life',
  'SSS' => 'Society and social sciences',
  'G' => 'Geography',
  'H' => 'History',
  'AST' => 'Applied sciences and technology',
  'M' => 'Mathematics',
  'NS' => 'Natural sciences',
  'Bio' => 'Biography'
);


my $line = 0;
while ( <STDIN> ) { 
  $line++;
  chomp;
  @parts  = split /\t/;
  @cats = split /,/, $parts[1];
#  print "See: $parts[0]\n";

  if ( defined $parts[2] ) { 
   die "Check line $line\n";
  }

  foreach $cat ( @cats ) { 
    $cat =~ s/\s//g;
 #   print "Cat: $cat\n";
    die "line $line: bad prefix '$cat'\n"
      unless defined $Keys{$cat};
    $k = $Keys{$cat};
    if ( ! defined $pages->{$k} ) { 
      $pages->{$k} = {};
 #     print "Create: $k\n";
    }
#    print "Key: $k\n";
    $pages->{$k}->{$parts[0]} = 1;
  }
}

$seen = {};

foreach $page ( sort {$a cmp $b} keys %$pages ) { 
  print "Page: $page\n";
  $count = 0;
  $arts = {};
  foreach $proj ( sort {$a cmp $b} keys %{$pages->{$page}} ) { 
    $c = scalar keys %{$Projs->{$proj}};
    print "\t" . $proj . " : " . $c . "\n";
    foreach $p ( keys %{$Projs->{$proj}} ) { 
      $arts->{$p} = 1;
      $seen->{$p} = 1;
    }
    $count = scalar keys %$arts;
#    print "\t\tSubtotal: $count\n";
  }
  $count = scalar keys %$arts;
  print "\tTotal: $count\n";
}

print "-------------\n";
print "Orphans: " . (scalar keys %$AllArts) . "\n";
print "Seen: " . (scalar keys %$seen) . "\n";

open OUT, ">", "Orphans";
foreach $k ( keys %$AllArts ) { 
  if ( ! defined $seen->{$k} ) { 
    print OUT "$k\n";
  }
}
close OUT;

