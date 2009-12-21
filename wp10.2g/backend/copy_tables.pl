#!/usr/bin/perl

# copy_tables.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for additional information

=head1 SYNOPSIS

Copy assessment tables to the wiki

=cut

binmode STDOUT, ":utf8";

use strict;
use Encode;
use Data::Dumper;
use POSIX;
use Getopt::Long;

#############################################################
# Define global variables and then load subroutines

require 'read_conf.pl';
our $Opts = read_conf(); # Also initializes library paths

require 'database_routines.pl';
require 'wp10_routines.pl';
require 'api_routines.pl';
require 'tables_lib.pl';

my $start_time = time();

my $project_details = db_get_project_details();

my $project;

my $count = scalar keys %$project_details;

print "Count: $count\n";

my $i = 0;
foreach $project ( sort {$a cmp $b} keys %$project_details ) {
  next unless ( $project =~ /\Q$ARGV[0]\E/);
    $i++;
    print "$i / $count $project\n";

    my ( $html, $wiki) = cached_project_table($project);

    $wiki = munge($wiki);

    my $page = "User:WP 1.0 bot/Tables/Project/$project";
    my $summary = "Copying assessment table to wiki";

    api_edit($page, $wiki, $summary);

    exit;
}

#######################################
# In case we need to do some reformatting for the wiki

sub munge { 
  my $text = shift;
  return $text;
}
