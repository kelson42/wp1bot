#!/usr/bin/perl

while ( <STDIN> ) { 
  chomp;
  @parts = split /\t/;
  shift @parts;

  foreach $p ( @parts ) { 
    $proj{$p} =1;
  }
}

foreach $p ( sort {$a cmp $b} keys %proj ) { 
  print "$p\t\n";
}

