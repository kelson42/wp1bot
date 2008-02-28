#!/usr/bin/perl
# 
# part of VeblenBot
# Carl Beckhorn, 2008
# Copyright: GPL 2.0

use strict;	
use diagnostics;	 

use lib '/home/veblen/VeblenBot';
require Mediawiki::Edit;

MAIN: {

  my $client = Mediawiki::Edit->new();
  $client->base_url('http://en.wikipedia.org/w');
  $client->login_from_file('/home/veblen/api.credentials');

  $client->debug_level(3);

  my $file;

  ## Very crude scan of command line arguments, 
  ## All we care about is whether one of them is '-a'
  my $edit_summary = "manual update";  
  foreach $_ ( @ARGV) { 
    if ( $_ eq '-a') { 
      $edit_summary = "automatic update";
    }
  }

  my @Fields;

  my $line;
  my $ns;
  my $cat;

  open IN, "<CategoryList";

  while ($line = <IN>) {
    chomp $line;
    ($ns,$cat) = split /\t/,$line,2;
    push @Fields, $cat;
  }

  close IN;

  @Fields = sort {$a cmp $b} @Fields;  

  my $field;
  my $location = "/home/veblen/VeblenBot/categories/Data";
  my $remote  = "User:VeblenBot/C";

  my $text;

  foreach $field (@Fields) {
    $text = "";

    my $catesc = $field;
    $catesc =~ s/\//|/g;

    open IN, "<$location/$catesc" 
        or die "Can't open $field from $location: $!\n";

    # Check first line for magic word, to confirm all is well    
    $text = <IN>;
    if ( ! ($text =~ /Success/)) {
      print "Error with $field: $text\n";
      next;
    }
 
    # Read the rest of the file
    $text = '';
    while ( $_ = <IN> ) {
      $text .= $_;
    }

    $file = "$remote/$field";

    print "\nUpload $file\n";
    $client->edit($file, $text, $edit_summary);
  }
}

## End
