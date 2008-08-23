#!/usr/bin/perl

use strict;
#use Data::Dumper;
# Internal variable holding the configuration variables
my $settings = {};

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
    next if ( $line =~ /\s*#/ );
    next if ( $line =~ /^\s*$/ );
    chomp $line;
    ($opt, $val) = split /\s+/, $line, 2;
    $val =~ s/\s*$//;

    if ( $opt eq 'lib' ) { 
      push @INC, $val;
    } else { 
      $opts->{$opt} = $val;
	  $settings->{$opt} = $val;
    }
  }
  close CONF;

  return $opts;
}

sub get_conf() { 
  my $var = shift;
  my $val;
		
  if ( defined $settings->{$var})
  {
    $val = $settings->{$var};
	# print "$var found in settings; value = $val\n";
  }
  else
  {
    print "$var not found in settings\n";
  }
  return $val;	
}


# Load successfully
1;
