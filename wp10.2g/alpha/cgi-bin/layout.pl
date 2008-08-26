#!/usr/bin/perl

my $App = "Wikipedia Release Version Data";

our $Opts;

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
$subtitle
</div><div class="linkback">
<a href="$indexURL">Return to the project index ↵</a>
</div>

<div class="content">
HERE

}

#######################################################################

sub layout_footer {
	my $indexURL = get_conf('index_url');
print << "HERE";
</div>
<div class="footer">
Please comment or file bug reports at the 
<a 
href="http://en.wikipedia.org/wiki/User_talk:WP_1.0_bot/Second_generation">discussion page </a>.<br/>
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

1;
