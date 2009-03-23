#!/usr/bin/perl

# UploadFieldTables.pl
# part of VeblenBot
# Carl Beckhorn, 2008
# Copyright: GPL 2.0

use strict;		      # 'strict' insists that all variables be declared
use diagnostics;	      # 'diagnostics' expands the cryptic warnings

# make sure you write below the correct path to the wikipedia_perl_bot directory

use lib '/home/veblen/VeblenBot';

use Mediawiki::API;

# undefines the line separator. Can read one whole file in one scalar.
#undef $/;                     

MAIN: {

  #log in (make sure you specify a login and password in bin/wikipedia_login.pl
  
  my $client = Mediawiki::API->new();
  
#  $client->{'name'} = 'Editor 1';

  $client->base_url('http://en.wikipedia.org/w/api.php');
  $client->maxlag(`/home/veblen/maxlag.sh`);

  $client->login_from_file("/home/veblen/api.credentials");

  # Count requests

  my $count = `/usr/bin/wc -l /home/veblen/VeblenBot/per/Cache.new`;
  chop $count;
  $count =~ s/ .*//;

  my $request = "requests";
  if ( $count == 1) { $request = "request"; }

  # a file to edit. Note that each Wikipedia page has to have a ".wiki" 
  # appended to it.
  my $file;

  # fetch the wikicode of $file
  my $text;

  my $edit_summary = "manual update ($count $request)";  
  foreach $_ ( @ARGV) { 
    if ( $_ eq '-a') { 
      $edit_summary = "automatic update ($count $request)";
    }
  }

  
  $file = "PERtable.new";
  $text = "";
  open IN, "<$file" 
         or die "Can't open $file: $!\n";

   while ( <IN> ) {
     $text .= $_;
   }

#  print $edit_summary . "\n";
  $client->edit_page("User:VeblenBot/PERtable", $text, $edit_summary);
}
