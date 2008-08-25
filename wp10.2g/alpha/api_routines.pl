#!/usr/bin/perl
use strict;
use Encode;


=head1 SYNOPSIS

Routines for fetching content from the wiki. This library
is a wrapper that abstracts Mediawiki::API and toolserver_api.pl
into a common interface and output format. 

=over

=cut

use lib '/home/cbm/veblen/VeblenBot';

use Data::Dumper;

our $Opts;

require Mediawiki::API;
require "toolserver_api.pl";

my $api;
my $namespaces;

my $use_toolserver = 1;

#####################################################################

=item B<init_api>()

Initialize an internal Mediawiki::API object.

=cut

sub init_api() { 
  return if ( defined $api );

  $api = new Mediawiki::API;  # global object 
  $api->maxlag(-1);
  $api->max_retries(20);

  $api->base_url(get_conf('api_url'));
  $api->debug_level(3);

  if ( defined $Opts->{'api-credentials'} ) { 
#    $api->login_from_file($Opts->{'api-credentials'});
  }

  # Initialize hash of namespace prefixes
  my $r = $api->site_info();
  $r = $r->{'namespaces'}->{'ns'};

  $namespaces ={};
  my $n;
  foreach $n ( keys %$r ) { 
    if ( $r->{$n}->{'content'} ne "" ) { 
      $namespaces->{$n}= $r->{$n}->{'content'} . ":";
    } else { 
      $namespaces->{$n}= $r->{$n}->{'content'} . "";
    }
  }
}

#####################################################################

=item B<pages_in_category>(CATEGORY, [NS])

Returns an array reference listing pages in CATEGORY

CATEGORY _must_ be UTF-8 encoded

The NS parmater, optional, is a numeric namespace for 
filtering the results.

The pages in the rsulting array _do_ have the namespace
prefix attached (for example C<Talk:Foo> and C<Wikipedia:Bar>)

The titles returned are UTF-8 encoded

=cut

sub pages_in_category {
  my $cat = shift;
  my $ns = shift;

  print "Get: $cat\n";

  if ( $use_toolserver ) { 
    $cat =~ s/^Category://;
    $cat =~ s/ /_/g;
    my $r =  toolserver_pages_in_category($cat, $ns);
    return $r;
  }

  init_api();

  my $r = $api->pages_in_category($cat, $ns);
  my @encoded = map { encode("utf8", $_) } @$r;
  return \@encoded;
}

#####################################################################

=item B<pages_in_category_detailed>(CATEGORY, [NS])

Returns a reference to an array of hashes, 
one for each page in CATEGORY.

The output format is

  {  'ns'        => NAMESPACE, 
     'title'     => TITLE,
     'pageid'    => PAGEID,
     'sortkey'   => SORTKEY,
     'timestamp' => TIMESTAMP }

CATEGORY _must_ be UTF-8 encoded. 

The NS parmater, optional, is a numeric namespace for 
filtering the results.

The page titles in the resulting array _do_not_ have the namespace
prefix attached (for example, the page C<Talk:Foo> will show

  { 'ns' => '1',
    'title' => 'Foo',
     ...  }

The data returned is all UTF-8 encoded.

=cut

sub pages_in_category_detailed {
  my $cat = shift;
  my $ns = shift;

  print "Get: $cat '$ns'\n";

  if ( $use_toolserver ) { 
    $cat =~ s/^Category://;
    $cat =~ s/ /_/g;
    my $r = toolserver_pages_in_category_detailed($cat, $ns);
    return $r;
  }

  init_api();

  my $results = $api->pages_in_category_detailed($cat, $ns);

  my $r;

  foreach $r ( @$results ) { 
    $r->{'title'} =~ s/^\Q$namespaces->{$r->{'ns'}}\E//;
    $r->{'title'} = encode("utf8", $r->{'title'});
    $r->{'sortkey'} = encode("utf8", $r->{'sortkey'});
  }

  return $results;

}

#####################################################################

=item B<content_section>(PAGE, SECTION) 

Fetch the source code of section number SECTION in PAGE. The lede is
section 0.

The returned text is UTF-8 encoded.

=cut

sub content_section {
  my $art = shift;
  my $sect = shift;

  init_api();

  return encode("utf8", $api->content_section($art, $sect));

}

#####################################################################

=item B<api_namespaces>() 

Fetch a hash reference mapping namespace number to namespace prefix.

=cut

sub api_namespaces {
    init_api(); 
 
    return $namespaces;
}

#####################################################################
=item B<api_resolve_redirect>(NS, TITLE) 

Find the redirect target for NS:TITLE.

Return undef if NS:TITLE is not a redirect, otherwise return
(DEST_NS, DEST_TITLE)

=cut

sub api_resolve_redirect {
  my $ns = shift;
  my $title = shift;

  if ($use_toolserver == 1) { 
    return toolserver_resolve_redirect($ns, $title);
  }

  init_api();

  $title = $namespaces->{$ns} . $title;  

  print "T '$title'\n";

  my $data = $api->makeXMLrequest(['action'=>'query',
                                    'titles'=>$title,
                                    'redirects'=>'1',
                                    'format'=>'xml']);

  my $c = $data->{'query'}->{'redirects'}->{'r'}->{'to'};

  if ( defined $c) { 
    my $ns = $data->{'query'}->{'pages'}->{'page'}->{'ns'};
    my $title = $data->{'query'}->{'pages'}->{'page'}->{'title'};
    $title =~ s/^\Q$namespaces->{$ns}\E//;
    return $ns, $title;
  } else { 
    return undef;
  }        
}

#####################################################################
=item B<api_get_move_log>(NS, TITLE) 

Download a list of move log entries for NS:TITLE

Returns a reference to an array of hashes

=cut

sub api_get_move_log {
  my $ns = shift;
  my $title = shift;

  if (0 && $use_toolserver == 1) { 
    return toolserver_get_move_log($ns, $title);
  }

  init_api();

  $title = $namespaces->{$ns} . $title;  

  my $data = $api->log_events($title, 'move');

  my $output = [];
  my $d;

  foreach $d ( @$data ) { 
    $d->{'user'} = encode('utf8', $d->{'user'});
    $d->{'title'} = encode('utf8', $d->{'title'});
    $d->{'comment'} = encode('utf8', $d->{'comment'});
    $d->{'dest-ns'} =$d->{'move'}->{'new_ns'};
    $d->{'dest-title'} = encode('utf8',$d->{'move'}->{'new_title'});

    push @$output, $d;
  }

 return $output;
}


#Load successfuly
1;
