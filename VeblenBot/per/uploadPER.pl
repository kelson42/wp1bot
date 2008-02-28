#!/usr/bin/perl
# 
# part of VeblenBot
# Carl Beckhorn, 2008
# Copyright: GPL 2.0

use strict;		      # 'strict' insists that all variables be declared
use diagnostics;	      # 'diagnostics' expands the cryptic warnings

# make sure you write below the correct path to the wikipedia_perl_bot directory
use lib '/home/veblen/VeblenBot/wikipedia_perl_bot';

require 'bin/wikipedia_fetch_submit.pl';
require 'bin/wikipedia_login.pl';
require 'bin/fetch_articles_cats.pl';
require 'bin/html_encode_decode.pl';
require 'bin/get_html.pl';

# undefines the line separator. Can read one whole file in one scalar.
undef $/;                     

MAIN: {

  #log in (make sure you specify a login and password in bin/wikipedia_login.pl
  &wikipedia_login();

  # how long to sleep between fetch/submit operations on Wikipedia pages
  my $sleep = 10;   

  # how many attempts one should take to fetch/submit Wikipedia pages
  my $attempts=5; 
  
  # a file to edit. Note that each Wikipedia page has to have a ".wiki" 
  # appended to it.
  my $file;

  # fetch the wikicode of $file
  my $text;

  $text = `/usr/bin/wc -l Cache`;
  $text =~ s/ Cache\n//;
 
  my $edit_summary = "manual update ($text requests)";  
  foreach $_ ( @ARGV) { 
    if ( $_ eq '-a') { 
      $edit_summary = "automatic update ($text requests)";
    }
  }

  my @Fields = ('PERtable');

  @Fields = sort {$a cmp $b} @Fields;  

  my $field;
  my $location = "/home/veblen/VeblenBot/per";
  my $remote  = "User:VeblenBot";

  foreach $field (@Fields) {
     $text = "";
 
     open IN, "<$location/$field" 
              or die "Can't open $field from $location: $!\n";

     while ( <IN> ) {
       $text .= $_;
     }

     $file = "$remote/$field.wiki";
     &wikipedia_submit($file, $edit_summary, $text, $attempts, $sleep);
  }
}

