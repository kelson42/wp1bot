#!/usr/bin/perl

# copy_tables.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for additional information

=head1 SYNOPSIS

Copy assessment tables to the wiki

=cut

use utf8;
use encoding 'utf8';

binmode STDOUT, ":utf8";
select STDOUT;
$| = 1;

use strict;
use Encode;

#############################################################
# Define global variables and then load subroutines

require 'read_conf.pl';
our $Opts = read_conf(); # Also initializes library paths

require 'database_routines.pl';
require 'wp10_routines.pl';
require 'api_routines.pl';
require 'tables_lib.pl';
require 'custom_tables.pl';
require 'read_custom.pl';


############################################################

if ( $ARGV[0] =~ /^--project/ ) {  # accept --project and --projects
  copy_project_tables($ARGV[1]);
} elsif ( $ARGV[0] eq '--global' ) { 
  copy_global_table();
} elsif ( $ARGV[0] eq '--custom' ) { 
  copy_custom_tables($ARGV[1]);
} else { 
  print << "HERE";
Usage:

* Copy project tables:

  $0 --project [PROJECT]

* Copy global table:

  $0 --global 

* Copy custom tables:

  $0 --custom

HERE
}

exit;

############################################################

sub copy_project_tables { 
  my $filter = shift;

  my $project_details = db_get_project_details();
  my $project;

  my $count = scalar keys %$project_details;
  print "Count: $count\n";

  my $i = 0;
  foreach $project ( sort {$a cmp $b} keys %$project_details ) {
    next unless ( (! defined $filter ) || ($project =~ /^\Q$filter\E$/));
    $i++;
    print "\n$i / $count $project\n";

    my $page = "User:WP 1.0 bot/Tables/Project/$project";
    my $summary = "Copying assessment table to wiki";
    my ( $html, $wiki) = cached_project_table($project);
    $wiki = munge($wiki, 'project');

    if ( ! defined $ENV{'DRY_RUN'}) {
      api_edit(encode("utf8", $page), $wiki, $summary);
    }
  }
}

############################################################

sub copy_custom_tables { 

  my $filter = shift;
print "F: '$filter'\n";

  my $custom = read_custom();

  my $table;
  my $code;
  my $dest;
  my $summary;

  foreach $table ( keys %$custom ) { 
    if ( defined $filter ) { 
      next unless ( $table =~ /\Q$filter\E/);  
    }

    print "T: '$table'\n";

    if ( ! defined $custom->{$table}->{'dest'} ) { 
      die "No destination for table '$table'\n";
    } else { 
      $dest = $custom->{$table}->{'dest'};
    }

    if ( $custom->{$table}->{'type'} eq 'projectcategory' ) { 
      print "... projectcategory\n";
      $code = project_category_table($custom->{$table});
    } elsif ( $custom->{$table}->{'type'} eq 'customsub' ) { 
      print "... customsub \n";
      $code = &{$custom->{$table}->{'customsub'}}();
    }  else { 
      die ("Bad table type for '$table'\n");
    }

    $code = munge($code, 'project');
    $summary = "Copying custom table '$table' to wiki\n";

    if ( ! defined $ENV{'DRY_RUN'}) {
      api_edit($dest, $code, $summary);
    } else { 
      print "DRY RUN - not editing wiki\n";
    }
  }
}

############################################################

sub project_category_table { 
  my $data = shift;

  my $project = $data->{'project'};
  my $cat = $data->{'cat'};
  my $catns = $data->{'catns'};
  my $title = $data->{'title'};
  my $dest = $data->{'dest'};
  my $config = $data->{'config'};

  my $summary = "Copying assessment table to wiki";

  my ($html, $wiki) = make_project_table($project, $cat, $catns, $title, $config);

  return $wiki;
}

############################################################

sub copy_global_table { 
  print "Copying global table\n";

  my $page = "User:WP 1.0 bot/Tables/OverallArticles";
  my $summary = "Copying assessment table to wiki";
  my ( $html, $wiki) = cached_global_ratings_table();
  $wiki = munge($wiki, 'global');

  api_edit($page, $wiki, $summary);
  exit;
}

############################################################
# In case we need to do some reformatting for the wiki

sub munge { 
  my $text = shift;
  my $mode = shift;

  if ( $mode eq 'project' ) { 
      # Don't center the tables so they can be trancluded more flexibly
    $text =~ s/margin-left: auto;//;
    $text =~ s/margin-right: auto;//;
  }

  return $text;
}

############################################################
