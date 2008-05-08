#!/usr/bin/perl
# 
# PeerReviewBot 
# Task 1: archive old peer reviews
#
# Carl Beckhorn, 2008
# Copyright: GNU Public License (GPL) 2.0

my $dryrun = 1;  # Won't edit anything if this is nonzero

use strict vars;

binmode STDOUT, ":utf8";

use Date::Parse;   # function str2time parses ASCII timestamps
use Encode;

use Data::Dumper;
$Data::Dumper::Indent = 2; 

#########################################################################
############ Load and initialize API and Edit libraries

use lib '/home/veblen/VeblenBot/';
require Mediawiki::API;
require Mediawiki::Edit;

my $api;
$api = new Mediawiki::API;

$api->base_url('http://en.wikipedia.org/w/api.php');
$api->debug_level(3);
$api->login_from_file("/home/veblen/api.credentials.pr");

my $edit;
$edit = new Mediawiki::Edit;
$edit->base_url('http://en.wikipedia.org/w');
$edit->debug_level(3);
$edit->login_from_file("/home/veblen/api.credentials.pr");

my $now = time();

##########################################################################
############## Fetch list of peer reviews

my $page;
my $currentPeerReviewDetails = {};
my $expiry = $now - 30*24*60*60;
my $currentPeerReviews = [];

my $cprdRaw = $api->pages_in_category_detailed(
                       "Category:Current_peer_reviews", 4);

foreach $page ( @$cprdRaw ) {
  push @$currentPeerReviews, $page->{'title'};
  if ( str2time($page->{'timestamp'}) <= $expiry ) { 
    $page->{'old'} = 1;
  }

  $currentPeerReviewDetails->{$page->{'title'}} = $page;
}

$currentPeerReviews = [ sort @$currentPeerReviews ];

my $currentPeerReviewTalks = make_talks($currentPeerReviews);

print "Read " . (scalar @$currentPeerReviews) . " current peer reviews.\n";


#########################################################################
###################### Fetch FAC and FLC lists

my $archivablePages = [];

my $currentFAC = make_hash($api->pages_in_category(
                      "Category:Wikipedia featured article candidates", 1));
my $currentFLC = make_hash($api->pages_in_category(
                      "Category:Wikipedia featured list candidates", 1));

foreach $page ( $currentPeerReviews ) {
  if ( defined $currentFAC->{$currentPeerReviewTalks->{$page}} ) { 
     print "$page is on FAC\n"; 
     push @$archivablePages, $page;
     $currentPeerReviewDetails->{$page}->{'fac'} = 1;
  }
  if ( defined $currentFLC->{$currentPeerReviewTalks->{$page}} ) { 
     print "$page is on FLC\n"; 
     push @$archivablePages, $page;
     $currentPeerReviewDetails->{$page}->{'flc'} = 1;
  }
}

###########################################################################
###################  Look for PRs that can be archived

my $revisions = get_revisions($api, $currentPeerReviews);

my $timestamp;
my $timestampe;

my $expiryYoung = $now - 14*24*60*60;
my $expiryOld =   $now -  2*24*60*60;

foreach $page ( @$currentPeerReviews )  {

  $timestamp = $revisions->{$page}->{'timestamp'};
  $timestampe = str2time($timestamp);

  if ( defined $currentPeerReviewDetails->{$page}->{'old'} ) { 
    $expiry = $expiryOld;
  } else { 
    $expiry = $expiryYoung;
  }

  if ( $timestampe < $expiry ) { 
    push @$archivablePages, $page;
    $currentPeerReviewDetails->{$page}->{'expired'} = 1;
  }
}

###########################################################################
#### Go through archivable pages, archive the ones that pass a sanity check

my $prContent;
my $talkContent;

my $prTag;
my $talkTag;

my $badPRPages = [];
my $badTalkPages = [];
my $archive;

my $editsummary = "Archiving peer review";

my $s;

foreach $page ( @$archivablePages ) {
  print "\n\nWould like to archive $page: ";

  if ( defined $currentPeerReviewDetails->{$page}->{'fac'} ) { 
    print "on FAC";
  }
  if ( defined $currentPeerReviewDetails->{$page}->{'flc'} ) { 
    print "on FLC";
  }
  if ( defined $currentPeerReviewDetails->{$page}->{'expired'} ) { 
    print "not recently edited";
  }
  if ( defined $currentPeerReviewDetails->{$page}->{'old'} ) { 
    print ", over 30 days old";
  }

  print ".\n";

  $prContent   = $api->content(encode("utf8", $page));
  $talkContent = $api->content(encode("utf8", 
                                      $currentPeerReviewTalks->{$page}));
 
  if ( $prContent =~ m!({{PR/header[^{}]*}})! ) { 
    $prTag = $1;
  } else { 
    push @$badPRPages, $page;
    print "\tSanity check failed: bad PR tag\n";
    print "------------------  PR page:\n" . substr($prContent,0, 1000);
    next;
  }

  if ( $page =~ m!archive(\d+)$! ) { 
    $archive = $1;
  } else { 
    print "Unexpected error: misnamed PR page has no archive number\n";
    push @$badPRPages, $page;
    next;
  }

  if ( $talkContent =~ m!({{[Pp]eer ?review[^{}]*}})! ) { 
    $talkTag = $1;
  } else { 
    print "\tSanity check failed: bad talk page tag\n";
    print "------------------  Talk page:\n" . substr($talkContent,0, 1000);
    push @$badTalkPages, $currentPeerReviewTalks->{$page};
    next;
  }

  print "\tSanity check OK: archive # $archive\n\t$prTag\n\t$talkTag\n";
  
  # Now replace templates with archive versions and commit

  $prContent =~ s!{{PR/header[^{}]*}}!{{subst:PR/archive}}!;

  $s = "{{oldpeerreview|archive=$archive}}";
  $talkContent =~ s!{{[Pp]eer ?review[^{}]*}}!$s!e;

  if ( $dryrun == 0) { 
    $edit->edit(encode("utf8", $page), 
                encode("utf8", $prContent), 
                $editsummary);
    $edit->edit(encode("utf8", $currentPeerReviewTalks->{$page}), 
                encode("utf8", $talkContent), 
                $editsummary);
  } else { 
    print "----------------  New PR page:\n" . substr($prContent,0, 1000);
    print "\n\n";
    print "----------------  New talk page:\n" . substr($talkContent,0, 1000);
    print "\n\n";
  }

  print "\n";
}

foreach $page ( @$badTalkPages ) { 
  print "Bad talk page: $page\n";
}

foreach $page ( @$badPRPages ) { 
  print "Bad PR page: $page\n";
}

exit;  # End of main routine

##########################################################################
##########################################################################
## Make a hash whose keys are from a given array reference

sub make_hash {
  my $list = shift;
  my $hash = {};
  my $e;
  foreach $e ( @$list ) { 
    $hash->{$e} = 1;
  }
  return $hash;
}

##########################################################################
## Get info on the most recent revision for a list of pages

sub get_revisions { 
  my $api = shift;
  my $pages = shift;
  
  my $titles = [];
  my $title;
  my $limit = 40;
  my $page;

  my $results = [];
  my $result;
  
  foreach $page ( @$pages ) { 
    push @$titles, $page;

    if ( scalar @$titles >= $limit ) { 
      $title =join "|", @$titles;
      print "Fetching revisions for " . (scalar @$titles) . " titles\n";
      $result = $api->makeXMLrequest([ 'action' => 'query', 
                                       'prop'   => 'revisions', 
                                       'format' => 'xml',
                                       'titles' => encode("utf8", $title),
                                       'rvprop' => 'timestamp|user|comment' ], 
                                     [ 'page' ]);
  
      $result = $result->{'query'}->{'pages'}->{'page'};
      $results = [ @$results , @$result ];
      $titles = [];
    }
  }

  if ( scalar @$titles > 0 ) { 
    $title = join "|", @$titles;
    print "Fetching revisions for " . (scalar @$titles) . " titles\n";
    $result = $api->makeXMLrequest([ 'action' => 'query', 
                                     'prop'   => 'revisions', 
                                     'format' => 'xml',
                                     'titles' => encode("utf8", $title),
                                     'rvprop' => 'timestamp|user|comment' ], 
                                   [ 'page' ]);
    $result = $result->{'query'}->{'pages'}->{'page'};
    $results = [ @$results,  @$result ];
  }

  print "Fetched revision info for " . (scalar @$results) . " pages\n";

  my $trim = {};
  my $e;

  foreach $e ( @$results ) { 
    $page = $e->{'title'};
    $trim->{$page} = $e->{'revisions'}->{'rev'};
  }

  return $trim;
}

########################################################################
## Make hash mapping peer review archive pages 
## to corresponding article talk pages      

sub make_talks {
  my $pages = shift;
  my $page;  
  my $target;
  my $targets = {};
  
  foreach $page (@$pages) { 
    $target = $page;
    $target =~ s!^Wikipedia:Peer review/!!;
    $target =~ s!/archive\d*$!!;
    $targets->{$page} = "Talk:" . $target;
  }

  return $targets;
}


__END__
