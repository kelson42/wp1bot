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
<script type="text/javascript"   
  src="$usableforms";</script>
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
</div>

<div class="content">
HERE

}

#######################################################################

sub layout_footer {
print << "HERE";
</div>
<div class="footer">
Please comment or file bug reports at the 
<a href="http://en.wikipedia.org/wiki/User_talk:WP_1.0_bot/Second_generation">discussion page </a>.
</body>
</html>
HERE

}

#######################################################################
1;
