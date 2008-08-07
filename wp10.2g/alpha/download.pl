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

use lib '/home/veblen/NewMath';
require 'database_routines.pl';
require 'wp10_routines.pl';

#############################################################
# Create and initalize API object

use lib '/home/veblen/VeblenBot';
use Mediawiki::API;
$api = new Mediawiki::API;  # global object 
$api->maxlag(12);
$api->max_retries(20);

$api->base_url('http://en.wikipedia.org/w/api.php');
$api->debug_level(3);
$api->login_from_file("/home/veblen/api.credentials");

#############################################################

my $project;

if ( defined $ARGV[0] ) { 
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
