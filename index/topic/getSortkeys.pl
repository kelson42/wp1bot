#!/usr/bin/perl

$max = 100;

open IN, "<", "CombinedList-0.7.txt" or die;

$c = 0;
while ( <IN> ) { 
  @parts = split;
  $c++;
  $parts[0] =~ s/'/\\'/g;
  push @list, $parts[0];
  if ( $max < scalar @list ) { 
    $s = join "','", @list;
    $s = "'$s'";
    system "./sortkey.sh", $s;
    @list = ();
    sleep 1;
    print STDERR "$c\n";
  }

}

if ( 0 < scalar @list ) { 
    $s = join "','", @list;
    $s = "'$s'";
    system "./sortkey.sh", $s;
    @list = ();
}
