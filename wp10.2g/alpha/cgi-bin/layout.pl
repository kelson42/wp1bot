#!/usr/bin/perl

my $App = "Wikipedia Release Version";

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
  <style type="text/css" media="screen">
     \@import "$stylesheet";
  </style>
<script type="text/javascript"   
  src="$usableforms";</script>
</head>
<body>
<div class="head">
$App
</div>
<div class="subhead">
$subtitle
</div>
<div class="content">
HERE

}



sub layout_footer {
print << "HERE";
</div>
</body>
</html>
HERE

}



