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
require Mediawiki::API;

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

	if ( $data->{'p_count'} != 0 ) { 
		print_progress_bar(($data->{'p_qcount'} / $data->{'p_count'}) * 100);
		print_progress_bar(($data->{'p_icount'} / $data->{'p_count'}) * 100);
	}
	
  $line .= "</li>\n";
  print $line;
}

#####################################################################
# FIXME: hack hack hack 
# Instead of making the code resemble frwiki's output, we just
# copy it from frwiki via the API
# TODO: figure out how the {{avancement}} template works, and
# copy it to enwiki
sub print_progress_bar {
	my $number = shift;
	my $fr_api = new Mediawiki::API;
	$fr_api->debug_level(0); # no output at all 
	$fr_api->base_url('http://fr.wikipedia.org/w/api.php');
	
	# Format the input to two decimal digits
	my $rounded = sprintf("%.2f", $number);
	my $r =  $fr_api->parse("{{Avancement|avancement=$rounded}}");
	my $t = $r->{'text'};
	$t =~ s!^<p>!!;
	my @t = split('</p>',$t);
	print $t;
}