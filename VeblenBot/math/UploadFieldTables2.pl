#!/usr/bin/perl

# UploadFieldTables.pl
# part of VeblenBot
# Carl Beckhorn, 2008
# Copyright: GPL 2.0


use strict;		      # 'strict' insists that all variables be declared
use diagnostics;	      # 'diagnostics' expands the cryptic warnings

# make sure you write below the correct path to the wikipedia_perl_bot directory

use lib '/home/veblen/VeblenBot';

use Mediawiki::Edit;

# undefines the line separator. Can read one whole file in one scalar.
undef $/;                     

MAIN: {

  #log in (make sure you specify a login and password in bin/wikipedia_login.pl
  
  my $client = Mediawiki::Edit->new();

  $client->base_url('http://en.wikipedia.org/w');
  $client->maxlag(20);

  $client->login_from_file("/home/veblen/api.credentials");


  # a file to edit. Note that each Wikipedia page has to have a ".wiki" 
  # appended to it.
  my $file;

  # fetch the wikicode of $file
  my $text;

  my $edit_summary = "manual update";  
  foreach $_ ( @ARGV) { 
    if ( $_ eq '-a') { 
      $edit_summary = "automatic update";
    }
  }

  my $files = `ls output/`;
  my @Fields = split /\n/, $files;
  my $count = scalar @Fields;
  my $i = 0;

# @Fields = ( 'table:FIELDS.QUALITY', 'table:FIELDS.PRIORITY'  );

  @Fields = sort {$a cmp $b} @Fields;  

  my $field;
  my $location = "/home/veblen/VeblenBot/math/output";
  my $remote  = "User:VeblenBot/Math";

  foreach $field (@Fields) {

     $text = "";
     $i++; 
     open IN, "<$location/$field" 
              or die "Can't open $field from $location: $!\n";

     while ( <IN> ) {
       $text .= $_;
     }

     $file = "$remote/$field";
     print "$i / $count : $file\n";

     $client->edit($file, $text, $edit_summary);
  }
}
