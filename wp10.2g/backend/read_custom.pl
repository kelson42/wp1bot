#!/usr/bin/perl

# read_custom.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for additional information

use strict;
use Data::Dumper;

sub read_custom { 
  my $filename;
  my $settings;
  my $homedir = (getpwuid($<))[7];
  
  $filename = 'Custom.tables.dat';

  die "Can't open file '$filename'\n"
    unless -r $filename;

  if ( $ARGV[0] eq '--debug' ) { 
    print "Reading configuration file '$filename'\n";
  }

  open CONF, "<", $filename 
    or die "Can't open configuration file '$filename': $!\n";

  my $text = "";
  my $line;
  
  while ( $line = <CONF> ) {
    $text .= $line;
  }
  close CONF;

  $settings = eval '{ ' . $text . ' }';

  if ( $@ ) { 
    die "\nError parsing configuration file '$filename':\n  $@\n";
  }


  if ( $ARGV[0] eq '--debug' ) { 

    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Sortkeys = 1;
    print "Configuration settings: \n";
    print Dumper($settings);
    print "\n";
  }

  check_custom($settings);

  return $settings;
}

sub check_custom { 
  my $settings = shift;
  my $tablen;
  my $table;
  my $die = 0;

  foreach $tablen ( keys %$settings ) { 
    print "Table: $tablen\n";
    $table = $settings->{$tablen};

    if ( ! defined $table->{'type'} ) { 
      fatal($tablen, "no type specified");
      $die++;
    }

    print "  type: " . ($table->{'type'}) . "\n";

    if ( 'projectcategory' eq $table->{'type'} ) { 
      my $param;
      foreach $param ( ('cat', 'catns', 'project', 'title', 'dest') ) { 
        if ( ! defined $table->{$param} ) { 
          fatal($tablen, "parameter '$param' not specified");
          $die++;
        } else { 
          print "  $param: " . ($table->{$param}) . "\n";
        }
      } 
      
      if ( ! defined $table->{'config'} ) { 
        $table->{'config'} = {};
      } else { 
        print "  configuration:\n";
        my $param;
        foreach $param ( sort {$a cmp $b} keys %{$table->{'config'}} ) { 
          print "    $param: " . $table->{'config'}->{$param} . "\n";
        }   
      }
      print "\n";
    }  # projectcategory type
  }

  if ( $die > 0 ) { 
    die "Encountered $die fatal errors, aborting\n";
  }

}


sub fatal { 
  my $table = shift;
  my $error = shift;
  print "Fatal error with configuration of '$table': $error\n";
}

# Load successfully
1;
