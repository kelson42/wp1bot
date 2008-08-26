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
my $api = new Mediawiki::API;
$api->debug_level(0); # no output at all 
$api->base_url(get_conf('api_url'));

my $cacheFile = init_cache();
my $cacheMem = {};

require CGI;
require CGI::Carp; 
CGI::Carp->import('fatalsToBrowser');

require DBI;
require POSIX;
POSIX->import('strftime');

my $cgi = new CGI;
my %param = %{$cgi->Vars()};

if ( $param{'limit'} > 1000 ) { 
  $param{'limit'} = 1000;
}

my $p;
my $logFile = "log." . time() . "." . $$;
my $logEntry = $logFile;

foreach $p ( keys %param ) { 
  $param{$p} =~ s/^\s*//;
  $param{$p} =~ s/\s*$//;
  $logEntry .= "&" . uri_escape($p) . "=" . uri_escape($param{$p});
}

# FIXME: Use get_conf instead of Opts
if ( defined $Opts->{'log-dir'} 
     && -d $Opts->{'log-dir'} ) { 
  open LOG, ">", $Opts->{'log-dir'} . "/" . $logFile;
  print LOG $logEntry . "\n";
  close LOG;
}

my $proj = $param{'project'} || $ARGV[0];

our $dbh = db_connect($Opts);

print CGI::header(-type=>'text/html', -charset=>'utf-8');      

if (defined $param{'project'}) {
  layout_header("Assessment logs: " . $proj . " " . get_conf('pages_label'), 1);
} else {
  layout_header("Assessment logs", 1);
}


my $projects = list_projects();
query_form(\%param, $projects);

if ( ! defined $param{'entry'} ) { 
  log_table(\%param, $projects);
}

layout_footer();

exit;

###########################################################################
###########################################################################


sub log_table { 
   my $params = shift;
   my $projects = shift;
  
   my ($project, $pagename, $oldrating, $newrating , 
       $pagenameWC, $offset, $limit);
  
   $project = $params->{'project'} || "";
   $pagename = $params->{'pagename'} || "";
   $oldrating = $params->{'oldrating'} || "";
   $newrating = $params->{'newrating'} || "";
   $pagenameWC = $params->{'pagenameWC'} || 0;
   $offset = $params->{'offset'} || 1;
   $limit = $params->{'limit'} || 1000;
  
   if ( $offset > 0) { $offset--; }
   if ( $limit > 1000 ) { $limit = 1000; } 
   # FIXME: use get_conf('class-suffix'); not sure how that would work 
   # with the /-Class/ regexp below
   if ( $oldrating =~ /\w|\d/ && ! $oldrating =~ /-Class/) { 
     $oldrating .= "-Class";
   }
  
   if ( $newrating =~ /\w|\d/ && ! $newrating =~ /-Class/) { 
     $newrating .= "-Class";
   }
  
   if ( (! $project =~ /\w|\d/) && (! $pagename =~ /\w|\d/ ) ) { 
     return;
   }
  
   my @qparam;
   my @qparamc;
  
   my $queryc = 'SELECT count(l_article) FROM logging ';

   my $query = << "HERE";
 SELECT l_project, l_article, l_action, l_timestamp, 
        l_old, l_new, l_revision_timestamp
 FROM logging
HERE
	  
   $query .= " WHERE ";
   $queryc .= " WHERE ";
  
   if ( $project =~ /\w|\d/ ) { 
     if ( defined $projects->{$project} ) { 
       $query .= " l_project = ?";
       $queryc .= " l_project = ?";
       push @qparam, $project;
       push @qparamc, $project;
     } else { 
       print "Project '$project' is not in the database<br/>\n";
       return;
     }
   }
  
   if ( $oldrating =~ /\w|\d/) {
     # 'Assessed' is a magic word that means "not unassessed".
     if ( $oldrating eq 'Assessed-Class' ) { 
       $query .= " AND NOT l_old = 'Unassessed-Class'";
       $queryc .= " AND NOT l_old = 'Unassessed-Class'";
     } else { 
       $query .= " AND l_old = ?";
       $queryc .= " AND l_old = ?";
       push @qparam, $oldrating;
       push @qparamc, $oldrating;
     }
   }
  
   if ( $newrating =~ /\w|\d/) {
     # 'Assessed' is a magic word that means "not unassessed".
     if ( $newrating eq 'Assessed-Class' ) { 
       $query .= " AND NOT l_old = 'Unassessed-Class'";
       $queryc .= " AND NOT l_old = 'Unassessed-Class'";
     } else { 
       $query .= " AND l_old = ?";
       $queryc .= " AND l_old = ?";
       push @qparam, $newrating;
       push @qparamc, $newrating;
     }
   }

   if ( defined $pagename and $pagename =~ /\w|\d/ ) { 
     if ( $params->{'pagenameWC'} eq 'on' ) { 
       $query .= " AND l_article REGEXP ?";
       $queryc .= " AND l_article REGEXP ?";
       push @qparam, $pagename;
       push @qparamc, $pagename;
     } else { 
       $query .= " AND l_article = ?";
       $queryc .= " AND l_article = ?";
       push @qparam, $pagename;
       push @qparamc, $pagename;
     }
   }
  

   $query .= " ORDER BY l_revision_timestamp DESC, l_article ";

  
   $query .= " LIMIT ?";
   push @qparam, $limit;
  
   $query .= " OFFSET ?";
   push @qparam, $offset;
  
  
   # clean up the SQL for edge cases 
   $query =~ s/WHERE\s*AND/WHERE /;
   $queryc =~ s/WHERE\s*AND/WHERE /;
  
   $query =~ s/WHERE\s*ORDER/ORDER/;
   $queryc =~ s/WHERE\s*ORDER/ORDER/;
  
   $queryc =~ s/WHERE\s*$//;
  
  
   print "<pre>Q:\n$query</pre>\n";
   print join "<br/>", @qparam;

  my $sthcount = $dbh->prepare($queryc);
  $sthcount->execute(@qparamc);
  	
  my @row = $sthcount->fetchrow_array() ;
  my $total = $row[0];
  
  print "<div class=\"navbox\">\n";
  print_header_text($project);
  print "</div>\n";

  print "<p><b>Total results: " . $total 
        . "</b>.<br/> Displaying up to $limit results beginning with #" 
        . ($offset +1) . "</p>\n";


  my $sth = $dbh->prepare($query);
  my $c = $sth->execute(@qparam);
  my $i = $offset;

  print << "HERE";
  <center><table class="wikitable">
  <tr>
    <th><b>Result</b></th>
HERE

    if (  ! ( $project =~ /\w|\d/ ) ) { 
      print "    <th>Project</th>\n";
    }

print << "HERE";
    <th><b>Timestamp</b></th>
    <th><b>Article</b></th>
    <th><b>Revision</b></th>
    <th><b>Type</b></th>
    <th><b>New value</b></th>
    <th><b>Old value</b></th>
  </tr>
HERE


  while ( @row = $sth->fetchrow_array ) {
    $i++;

    print "<tr><td>$i</td>\n";

    if (  ! ( $project =~ /\w|\d/ ) ) { 
      print "    <td>" . $row[0] . "</td>\n";
    }

#    print "    <td>" . $row[3] . "</td>\n";
    print "    <td>" . make_article_link($row[1]) . "</td>\n";
    print "    <td>" . make_history_link($row[1],$row[6],"l") . "</td>\n";
    print "    <td>" . $row[2] . "</td>\n";
    print "    " . get_cached_td_background($row[5]) . "\n";
    print "    " . get_cached_td_background($row[4]) . "\n";

    print "</tr>\n";
  }
  print "</table>\n</center>\n";

	my $p;
	my $params_enc;
	foreach $p ( keys %$params ) { 
		next if ( $p eq 'offset' ) ;
		$params_enc .= "$p=" . uri_escape($params->{$p}) . "&";   
	}

	# For display purposes - whether we use a pipe between "previous" and "next"
	# depends on whether "previous" is defined or not 
	my $prev = 0;
	if (($offset - $limit + 1) > 0) {
		my $newURL = $ENV{"SCRIPT_URI"} . "?" . $params_enc
		. "offset=" . ($offset - $limit + 1);	  
		
		print "<a href=\"" . $newURL . "\">Previous $limit entries</a>";
		$prev = 1;
	}
	
	if ($limit + $offset < $total){ 
		if ($prev == 1) {
			print " | ";
		}
		my $newURL = $ENV{"SCRIPT_URI"} . "?" . $params_enc
		. "&offset=" . ($offset + $limit + 1);	  
		
		print "<a href=\"" . $newURL . "\">Next $limit entries</a>";
	}
	print "\n";	
	
}


###########################################################################

sub list_projects { 
  my @row;
  my $projects = {};

  my $sth = $dbh->prepare("SELECT p_project FROM projects");
  $sth->execute();

  while ( @row = $sth->fetchrow_array ) { 
    $projects->{$row[0]} = 1;
  }
  return $projects;
}

###########################################################################

sub query_form {
  my $params = shift;
  
  my $project = $params->{'project'} || '';
  my $oldrating = $params->{'oldrating'} || "";
  my $newrating = $params->{'newrating'} || "";

  my $limit = $params->{'limit'} || "1000";
  my $offset = $params->{'offset'} || "1";

  my $pagename = $params->{'pagename'} || "";
  my $pagenameWC = $params->{'pagenameWC'} || "";

  my $pagename_wc_checked = "";
  if ( $pagenameWC eq 'on' ) { 
    $pagename_wc_checked = "checked=\"yes\" ";
  }

  print << "HERE";
<form>

<table class="mainform">
<tr>
<td id="projecta" class="toprow"><b>First project</b><br/>
  <table class="subform">
    <tr><td>Project name</td>
      <td><input type="text" value="$project" name="project"/></td></tr>
    <tr><td>Page name</td>
      <td><input type="text" value="$pagename" name="pagename"/></td></tr>
    <tr><td>Old rating</td>
      <td><input type="text" value="$oldrating" name="oldrating"/></td></tr>
    <tr><td>New rating</td>
      <td><input type=\"text\" value="$newrating" name="newrating"/></td></tr>
    <tr><td colspan="2"><input type="checkbox" $pagename_wc_checked  
                               name="pagenameWC" />
      Treat page name as a 
      <a href="http://en.wikipedia.org/wiki/Regular_expression">regular expression</a></td></tr>
    <tr><td colspan="2" class="note">Note: leave any field blank to 
                       select all values.</td></tr>
  </table>
</td>
</tr>

<tr>
<td class="bottomrow"><b>Output options</b><br/>
<table class="subform">
  <tr><td>Results per page</td>
      <td><input type="text" value="$limit" name="limit"/></td></tr>
  <tr><td>Start with result #</td>
      <td><input type="text" value="$offset" name="offset"/></td></tr>
</table>
<div style="text-align: center;"><input type="submit" value="Generate list"/></div>
</td>
</tr>
</table>
</form>
HERE

}

###########################################################################

sub get_cached_td_background { 
  my $class = shift;

  if ( defined $cacheMem->{$class} ) { 
    print " <!-- hit $class in memory cache --> ";
    return $cacheMem->{$class};
  }

  my $key = "CLASS:" . $class;
  my $data;

  if ( $cacheFile->exists($key) ) { 
     print " <!-- hit $class in file cache, expires " 
           . strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($cacheFile->expiry($key)))
           . " --> ";
    $data = $cacheFile->get($key);
    $cacheMem->{$class} = $data;
    return $data;
  }

  $data = get_td_background($class);

  $cacheFile->set($key, $data, '12 hours');
  $cacheMem->{$class} = $data;
  return $data;
}

###########################################################################

sub get_td_background { 
  my $class = shift;
  my $r =  $api->parse('{{' . $class . '}}');
  my $t = $r->{'text'};

  $t =~ s/\|.*//s;
  $t =~ s!^<p>!!;
  # FIXME: use get_conf('class-suffix') instead;
  $class =~ s/-Class//;
  $t = "<td $t><b>$class</b></td>";

  return $t;
}

###########################################################################

sub get_link_from_api { 
  my $text = shift;
  my $r =  $api->parse($text);
  my $t = $r->{'text'};

  my $baseURL = get_conf('base_url');
  $t =~ s!^<p>!!;
  my @t = split('</p>',$t);
  $t = @t[0];

  @t = split('"',$t,2);
  $t = @t[0] . "\"" . $baseURL .  @t[1];

  return $t;
}

###########################################################################

sub print_header_text {
  my $project = shift;
  my ($timestamp, $wikipage, $parent, $shortname);
  my $tableURL = get_conf('table-url');
  my $listURL = get_conf('list2-url');

  # If the project is defined, show the project's navbar
  if ( $project =~ /\w|\d/ ) { 
    $tableURL = $tableURL . "project=" . $project;
    $listURL = $listURL . "projecta=" . $project . "&limit=50";

    ($project, $timestamp, $wikipage, $parent, $shortname) = 
      get_project_data($project);

    if ( ! defined $wikipage) {
      print "Data for <b>$project</b> "; 	
    } elsif ( ! defined $shortname) {
      print "Data for <b>" . get_link_from_api("[[$wikipage]]") . "</b> "; 
    } else {
      print "Data for <b>" . get_link_from_api("[[$wikipage|$shortname]]") . "</b> ";
    }
  } else { 
    print " Data for all projects ";
  }

  print "(<a href=\"" . $listURL . "\">list</a> \| <a href=\"" . $tableURL 
        . "\">summary table</a> | <b>assessment log</b>)\n";
}


###########################################################################

sub make_article_link {
  my $server_uri = "http://en.wikipedia.org/w/index.php";
  my $a = shift;
  return "<a href=\"$server_uri?title=" . uri_escape($a) . "\">$a</a>"
         . " (<a href=\"$server_uri?title=Talk:" . uri_escape($a) 
         . "\">t</a> &middot; "
         . "<a href=\"$server_uri?title=" . uri_escape($a) 
         . "&action=history\">h</a>)";
}

###########################################################################

sub make_history_link { 
  my $art = shift;
  my $ts = shift;
  my $long = shift || "";

  my $d = $ts;

  if ( $long eq 'l' ) { 
    $d =~ s/T/ /;
    $d =~ s/Z/ /;
  } else { 
    $d =~ s/T.*//;
  }

  my $dir = "http://toolserver.org/~cbm//cgi-bin/wp10.2g/alpha/cgi-bin/";
  return "<a href=\"$dir/loadVersion.pl?article=" . uri_escape($art) 
       . "&timestamp=" . uri_escape($ts) . "\">$d</a>&nbsp;";
}

###########################################################################
