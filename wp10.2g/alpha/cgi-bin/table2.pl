#!/usr/bin/perl
use strict;
use Encode;

# WP 1.0 bot - second generation
# CGI to display table of ratings information

require 'read_conf.pl';
our $Opts = read_conf();

require Mediawiki::API;
my $api = new Mediawiki::API;
$api->debug_level(0); # no output at all 
$api->base_url('http://en.wikipedia.org/w/api.php');

use Data::Dumper;
use URI::Escape;

require POSIX;
POSIX->import('strftime');

require 'layout.pl';

my $timestamp = strftime("%Y-%m-%dT%H:%M:%SZ", gmtime(time()));

my $script_url = $Opts->{'list2-url'} 
 or die "No 'list2-url' specified in configuration.\n";


########################

require 'init_cache.pl';
my $cache = init_cache();
my $cache_sep = "<hr/><!-- cache separator -->\n";

########################

require CGI;
CGI::Carp->import('fatalsToBrowser');

my $cgi = new CGI;
my %param = %{$cgi->Vars()};

print CGI::header(-type=>'text/html', -charset=>'utf-8');      

my $proj = $param{'project'} || $ARGV[0];

use DBI;
require "database_www.pl";

our $dbh = db_connect($Opts);


layout_header('Summary tables');

my ($html, $wikicode) = cached_ratings_table();

  print "</div><hr/><div class=\"navbox\">\n";
  print_header_text();
  print "</div>\n<center>\n";
  print $html;
  print "</center>\n";
  print "\n";
  print "<hr/><div class=\"indent\"><pre>";
  print $wikicode;
  print "</pre></div>\n";

layout_footer();

exit;

#######################

sub cached_ratings_table { 


  print "<div class=\"indent\">\n";
  print "<b>Debugging output</b><br/>\n";
  print "Current time: $timestamp<br/>\n";

  my $key = "TABLE:GLOBAL";
  my $data;

  if ( defined $cgi->{'purge'} ) { 
    print "Purging cached output<br/>\n";
  } elsif ( $cache->exists($key) ) { 
    my $expiry = $cache->expiry($key);
    print "Cached output expires: " 
        . strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($expiry)) 
        . "<br/>\n";

    $data = $cache->get($key);
    my ($c_key, $c_timestamp, $c_html, $c_wikicode) = 
	  split /\Q$cache_sep\E/, $data, 4;

  } else {
    print "No cached output available<br/>\n";
  }

  print "Regenerating output<br/>\n";

  my ($html, $wikicode) = ratings_table($proj);
	
  print "</div><hr/><div class=\"navbox\">\n";
  print_header_text($proj);
  print "</div>\n<center>\n";
  print $html;
  print "</center>\n";
  print "\n";
  print "<hr/><div class=\"indent\"><pre>";
  print $wikicode;
  print "</pre></div>\n";

  $data = "TABLE:$proj" . $cache_sep 
        . $timestamp . $cache_sep
        . $html . $cache_sep 
        . $wikicode;

  $cache->set($key, $data, '1 hour');
}


sub ratings_table { 
  my $proj = shift;

  # Step 1: fetch totals from DB and load them into the $data hash

  my $sth = $dbh->prepare(
  "select count(distinct r_article), cq.c_replacement, ci.c_replacement
     from ratings 
     join categories as cq 
       on r_project = cq.c_project and cq.c_type = 'quality' 
                                  and cq.c_rating = r_quality
    join categories as ci
       on r_project = ci.c_project and ci.c_type = 'importance' 
                                   and ci.c_rating = r_importance
    group by cq.c_replacement, ci.c_replacement");

  $sth->execute();

  my ($SortQual, $SortImp, $QualityLabels, $ImportanceLabels) = 
	get_categories();

  print Dumper($SortQual);

  my $data = {};
  my $cols = {};
  my @row;

  while ( @row = $sth->fetchrow_array ) {
    if ( ! defined $row[1] ) { $row[1] = 'Unknown-Class'; }
    if ( ! defined $row[2] ) { $row[2] = 'Unknown-Class'; }
    if ( ! defined $data->{$row[1]} ) { $data->{$row[1]} = {} };

    # The += here is for 'Unknown-Class' classifications, which 
    # could happen either as a result of an actual category or as 
    # the result of the if statements above
    $data->{$row[1]}->{$row[2]} += $row[0];
    $cols->{$row[2]} = 1;

  }

  # Step 2 - remove any rows or columns that shouldn't be displayed

  my $col;
  foreach $col ( keys %$cols ) {
    if ( ! defined $SortImp->{$col} ) { 
      print "skip col $col\n";
      delete $cols->{$col};
    }
  }

  my $row;
  foreach $row ( keys %$data ) { 
    if ( ! defined $SortQual->{$row} ) { 
      print "skip row $row\n";
      delete $data->{$row};
    }
  }

  # The 'Assessed' classification is dynamically generated as we go. 
  $data->{'Assessed'} = {};

  # These, along with the totals, will appear in the final table. 
  # The important step here is the sorting. 
  my @PriorityRatings = sort { $SortImp->{$b} <=> $SortImp->{$a} } 
                             keys %$cols;
  my @QualityRatings =  sort { $SortQual->{$b} <=> $SortQual->{$a} } 
                             keys %$data; 

  use RatingsTable;
  my $table = RatingsTable::new();

  $QualityLabels->{'Total'} = "'''Total'''";
  $ImportanceLabels->{'Total'} = "'''Total'''";

  $table->title("Rated pages by quality and importance");
  $table->columnlabels($ImportanceLabels);
  $table->rowlabels($QualityLabels);
  $table->columntitle("'''Importance'''");
  $table->rowtitle("'''Quality'''");

  # Temporary arrays used to hold lists of row resp. column names
  my @P = (@PriorityRatings, "Total");
  my @Q = (@QualityRatings, "Total");

  $table->rows(\@Q);
  $table->columns(\@P);

  my $priocounts = {};  # Used to count total articles for each priority rating
  my $qualcounts = {};  # same, for each quality rating
  my $cells;

  my $total;
  
  $table->clear();

  my $qual;
  my $prio;
  my $total = 0;
  my $totalAssessed = {};  # To count 'Assessed' articles

  # Next step: fill in table data using the $data hash

  foreach $qual ( @QualityRatings ) {
    $qualcounts->{$qual}=0;
  }

  foreach $prio ( @PriorityRatings ) { 
    $priocounts->{$prio} = 0;
  }

  foreach $qual ( @QualityRatings ) {
    next if ( $qual eq 'Assessed' );  # nothing in $data for this
    foreach $prio ( @PriorityRatings ) { 

      if ( $data->{$qual}->{$prio} > 0 ) { 
         $table->data($qual, $prio, 
                   '[' . $script_url . "projecta=" . uri_escape($proj) 
                    . "&importance=" . uri_escape($prio) 
                    . "&quality=" . uri_escape($qual)  . ' ' 
                    . $data->{$qual}->{$prio} . "]");
      } else { 
         $table->data($qual, $prio, "");
      }

      $qualcounts->{$qual} += $data->{$qual}->{$prio};    
      $priocounts->{$prio} += $data->{$qual}->{$prio};    
      $total += $data->{$qual}->{$prio};    

      if ( ! ($qual eq 'Unassessed-Class' ) ) { 
        $totalAssessed->{$prio} += $data->{$qual}->{$prio};
        $totalAssessed->{'Total'} += $data->{$qual}->{$prio};
      }
    }
  }

  foreach $qual ( @QualityRatings ) {
    $table->data($qual, "Total", "'''[" 
                   . $script_url . "projecta=" . uri_escape($proj) 
#                    . "&importance=" . uri_escape($prio) 
                    . "&quality=" . uri_escape($qual)  . ' ' 
                    . $qualcounts->{$qual} . "]'''");
  }

  foreach $prio ( @PriorityRatings ) { 
    $table->data("Total", $prio, 
                "'''[" . $script_url . "projecta=" . uri_escape($proj) 
                    . "&importance=" . uri_escape($prio) 
#                    . "&quality=" . uri_escape($qual)  
                   . ' ' . $priocounts->{$prio} . "]'''");

    $table->data("Assessed", $prio, 
                "'''[" . $script_url . "projecta=" . uri_escape($proj) 
                    . "&importance=" . uri_escape($prio) 
                    . "&quality=Assessed" 
                   . ' ' . $totalAssessed->{$prio} . "]'''" );
  }

  $table->data("Total", "Total", "'''[" 
                   . $script_url . "projecta=" . uri_escape($proj) 
                   . ' ' . $total . "]'''");

  $table->data("Assessed", "Total", 
                "'''[" . $script_url . "projecta=" . uri_escape($proj) 
                    . "&quality=Assessed" 
                   . ' ' . $totalAssessed->{'Total'} . "]'''" );

  my $code = $table->wikicode();

  my $r =  $api->parse($code);

  return ($r->{'text'}, $code);
}

###################################

sub get_categories { 

  my $Assessed = "Assessed";
  my $Assessed_Class = "Assessed-Class";
  my $Unassessed_Class = "Unassessed-Class";

  my $sortQual = { 'FA-Class' => 500, 'FL-Class' => 480, 'A-Class' => 425, 
              'GA-Class' => 400, 'B-Class' => 300, 'C-Class' => 225, 
              'Start-Class'=>150, 'Stub-Class' => 100, 'List-Class' => 80, 
              $Assessed_Class => 20, $Unassessed_Class => 0};

  my $sortImp= { 'Top-Class' => 400, 'High-Class' => 300, 
                 'Mid-Class' => 200, 'Low-Class' => 100, 
                 $Unassessed_Class => 0};


  my $qualityLabels = {};
  my $importanceLabels = {};

  my $k;
  foreach $k ( keys %$sortQual ) { 
    $qualityLabels->{$k} = "{{$k}}";
  }

  $qualityLabels->{$Assessed} = "'''$Assessed'''";

  foreach $k ( keys %$sortImp ) { 
    $importanceLabels->{$k} = "{{$k}}";
  }

  $importanceLabels->{'Unassessed-Class'} =~ s/Unassessed-Class/No-Class/;

  return ($sortQual, $sortImp, $qualityLabels, $importanceLabels);

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
  print "<select name=\"project\">\n";

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
  print "</form>\n";
  print "<hr/>\n";

  return $projects;
}

#####################################################################

sub get_link_from_api { 
	my $text = shift;
	my $r =  $api->parse($text);
	my $t = $r->{'text'};
	
	# TODO: internationalize this bare URL
	my $baseURL = "http://en.wikipedia.org";
	$t =~ s!^<p>!!;
	my @t = split('</p>',$t);
	$t = @t[0];
	
    @t = split('"',$t,2);
    $t = @t[0] . "\"" . $baseURL .  @t[1];
	
	return $t;
}

sub print_header_text {
	my $project = shift;
	my ($timestamp, $wikipage, $parent, $shortname);
	my $listURL = $script_url;
	$listURL = $listURL . "projecta=" . $project . "&limit=50";
	
	($project, $timestamp, $wikipage, $parent, $shortname) = 
	get_project_data($project);
	if ( ! defined $wikipage) 
	{
		print "Data for $project "; 	
	}
	elsif ( ! defined $shortname) 
	{
		print "Data for " . get_link_from_api("[[$wikipage]]") . " "; 
	}
	else
	{
		print "Data for " . get_link_from_api("[[$wikipage|$shortname]]") . " "; 		
	}
	print "(<a href=\"" . $listURL . "\">lists</a> | <b>summary table</b>)\n";
	
}



sub cached_ratings_table { 
  print "<div class=\"indent\">\n";
  print "<b>Debugging output</b><br/>\n";
  print "Current time: $timestamp<br/>\n";

  my $key = "GLOBAL:TABLE";
  my $data;

  if ( $cache->exists($key) && ! defined $ARGV[0] ) { 
    my $expiry = $cache->expiry($key);
    print "Cached output expires: " 
        . strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($expiry)) 
        . "<br/></div>\n";

    $data = $cache->get($key);
    my ($c_key, $c_html, $c_wikicode) = 
          split /\Q$cache_sep\E/, $data, 3;

    return ($c_html, $c_wikicode);
 }

  print "No cached output, regenerating\n";
  my $ts = time();
  
  my ($html, $wikicode) = ratings_table();

  $ts = time() - $ts;
  print "Done; $ts seconds elapsed.</div>\n";
  sleep 4;

  $data = "GLOBAL:TABLE" . $cache_sep 
        . $html . $cache_sep 
        . $wikicode;

  $cache->set($key, $data, '1 hour');


  return ($html, $wikicode);
}
