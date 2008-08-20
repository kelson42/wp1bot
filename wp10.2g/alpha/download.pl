#!/usr/bin/perl

binmode STDOUT, ":utf8";

use strict;
use Encode;
use Data::Dumper;
use POSIX;

#############################################################
# Define global variables and then load subroutines

our $api;

my $t = time();
our $global_timestamp = strftime("%Y%m%d%H%M%S", gmtime($t));
our $global_timestamp_wiki = strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($t));

require 'read_conf.pl';
our $Opts = read_conf(); # Also initializes library paths

require 'database_routines.pl';
require 'wp10_routines.pl';

#############################################################
# Create and initalize API object

require Mediawiki::API;

$api = new Mediawiki::API;  # global object 

$api->maxlag(-1);
$api->max_retries(20);

$api->base_url('http://en.wikipedia.org/w/api.php');
$api->debug_level(3);

if ( defined $Opts->{'api-credentials'} ) { 
#  $api->login_from_file($Opts->{'api-credentials'});
}


#############################################################

my $project;

$ARGV[0] = decode("utf8", $ARGV[0]);

if ( defined $ARGV[0] ) { 
  if ( $ARGV[0] eq '-reviews' ) { 
	# Don't download all the GAs and FAs unless explicitly asked to do so
	print "\n-- First, getting all FA, FL and GA data \n";
	download_review_data();	  
	exit;
  }

  if ( $ARGV[0] eq '-releases' ) { 
	download_release_data();	  
	exit;
  }

  my $project_details = db_get_project_details();

  if ( $ARGV[0] eq '-all' ) { 
    if ( $ARGV[1] eq 'under' && $ARGV[2] > 0 ) { 
      foreach $project ( keys %$project_details ) { 
        delete $project_details->{$project} 
         if ( $project_details->{$project}->{'p_count'} >= $ARGV[2] );
      }
    } elsif ( $ARGV[1] eq 'over' && $ARGV[2] > 0 ) { 
      foreach $project ( keys %$project_details ) { 
        delete $project_details->{$project} 
         if ( $project_details->{$project}->{'p_count'} < $ARGV[2] );
      }
    }

    my @projects = sort {    $project_details->{$b}->{'p_timestamp'} 
                         <=> $project_details->{$a}->{'p_timestamp'} }
                      keys %$project_details;

    foreach $project ( @projects )  {
      download_project(decode("utf8",$project));
    }
    exit;
  }

  if ( $ARGV[0] =~ /^-/ ) { 
    print << "HERE";

Unknown option $ARGV[0]
  $0                   : update all projects on wiki
  $0 -all              : update all projects already in database
    $0 -all under <N>  : limit -all to projects with <= N articles 
    $0 -all over <N>   : limit -all to projects with > N articles
  $0 -releases         : update WP 1.0 data
  $0 -reviews          : update FA/FL/GA data
  $0 <PROJECT>         : update PROJECT
HERE
    exit;
  }

  if ( project_exists($ARGV[0]) ) { 
    download_project($ARGV[0]);
    print "-- main driver done\n";
    exit;
  } else { 
    print "Looking for '$ARGV[0]' on wiki\n";
  }
}

my $projects = download_project_list();
foreach $project ( @$projects ) { 
  if ( defined $ARGV[0] ) {
    next unless ( $project =~ m/^\Q$ARGV[0]\E$/ );
  }
  download_project($project);
}

print "Done.\n";

exit;

__END__
