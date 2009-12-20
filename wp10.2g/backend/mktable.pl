#!/usr/bin/perl

# table_lib.pl                                                         
# Part of WP 1.0 bot                                                
# See the files README, LICENSE, and AUTHORS for additional information   

=head1 SYNOPSIS     
                                                                              
Backend program to fetch wikitext of summary tables

=cut 

require 'read_conf.pl';
our $Opts = read_conf();

require 'tables_lib.pl';

my $purge;
if ( $ARGV[0]  eq '--purge' ) { 
  shift @ARGV;
  $purge = 1;
}

if ( $ARGV[0] =~ /--project/ ) { 
  my ( $html, $wiki) = cached_project_table($ARGV[1], $purge);
  print $wiki;
  print "\n";
} elsif ( $ARGV[0] =~ /--global/ ) { 
  my ( $html, $wiki) = cached_global_ratings_table($purge);
  print $wiki;
} else { 
  print << "HERE";
Usage:

* Output wikicode for PROJECT:
   
   $0 [--purge] --project PROJECT    

* Output wikicode for global table:

   $0 [--purge] --global

The --purge causes to table to be recreated even if it is cached.
Otherwise the cached version is returned if it is available.

HERE
}

exit;

