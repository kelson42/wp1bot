#!/usr/bin/perl

my $App = "Wikipedia Release Version";

sub layout_header {
  my $subtitle = shift;

print << "HERE";
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" 
"http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr">
<head>
  <base href="http://en.wikipedia.org">
  <style type="text/css" media="screen">
     \@import "http://localhost/~veblen/wp10.css";
  </style>
<script type="text/javascript"   
  src="http://localhost/~veblen/usableforms.js";</script>
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



