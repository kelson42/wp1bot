#!/usr/bin/perl

our $Opts;

require Mediawiki::API;
require "toolserver_api.pl";

my $api;

my $use_toolserver = 1;

#####################################################################

sub init_api() { 
  return if ( defined $api );

  $api = new Mediawiki::API;  # global object 
  $api->maxlag(-1);
  $api->max_retries(20);

  $api->base_url('http://en.wikipedia.org/w/api.php');
  $api->debug_level(3);

  if ( defined $Opts->{'api-credentials'} ) { 
    $api->login_from_file($Opts->{'api-credentials'});
  }
}


#####################################################################

sub pages_in_category {
  my $cat = shift;
  my $ns = shift;

  print "Get: $cat\n";

  if ( $use_toolserver ) { 
    $cat =~ s/^Category://;
    $cat =~ s/ /_/g;
    print "Get: $cat\n";

    my $r =  toolserver_pages_in_category($cat, $ns);
    print "See: " . scalar @$r . "\n";

    print Dumper($r);
    

    return $r;
  } 

  init_api();

  return $api->pages_in_category($cat, $ns);
}

#####################################################################

sub pages_in_category_detailed {
  my $cat = shift;
  my $ns = shift;

  if ( $use_toolserver ) { 
    $cat =~ s/^Category://;
    $cat =~ s/ /_/g;
    print "Get: $cat\n";
    return toolserver_pages_in_category_detailed($cat, $ns);
  } 

  init_api();

  return $api->pages_in_category_detailed($cat, $ns);
}

#####################################################################

sub content_section {
  my $art = shift;
  my $sect = shift;

  init_api();

  return $api->content_section($art, $sect);
}

#####################################################################

#Load successfuly
1;
