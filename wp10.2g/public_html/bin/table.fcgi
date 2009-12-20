#!/usr/bin/perl

# table.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for additional information

=head1 SYNOPSIS

CGI program to display table of assessment info for one project

=cut

use strict;
use Encode;

require 'read_conf.pl';
our $Opts = read_conf();
my $NotAClass = $Opts->{'not-a-class'};

require Mediawiki::API;
my $api = new Mediawiki::API;
$api->debug_level(0); # no output at all 
$api->base_url($Opts->{'api-url'});

use Data::Dumper;
use URI::Escape;

require POSIX;
POSIX->import('strftime');

require 'layout.pl';

require 'tables_lib.pl';

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

require 'tables_lib.pl';

########################

require CGI;
CGI::Carp->import('fatalsToBrowser');

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

  print CGI::header(-type=>'text/html', -charset=>'utf-8');      

  my $proj = $param{'project'} || $ARGV[0] || '';

  layout_header('Project summary tables');
  my $projects = query_form($proj);

  if ( defined $proj && defined $projects->{$proj} ) {
    my ($html, $wiki, $timestamp) = cached_project_table($proj, $cgi->{'purge'});

    print "<div class=\"navbox\">\n";
    print_header_text($proj);
    print "</div>\n<center>\n";
    print $html;
    print "</center>\n";
  }  

  $loop_counter++;
  layout_footer("Debug: PID $$ has handled $loop_counter requests");
  if ( $loop_counter >= $Opts->{'max-requests'} ) { exit; }
}


#################################

sub query_form {

  my $projSelected = shift;

  my $projects = {};
  my @row;

  my $sth = $dbh->prepare("SELECT p_project FROM projects");
  $sth->execute();

  while ( @row = $sth->fetchrow_array ) { 
    $projects->{$row[0]} = 1;
  }

  print "<form>\n"; 
  print "<fieldset style=\"display: inline;\">\n";
  print "<legend>Generate table</legend>\n";
  print "<label for=\"project\">Project:</label>\n";
  print "<select name=\"project\" id=\"project\">\n";

  my $p;
  foreach $p ( sort { $a cmp $b} keys %$projects) { 
    if ( $p eq $projSelected ) { 
      print "<option value=\"" . $p . "\" selected>" . $p ."</option>\n";
    } else {
      print "<option value=\"" . $p . "\">" . $p . "</option>\n";
    }
  }

  print "</select>\n";
  print "<input type=\"submit\" value=\"Make table\"/>\n";
  print "</fieldset></form>\n";
  print "\n";

  return $projects;
}

#####################################################################

sub print_header_text {
  my $project = shift;
  my ($timestamp, $wikipage, $parent, $shortname);
 
  my $listURL = $list_url;
  $listURL = $listURL . "?projecta=" . $project . "&limit=50";
  
  my $logURL = $log_url;
  $logURL = $logURL . "?project=" . $project;

  ($project, $timestamp, $wikipage, $parent, $shortname) = 
        get_project_data($project);

  if ( ! defined $wikipage)   {
    print "Data for <b>$project</b> ";   
  }  elsif ( ! defined $shortname)   {
    print "Data for <b>" . get_link_from_api("[[$wikipage]]") . "</b> "; 
  }  else  {
    print "Data for <b>" . get_link_from_api("[[$wikipage|$shortname]]") . "</b> ";     
  }

  print "(<a href=\"" . $listURL . "\">lists</a> | "
           .  "<a href=\"" . $logURL . "\">log</a> | "
           . " <b>summary table</b>)\n";  
}
