#!/usr/bin/perl

use strict;
use Encode;
use URI::Escape;

# WP 1.0 bot - second generation
# CGI to display table of ratings information

require 'read_conf.pl';
our $Opts = read_conf();

require 'database_www.pl';
require 'layout.pl';
require 'init_cache.pl';

require CGI;
require CGI::Carp; 
CGI::Carp->import('fatalsToBrowser');

require DBI;
require POSIX;
POSIX->import('strftime');

my $cacheFile = init_cache();
my $cacheMem = {};

my $cgi = new CGI;
my %param = %{$cgi->Vars()};

our $dbh = db_connect($Opts);

my $projects = db_get_project_details();

print CGI::header(-type=>'text/html', -charset=>'utf-8');      

layout_header("Project index");

print "<ul>\n";
my $project;
foreach $project ( sort {$a cmp $b} keys %$projects ){
  project_index_link($project, $projects->{$project});
}
print "</ul>\n";

layout_footer();
exit;

#####################################################################


sub project_index_link { 
  my $project = shift;
  my $data = shift;

  my $URI = $ENV{'SCRIPT_URI'};
  $URI =~ s/index.pl//;

  my $listp = $URI . "list2.pl?projecta=" . uri_escape($project);
  my $tablep = $URI . "table.pl?project=" . uri_escape($project);

  my $name = $project;
  if ( defined $data->{'p_shortname'} ) { 
    $name = $data->{'p_shortname'};
  }

  my $line =  "<li> <b>$name</b>"
            . " (" . $data->{'p_count'} . "): " 
            . "<a href=\"$tablep\">summary table</a>, "
            . "<a href=\"$listp\">article list</a>";
 
  if ( defined $data->{'p_wikipage'} ) { 
    $line .= ", <a href=\"http://en.wikipedia.org/w/index.php?title=" 
           . uri_escape($data->{'p_wikipage'}) . "\">homepage</a>";
  }

  $line .= "</li>\n";
  print $line;
}
