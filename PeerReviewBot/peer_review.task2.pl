#!/usr/bin/perl
# 
# PeerReviewBot 
# Task 2: add links to semiautomated peer reviews
#
# Carl Beckhorn, 2008
# Copyright: GNU Public License (GPL) 2.0

#my $dryrun = 1;  # Won't edit anything if this is nonzero
my $dryrun = ($ENV{'DRYRUN'} || 0);

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
my $currentPeerReviews = [];

my $cprdRaw = $api->pages_in_category_detailed(
                       "Category:Current_peer_reviews", 4);

foreach $page ( @$cprdRaw ) {
  push @$currentPeerReviews, $page->{'title'};
  $currentPeerReviewDetails->{$page->{'title'}} = $page;
}

$currentPeerReviews = [ sort @$currentPeerReviews ];

print "Read " . (scalar @$currentPeerReviews) . " current peer reviews.\n";

##########################################################################
############## Fetch link of semi-automated reviews

my $cat = "Category:Peer review pages with semiautomated peer reviews";

my $results = $api->pages_in_category($cat, 4);

foreach $page ( @$results) {
  if ( defined $currentPeerReviewDetails->{$page} ) {
    $currentPeerReviewDetails->{$page}->{'has-sa-link'} = 1;
  }
}

##########################################################################
############## Fetch list of semi-automated reviews

my $month = `/bin/date +'%B %Y'`;
chomp $month;
my $saPage = "Wikipedia:Peer review/Automated/$month";
print "Page: '$saPage'\n";

my $saReviews = {};

my $content = $api->content($saPage);

while ( $content =~ m!^===\[\[(.*)]]===$!gm) { 
  $page = $1; 
  $saReviews->{$page} = 1;
}

##########################################################################
############## Add links to semi-automated reviews

my $title;
my $link;

my $log = [];
my $errorLog = [];

my $logEntry;

my $re = '<!--semi-automated peer review placeholder -- please do not edit or delete this comment-->';

foreach $page ( @$currentPeerReviews ) { 
  next if ( defined $currentPeerReviewDetails->{$page}->{'has-sa-link'} );

  $title = $page;
  $title =~ s!^Wikipedia:Peer review/!!;
  $title =~ s!/archive\d+!!;

  next if ( ! defined $saReviews->{$title} );

  $logEntry = make_log_line($title, $page, $month);
  push @$log, $logEntry;

  $link = "{{subst:PR/semiauto|date=$month|page=$title}}\n";

  $content = $api->content($page);

  if ( $content =~ m!$re!m ) { 
    print "\tmatch\n";
    $content =~ s!$re!$link!;
  } else {
    print "\tno match\n";
    $logEntry .= ": missing or unrecognizable comment in PR page source code";
    push @$errorLog, $logEntry;
    next;
  }

  print substr($content, 0, 1000) . "\n\n";
}

commit_log_entry($edit, $log, $errorLog);

print "Done\n";

exit;

####################################################################
####################################################################

sub make_log_line { 
  my $title = shift;
  my $prPage = shift;
  my $month = shift;

  my $pat = "* [[%s]] ([[%s|peer review page]] - [[Wikipedia:Peer review/Automated/%s#%s|semi-auto peer review]])";

  return sprintf $pat, $title, $prPage, $month, $title;
}

####################################################################

sub commit_log_entry {
  my $editor = shift;
  my $log = shift;
  my $logErrors = shift;

  my $message = "";

  open LOG, ">>Log";
  binmode LOG, ":utf8";

  my $dateLong = `/bin/date`;
  chomp $dateLong;

  my $date = `/bin/date +'%b %d'`;
  chomp $date;
  
  my $count = scalar @$log;
  my $line;

  my $header = "Semiautomated peer review linking log for $date";
  $message .= "Script executed $dateLong.\n\nResult: ";

  if ( $count == 0) { 
    $message .= "no semiautomated peer reviews linked today.\n";
  } else {
    $message .= "$count semiautomated peer revies to link.\n";
    foreach $line ( @$log) { 
      $message .= "* $line\n";
    }
 
    $count = scalar @$logErrors; 
    if ( $count == 0 ) { 
      $message .= "No errors encountered.\n";
    } else { 
      $message .= "===Errors on $date===\n";
      $message .= "$count errors encountered:\n";
      foreach $line ( @$logErrors) { 
        $message .= "* $line\n";
      }
    }
  }    
  $message .= "\n";

  open LOG, ">>Log.2";
  binmode LOG, ":utf8";
  print LOG "== $header ==\n";
  print LOG $message;
  close LOG;

  my $logpage = "User:PeerReviewBot/Logs/SA_links";
  if ( $dryrun == 0) {
    $editor->append($logpage, encode("utf8",$message), $header);
  }
}

__END__
