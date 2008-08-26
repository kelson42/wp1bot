#!/usr/bin/perl

use strict;
use Encode;
use URI::Escape;
use Data::Dumper;

require CGI;
require CGI::Carp; 
CGI::Carp->import('fatalsToBrowser');

require 'read_conf.pl';
our $Opts = read_conf();

require Mediawiki::API;
my $api = new Mediawiki::API;
$api->debug_level(0); # no output at all 
$api->base_url(get_conf('api_url'));

my $cgi = new CGI;
my %param = %{$cgi->Vars()};

my $rev = get_revision($api, $param{'article'},$param{'timestamp'});

if ( ! defined $rev ) { 
 print CGI::header(-type=>'text/plain', -charset=>'utf-8');  
 print "Error: could not get revision id.\n";
 print "A: '" . $param{'article'} . "'\n";
 print "T: '" . $param{'timestamp'} . "'\n";
 exit;
}

my $url = get_conf('server_url') . "?title="
. uri_escape($param{'article'}) . "&oldid="
. $rev->{'revid'} . "\n";


print << "HERE";
Location: $url

HERE
exit;

sub get_revision { 
  my $api = shift;
  my $article = shift;
  my $timestamp = shift;
  
  my $where = [ 'query',  'pages', 'page', 'revisions', 'rev'];

  my $rev = $api->makeXMLrequest([ 
      'action'  => 'query',
      'prop'    => 'revisions',
      'titles'  => encode("utf8", $article), # encoded
      'rvprop'  => 'ids|flags|timestamp|user|size|comment',
      'rvstart' => $timestamp,
      'rvlimit' => '1',
      'format'  => 'xml' ]);

  $rev = $api->child_data_if_defined($rev, $where);

  return $rev;
}




