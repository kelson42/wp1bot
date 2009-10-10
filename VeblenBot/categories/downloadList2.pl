#!/usr/bin/perl

## Download lists of category contents
## using the Mediawiki API
## Carl Beckhorn, 2008.  
## Copyright GPL 2.0

use strict;
use Data::Dumper;
use CGI::Util;

binmode STDOUT, ":utf8";

use lib '/home/veblen/VeblenBot';

use Mediawiki::API;
my $api;
$api = new Mediawiki::API;
$api->base_url('http://en.wikipedia.org/w/api.php');
$api->debug_level(3);
$api->maxlag(`/home/veblen/maxlag.sh`);

$api->login_from_file("/home/veblen/api.credentials");

$api->cmsort('timestamp');

###### Some categories are listed in reverse order

my %Reverse;
my $line;	

open IN, "<ReverseList";
while ( $line = <IN> ) { 
 chomp $line;
 print "Read '$line'\n";
 $Reverse{$line} = 1;
}

close IN;

######### Main routine 
######### Read list of categories to fetch and do it

my $file;
my $cat;
my $ns;

my $namespaces = $api->site_info()->{'namespaces'}->{'ns'};

foreach $file ( 'CategoryList', 'CategoryListTS' ) { 
  open IN, "<", $file;
  binmode IN, ":utf8";

  while ( $line = <IN> ) {
    chomp $line;
    ($ns, $cat) = split /\t/, $line, 2;
    download_cat_list($api, $namespaces, $cat, $ns);
  }

  close IN;
}

#######################################################
### Download a particular category's contents

sub download_cat_list {
  my $api = shift;
  my $namespaces = shift;
  my $cat = shift;
  my $ns = shift;
  my $re;
  my $line;

  my $catesc = $cat;  # escape slashes in file name
  $catesc =~ s/\//|/g;

  my $param = "CF/$cat";  # Template name on the wiki

  print "\nFetch '$cat' $ns\n";
  my $pages = $api->pages_in_category_detailed($cat, $ns);
  print "... " . scalar @$pages . " pages\n";

  if ( defined $Reverse{$cat} ) {
     print "... reverse order\n";
     $pages = [ reverse @$pages ];
  }
  
  my $title;
  my $timestamp;

  open OUT, ">Data/$catesc";   
  binmode OUT, ":utf8";
  print OUT "Success\n";  # First line is a magic word 
                          # So that empty files are not
                          # confused with empty categories

  foreach $line ( @$pages) { 
    $ns = $line->{'ns'};
    $title = $line->{'title'};
    $re = $namespaces->{$ns}->{'content'};
    $timestamp = $line->{'timestamp'};
    $title =~ s/^\Q$re\E://;  
    print OUT "{{" . $param . "|" . $title . "|" . $ns . "|" . 
                     $timestamp . "|extra={{{extra|}}}}}\n";
  }  
  close OUT;
  
}

## End
