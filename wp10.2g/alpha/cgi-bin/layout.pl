#!/usr/bin/perl

use strict;

my $App = "Wikipedia Release Version Data";

our $Opts;

my $indexURL = $Opts->{'index-url'};
my $table2URL = $Opts->{'table2-url'};
my $tableURL = $Opts->{'table-url'};
my $logURL = $Opts->{'log-url'};
my $listURL = $Opts->{'list2-url'};
my $versionURL = $Opts->{'version-url'};
my $serverURL = $Opts->{'server-url'};

my $namespaceIDs;

##################################################

sub layout_header {
  my $subtitle = shift;

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
  <title>$subtitle - $App</title>
  <style type="text/css" media="screen">
     \@import "$stylesheet";
  </style>
<script type="text/javascript"  src="$usableforms"></script>
<script type="text/javascript"  src="http://toolserver.org/~cbm/foo.js"></script>
</head>
<body>
<div class="head">
<a href="http://$ENV{'SERVER_NAME'}/">
<img id="poweredbyicon" alt="Powered by Wikimedia Toolserver" src="http://$ENV{'SERVER_NAME'}/~titoxd/images/wikimedia-toolserver-button.png"/>
</a>	
$App
</div>
<div class="subhead">
HERE


print "<!-- '$subtitle' -->\n";


if ( $subtitle eq "Project index" ) { 
  print "<span class=\"selectedtool\"><a href=\"$indexURL\">" 
      . "Project index</a></span> &middot; \n";
} else {
  print "<a href=\"$indexURL\">Project index</a> &middot; \n";
}

if ( $subtitle eq "Overall summary table" ) { 
  print "<span class=\"selectedtool\"><a href=\"$table2URL\">" 
      . "Overall summary table</a></span> &middot; \n";
} else {
  print "<a href=\"$table2URL\">Overall summary table</a> &middot; \n";
}

if ( $subtitle eq "Summary tables" ) { 
  print "<span class=\"selectedtool\"><a href=\"$tableURL\">" 
      . "Project summary tables</a></span> &middot; \n";
} else {
  print "<a href=\"$tableURL\">Project summary tables</a> &middot; \n";
}

if ( $subtitle eq "Article lists" ) { 
  print "<span class=\"selectedtool\"><a href=\"$listURL\">" 
      . "Article lists</a></span> &middot; \n";
} else {
  print "<a href=\"$listURL\">Article lists</a> &middot; \n";
}

if ( $subtitle eq "Assessment logs" ) { 
  print "<span class=\"selectedtool\"><a href=\"$logURL\">" 
      . "Assessment logs</a></span> \n";
} else {
  print "<a href=\"$logURL\">Assessment logs</a> \n";
}

print << "HERE";
</div>

<div class="content">
HERE

}

#######################################################################

sub layout_footer {
my $discussionPage = $Opts->{'discussion-page'} 
   || die "Must specify discussion-page in configuration file\n";

print << "HERE";
</div>
<div class="footer">
This is an <b>alpha</b> version of the second generation WP 1.0 
bot.<br/>
Please comment or file bug reports at the 
<a href="$discussionPage">discussion page</a>.
<hr/>
Current version:<br/>
HERE

system "ssh", "login.toolserver.org", "/home/cbm/wp10.2g/alpha/revinfo.pl";

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


1;
