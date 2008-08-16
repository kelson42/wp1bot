#!/usr/bin/perl

use strict;

sub read_conf { 
  my $filename;
  my $homedir = (getpwuid($<)) [7];
  
  if ( defined $ENV{'WP10_CREDENTIALS'} ) {
    $filename = $ENV{'WP10_CREDENTIALS'};
  } else { 
    $filename = $homedir . "/.wp10.conf";
  }

  die "Can't open database configuration '$filename'\n"
    unless -r $filename;

  my ($opt, $val, $line);
  my $opts = {};

  open CONF, "<", $filename;
  while ( $line = <CONF> ) {
    next if ( $line =~ /^\s*#/ );
    next if ( $line =~ /^\s*$/ );
    chomp $line;
    ($opt, $val) = split /\s+/, $line, 2;
    $val =~ s/\s*$//;

    if ( $opt eq 'lib' ) { 
      push @INC, $val;
    } else { 
      $opts->{$opt} = $val;
    }
  }
  close CONF;

  return $opts;
}


# Load successfully
1;
