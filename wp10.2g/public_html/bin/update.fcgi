#!/usr/bin/perl

# update.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for additional information

=head1 SYNOPSIS

CGI program to update data for a project

=cut

use strict;
use Encode;

require 'read_conf.pl';
our $Opts = read_conf();

require Mediawiki::API;
my $api = new Mediawiki::API;
$api->debug_level(0); # no output at all 
$api->base_url($Opts->{'api-url'});

use Data::Dumper;
use URI::Escape;

require POSIX;
POSIX->import('strftime');

require 'layout.pl';

my $timestamp = strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time()));

my $list_url = $Opts->{'list2-url'} 
 or die "No 'list2-url' specified in configuration.\n";

my $log_url = $Opts->{'log-url'} 
 or die "No 'list2-url' specified in configuration.\n";

########################

use DBI;
require "database_www.pl";
our $dbh = db_connect_rw($Opts);

require 'cache.pl';
my $cache_sep = "<hr/><!-- cache separator -->\n";

########################

require CGI;
use CGI;
use CGI::Carp qw(warningsToBrowser fatalsToBrowser); 

my $cgi;
my $loop_counter;
if ( $Opts->{'use_fastcgi'} ) {
  require CGI::Fast;
  while ( $cgi = CGI::Fast->new() ) { 
    main_loop($cgi);
  }
} else {
  $cgi = new CGI;
  $loop_counter = -5;
  main_loop($cgi);
}

exit;

############################################################

sub main_loop { 
  my %param = %{$cgi->Vars()};

  select STDOUT;
  $| = 1;

  print CGI::header(-type=>'text/html', -charset=>'utf-8');      

  my $proj = $param{'project'} || $ARGV[0] ;

  my $prog = $Opts->{'download-program'};

  if ( defined $proj ) { 
    layout_header("Updating project data for $proj");
    print "<pre>\n";
    open PIPE, "$prog '$proj'|";
    while ( <PIPE> ) { 
      print;
    }
    close PIPE;
    print "</pre>\n";
  } else { 
    layout_header('Update project data');
    input_html();
  }

  $loop_counter++;
  layout_footer("Debug: PID $$ has handled $loop_counter requests");

# XXX
  exit;

  if ( $loop_counter >= $Opts->{'max-requests'} ) { exit; }
}

############################################################

sub input_html { 
  print << "HERE";
    <form>
      <fieldset class="inner">
        <legend>Update project</legend>
          Project name <input type="text" name="project"><br/>
          <input type="submit" value="Go">
      </fieldset>
    </form>
HERE
}

