#!/usr/bin/perl

# layout.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for additional information

use strict;

our $Opts;
my $App = $Opts->{'appname'}
    or die "Must specify application name\n";

my $Version = $Opts->{'version'}
    or die "Must specify version\n";

my $indexURL = $Opts->{'index-url'};
my $table2URL = $Opts->{'table2-url'};
my $tableURL = $Opts->{'table-url'};
my $logURL = $Opts->{'log-url'};
my $listURL = $Opts->{'list2-url'};
my $manualURL = $Opts->{'manual-url'};
my $versionURL = $Opts->{'version-url'};
my $serverURL = $Opts->{'server-url'};

my $namespaceIDs;

use DBI;
require "database_www.pl";
our $dbh = db_connect_rw($Opts);
require 'cache.pl';

my $cacheMem = {};

require Mediawiki::API;
my $api = new Mediawiki::API;
$api->debug_level(0); # no output at all 
$api->base_url('http://en.wikipedia.org/w/api.php');


##################################################


sub layout_header {
  my $title = shift;
  my $subhead = shift || '&nbsp;';
  my $longtitle = shift;

  my $realtitle = $title;
  if ( defined $longtitle) { $realtitle = $longtitle; }

  my $stylesheet = $Opts->{'wp10.css'}
    or die "Must specify configuration value for 'wp10.css'\n";

  my $usableforms = $Opts->{'usableforms.js'}
    or die "Must specify configuration value for 'usableforms.js'\n";
  
  print << "HERE";
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" 
          "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr">
<head>
  <base href="http://en.wikipedia.org">
  <title>$title - $App</title>
  <style type="text/css" media="screen">
     \@import "$stylesheet";
  </style>
<script type="text/javascript"  src="$usableforms"></script>
<script type="text/javascript"  src="http://toolserver.org/~cbm/foo.js"></script>
</head>
<body>

<div id="container">
  <div id="head">
    <a href="http://toolserver.org">
      <img id="poweredbyicon" alt="Powered by Wikimedia Toolserver"
         src="http://toolserver.org/images/wikimedia-toolserver-button.png"/>
    </a>
  <h1>$App</h1>
  </div>

  <div id="subhead">
  $subhead
  </div>

</div>
HERE

  layout_leftnav($title);

  print << "HERE";
</div>
<div id="content">
<h2>$realtitle</h2>
HERE

}

#######################################################################

sub layout_leftnav { 
  my $title = shift;

  my @AssessmentData = (
     "Project index" =>          $indexURL,
     "Overall summary table" =>  $table2URL,
     "Project summary tables" => $tableURL,
     "Article lists" =>          $listURL,
     "Assessment logs" =>        $logURL
    );


  my @ManualSelection = (
     "List manual selection" => $manualURL . "mode=list",
     "Add articles" =>          $manualURL . "mode=add",
     "Changelog" =>             $manualURL . "mode=logs",
     "Log in" =>                $manualURL . "mode=login"
    );

  print << "HERE";
<div id="leftnav">
<h5 class="menu1 menu1start">Assessment data</h5>
HERE

  nav_list($title, \@AssessmentData);


  print << "HERE";
<h5 class="menu1 later">Manual selection</h5>
HERE

  nav_list($title, \@ManualSelection);


}
#######################################################################


sub nav_list { 
  my $title = shift;
  my $items = shift;

  print "<ul>\n";

  my ($i, $j, $selected);
  $i = 0;
  while ( $i < scalar @{$items} ) { 
    $j = $i + 1;
    $selected = "";
    if ( $title eq $items->[$i] ) { 
      $selected = "selected";
    }

    print "<li class=\"$selected\">" 
          . "<a href=\"" . $items->[$j] . "\">"
         . $items->[$i] . "</a></li>\n";

    $i += 2;
  }

  print "</ul>\n";

}

#######################################################################

sub layout_footer {

my $version = $Opts->{'version'};

my $discussionPage = $Opts->{'discussion-page'} 
   || die "Must specify discussion-page in configuration file\n";

print << "HERE";
</div>
<div id="footerbar">&nbsp;</div>

<div id="footer">
This is an <b>alpha</b> version of the second generation WP 1.0 
bot.<br/>
Please comment or file bug reports at the 
<a href="$discussionPage">discussion page</a>.
<br/>
<div class="version">
Current version: $Version
</div>
HERE

# system "ssh", "login.toolserver.org", "/home/cbm/wp10.2g/alpha/revinfo.pl";

print << "HERE";
</div>
</body>
</html>
HERE

}

#######################################################################
# Generates colors for the progress bar. The two endpoints are
# 0%: #D10000 = (209, 0, 0) and 100%: 33CC00 = (51, 204, 0).
# There's probably a more efficient way of doing this...
sub get_bar_color {  
	my $percent = shift; 
	my $color;
	
	if ($percent >= 0) { $color='D10000' }
	if ($percent >= 2.5) { $color='F10000' }
	if ($percent >= 7.5) { $color='FF1600' }
	if ($percent >= 12.5) { $color='FF3700' }
	if ($percent >= 17.5) { $color='FF6500' }
	if ($percent >= 22.5) { $color='FF8F00' }
	if ($percent >= 27.5) { $color='FFB900' }
	if ($percent >= 32.5) { $color='FFD800' }
	if ($percent >= 37.5) { $color='FFE500' }
	if ($percent >= 42.5) { $color='FFF600' }
	if ($percent >= 47.5) { $color='FCFF00' }
	if ($percent >= 52.5) { $color='D3FF00' }
	if ($percent >= 57.5) { $color='D3FF00' }
	if ($percent >= 62.5) { $color='BEFF00' }
	if ($percent >= 67.5) { $color='92FF00' }
	if ($percent >= 72.5) { $color='99FF00' }
	if ($percent >= 77.5) { $color='39FF00' }
	if ($percent >= 82.5) { $color='0BFF00' }
	if ($percent >= 87.5) { $color='16E900' }
	if ($percent >= 92.5) { $color='33CC00' }
	if ($percent >= 97.5) { $color='33CC00' }
	if ($percent > 100) { $color='000000' }
	return $color;
}

#######################################################################
# Rounding function 
sub round {
	my $n = shift;
    return int($n + .5);
}

#######################################################################

sub make_table_link {
  my $project = shift;
  return $tableURL . "project=" . uri_escape($project);
}

#######################################################################

sub make_list_link { 
  my $opts = shift;
  my @encoded;

  my $key;
  foreach $key ( sort keys %$opts ) { 
    push @encoded, $key . "=" . uri_escape($opts->{$key});
  }
  
  return $listURL . (join "&", @encoded);
}

#######################################################################

sub make_log_link { 
  my $opts = shift;
  my @encoded;

  my $key;
  foreach $key ( sort keys %$opts ) { 
    push @encoded, $key . "=" . uri_escape($opts->{$key});
  }
  
  return $logURL . (join "&", @encoded);
}

#######################################################################

sub make_article_link {

  my $ns = shift;
  my $a = shift;
  my $pagename = make_page_name($ns, $a);
  my $talkname = make_talk_name($ns, $a);

  my $loguri = $logURL;

  return "<a href=\"$serverURL?title=" . uri_escape($pagename)
       . "\">$pagename</a>"
         . " (<a href=\"$serverURL?title=" . uri_escape($talkname)
         . "\">t</a>"
         . " &middot; "
         . "<a href=\"$serverURL?title=" . uri_escape($pagename)
         . "&action=history\">h</a>"
         . " &middot; "
         . "<a href=\"$logURL?pagename=" . uri_escape($a)
         . "&ns=" . uri_escape($ns)
         . "\">l</a>)";
}


###########################################################################

sub make_history_link {
  my $ns = shift;
  my $title = shift;
  my $ts = shift;
  my $long = shift || "";

  my $d = $ts;

  my $art = make_page_name($ns, $title);

  if ( $long eq 'l' ) {
    $d =~ s/T/ /;
    $d =~ s/Z/ /;
  } else {
    $d =~ s/T.*//;
  }

  return "<a href=\"" . $versionURL . "article=" . uri_escape($art)
       . "&timestamp=" . uri_escape($ts) . "\">$d</a>&nbsp;";
}

###########################################################################

sub make_page_name {
  my $ns = shift;
  my $title = shift;

  if ( ! defined $namespaceIDs ) {
      $namespaceIDs = init_namespaces();
  }

  if ( $ns == 0 ) {
    return $title;
  } else {
    return $namespaceIDs->{$ns} . $title;
  }
}

sub make_talk_name {
  my $ns = shift;
  my $title = shift;

  if ( 1 == $ns % 2) {
    return $title;
  } else {
    return make_page_name($ns+1, $title);
  }

}

###########################################################################

sub init_namespaces {

  my $namespaces = db_get_namespaces();
  my $n;
  foreach $n ( keys %$namespaces ) {
    if ( $n ne '0') { $namespaces->{$n} .= ":";}
  }

  return $namespaces;
}

###########################################################################

sub get_link_from_api {
  my $text = shift;

  my $r =  $api->parse($text);
  my $t = $r->{'text'}->{'content'};

  # TODO: internationalize this bare URL
  $t =~ s!^<p>!!;
  my @t = split('</p>',$t);
  $t = @t[0];

  @t = split('"',$t,2);
  $t = @t[0] . "\"" . $serverURL .  @t[1];

  return $t;
}

###########################################################################

sub list_projects { 
  my $dbh = shift;
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

sub get_cached_td_background { 
  my $class = shift;

  if ( defined $cacheMem->{$class} ) { 
    print "<!-- hit $class in memory cache -->\n";
    return $cacheMem->{$class};
  }

  my $key = "CLASS:" . $class;
  my ($data, $expiry);

  if ( $expiry = cache_exists($key) ) { 
     print "<!-- hit $class in file cache, expires " 
           . strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($expiry))
           . " -->\n";
    $data = cache_get($key);
    $cacheMem->{$class} = $data;
    return $data;
  }

  $data = get_td_background($class);

  cache_set($key, $data, 12*60*60); # expires in 12 hours
  $cacheMem->{$class} = $data;
  return $data;
}

###########################################################################

sub get_td_background { 
  my $class = shift;
  my $r =  $api->parse('{{' . $class . '}}');
  my $t = $r->{'text'}->{'content'};

  $t =~ s/\|.*//s;
  $t =~ s!^<p>!!;
  $class =~ s/-Class//;
  $t = "<td $t><b>$class</b></td>";

  # XXX hack
  $t =~ s/Bplus/B+/;

  return $t;
}

###########################################################################

sub get_cached_review_icon { 
	my $class = shift;
	
	if ( defined $cacheMem->{$class . "-icon"} ) { 
		print "<!-- hit {$class}-icon in memory cache -->\n";
		return $cacheMem->{$class . "-icon"};
	}
	
	my $key = "CLASS:" . $class . "-icon";
	my ($expiry, $data);
	
	if ( $expiry = cache_exists($key) ) { 
		print "<!-- hit {$class}-icon in file cache, expires " 
		. strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($expiry))
		. " -->\n";
		$data = cache_get($key);
		$cacheMem->{$class} = $data;
		return $data;
	}
	
	$data = get_review_icon($class);
	
	cache_set($key, $data, '12 hours');
	$cacheMem->{$class . "-icon"} = $data;
	return $data;
}

###########################################################################

sub get_review_icon { 
	my $class = shift;
	my $r =  $api->parse('{{' . $class . '-Class}}');
	my $t = $r->{'text'}->{'content'};
	my $f =  $api->parse('{{' . $class . '-classicon}}');
	my $g = $f->{'text'}->{'content'};
	
	$t =~ s/\|.*//s;
	$t =~ s!^<p>!!;
	$g =~ s/<\/p.*//;
	$g =~ s!^<p>!!;
	# Perl doesn't want to get rid of the rest of the lines in the 
	# multi-line string, so remove them the hard way
	my @str = split(/\n/,$g);
	$g = @str[0];
	undef(@str);
	$class =~ s/-Class//;
	$t = "<td $t><b>$g&nbsp;$class</b></td>";
	
	return $t;
}

###########################################################################

sub make_wp05_link { 
  my $cat = shift;
  my $linka = "http://en.wikipedia.org/wiki/Wikipedia:Wikipedia_0.5";
  my $linkb = "http://en.wikipedia.org/wiki/Wikipedia:Version_0.5";
  my $abbrev = {  'Arts' => 'A',
		  'Engineering, applied sciences, and technology' => 'ET',
		  'Everyday life' => 'EL',
		  'Geography' => 'G',
		  'History' => 'H',
		  'Language and literature' => 'LL',
		  'Mathematics' => 'Ma',
		  'Natural sciences' => 'NS',
		  'Philosophy and religion' => 'PR',
		  'Social sciences and society' => 'SS',
		  'Uncategorized'  => 'U'};

  return "<a href=\"$linka\">0.5</a> ";
}

###########################################################################

sub make_review_link { 
  my $type = shift;
  return get_cached_td_background($type . "-Class") ;
}

###########################################################################

sub fix_timestamp { 
  my $t = shift;

  return substr($t, 0, 4) . "-" . substr($t, 4, 2) . "-"
           . substr($t, 6, 2) . "T" . substr($t, 8, 2) 
           . ":" . substr($t, 10, 2) . ":" . substr($t, 12, 2)  . "Z";
}


1;
