#!/usr/bin/perl
# part of VeblenBot
# Carl Beckhorn, 2008
# Copyright: GPL 2.0

use strict;               

binmode STDOUT, ":utf8";

use Date::Parse;
use POSIX qw(strftime);
use Data::Dumper;

my (%Names, %Namespaces, %Timestamps, %NTimestamps, @Lines, %Extras);


### Two sorting subroutines

sub by-forward-time { 
  return $NTimestamps{$a} <=> $NTimestamps{$b};
}

sub by-reverse-time { 
  return $NTimestamps{$b} <=> $NTimestamps{$a};
}

###########################################
# Sort a category

sub handleCat {
  my $cat = shift;
  my $sort = shift;
  my $headline;

  print "Sorting category $cat with algorithm $sort\n$";

  my $catesc = $cat;
  $catesc =~ s/\//|/g;

  open DATA, "<Data/$catesc";
  $headline = <DATA>;      # First line is a magic word, don't disturb

  my $line;
  my ($name, $namespace, $timestamp, $format, $extra);

  while ( $line = <DATA>) { 
    $line =~ s/\}\}\n//;
    ($format, $name, $namespace, $timestamp, $extra) = split /\|/, $line, 5;
    $Names{$line} = $name;
    $Namespaces{$line} = $namespace;
    $Timestamps{$line} = $timestamp;
    $NTimestamps{$key} = str2time($timestamp);
    $Extras{$key} = $extra;
    push @Lines, $line;
  }

  my @output;

  if ( $sort eq 'forward-timestamp') { 
    @output = sort by-forward-timestamp @Lines; 
  } elsif ($sort eq 'reverse-timestamp' ) { 
    @output = sort by-reverse-timestamp @Lines;
  } 
}


################################################
### Main routine

my ($line, $sort, $cat);

open IN, "SortList";
while ( $line = <IN> ) { 
  chomp $line;
  ($sort, $cat) = split /\t/, $line, 2;
  handleCat($line, $sort);
}
close IN;

## End
