#!/usr/bin/perl

# index.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for additional information

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

my $table = sort_projects($projects);

my $project_count = scalar keys %$projects;

# Fix this
my $uri = "http://toolserver.org/~cbm//cgi-bin/wp10.2g/alpha/cgi-bin";

print "<center>\n";
print "<b>$project_count</b> projects: \n";
my $letter;
foreach $letter ( sort {$a cmp $b} keys %$table ) {
  print "<a href=\"$uri/index.pl#" . $letter . "\">$letter</a> ";
}
print "<br/><a href=\"$uri/table2.pl\">Overall ratings table</a>\n"; 
print "</center><hr/>\n";

print "<center><table class=\"wikitable\">\n";

foreach $letter ( sort {$a cmp $b} keys %$table ){
print << "HERE";
  <tr>
    <th colspan="5" style="text-align: center; padding-top: 1em;"">
         &mdash;&nbsp;<B>$letter</B>&nbsp;&mdash;<a name="$letter"/>
    </th>
  </tr>
  <tr>
        <th>Project</th>
        <th>Articles</th>
        <th>Data</th>
        <th>Quality<br/>ratings</th>
        <th>Importance<br/>ratings</th>
   </tr>
HERE

  my $project;
  foreach $project ( sort {$a cmp $b} keys %{$table->{$letter}} ){
    project_index_link($project, $projects->{$project});
  }
  print "</td></tr>\n";
}

print "</table></center>\n";
layout_footer();
exit;

#####################################################################

sub project_index_link { 
  my $project = shift;
  my $data = shift;

  my $listp = make_list_link({'projecta'=>$project});
  my $tablep = make_table_link($project);
  my $logp = make_log_link({'project'=>$project});
  my $catp = "/wiki/Category:" . uri_escape($project)
             . " articles by quality";
  

  my $name = $project;
  if ( defined $data->{'p_shortname'} ) { 
    $name = $data->{'p_shortname'};
  }

  if ( defined $data->{'p_wikipage'} ) { 
    $name =  "<a href=\"http://en.wikipedia.org/w/index.php?title=" 
            . uri_escape($data->{'p_wikipage'}) . "\">$name</a>";
  }

  my $line =  "<tr><td><b>$name</b></td>"
            . "<td style=\"text-align: right;\">" . 
               commify($data->{'p_count'}) . "</td>" 
            . "<td>&nbsp;<a href=\"$tablep\">table</a>, "
            . "<a href=\"$listp\">list</a>, "
            . "<a href=\"$logp\">log</a>, "
            . "<a href=\"$catp\">cat</a>";
  $line .= "</td>";

  if ( $data->{'p_count'} != 0 ) { 
#    $line .= "<table style=\"background: transparent; border: 0\">" 
#             . "<tr><td>\nQuality:";		
    $line .= "<td>";
    $line .= print_progress_bar(($data->{'p_qcount'} / $data->{'p_count'}) * 100);
#    $line .= "</td><td>Importance:";
    $line .= "</td><td>";
    $line .= print_progress_bar(($data->{'p_icount'} / $data->{'p_count'}) * 100);
#  $line .= "</td></tr></table>";
    $line .= "</td>";
  }
	
  $line .= "</tr>\n";
  print $line;
}

#####################################################################
# TODO: figure out how the [[fr:Template:Avacement]] template works, and
# copy it to enwiki
sub print_progress_bar {
  my $number = shift;

  # Special case: if none at all are assessed, that means the project
  # just doesn't do that sort of assessment (particularly with 
  # importance ratings)
  if ( $number == 0 ) { return "";}
		
  # Get the color of the bar
  my $color = get_bar_color($number);
	
  # Format the input to two decimal digits
  my $rounded = sprintf("%.2f", $number);
		
  return << "HERE";
    <div class="progress_cell" style="">
    <div class="progress_bar" style="background:#$color; width:$rounded%;">
    <div class="progress_text" style="">$rounded&#160;%</div></div></div>
HERE
}

#####################################################################

sub sort_projects { 
  my $projects= shift;

  my $table = {};

  my ($p, $name, $letter);

  foreach $p ( keys %$projects ) {
    $name = $p;
    if ( defined $projects->{$p}->{'p_shortname'} ) { 
      $name = $projects->{$p}->{'p_shortname'};
    }
    $letter = substr(decode("utf8", $name), 0, 1) ;
    $letter = encode("utf8", $letter);

    if ( ! ( $letter =~ /[A-Z]/ ) ) { 
      if ( $letter =~ /[0-9]/ ) { 
        $letter = '0&ndash;9';
      } else { 
        $letter = "[Other]";
      }
    }

    if ( ! defined $table->{$letter} ) { 
      $table->{$letter} = {};
    }

    $table->{$letter}->{$p} =  $projects->{$p};

  }

  return $table;

}

#####################################################################
sub commify {
	# commify a number. Perl Cookbook, 2.17, p. 64
	my $text = reverse $_[0];
	$text =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
	return scalar reverse $text;
}
#####################################################################
