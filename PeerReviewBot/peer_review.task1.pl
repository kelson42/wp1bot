#!/usr/bin/perl
# 
# PeerReviewBot 
# Task 1: archive old peer reviews
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

use POSIX;

#########################################################################
############ Load and initialize API and Edit libraries

use lib '/home/veblen/VeblenBot/';
require Mediawiki::API;
require Mediawiki::Edit;

my $api;
$api = new Mediawiki::API;

$api->base_url('http://en.wikipedia.org/w/api.php');
$api->debug_level(3);
$api->maxlag(`/home/veblen/maxlag.sh`);
$api->login_from_file("/home/veblen/api.credentials.pr");

my $edit;
$edit = new Mediawiki::Edit;
$edit->base_url('http://en.wikipedia.org/w');
$edit->maxlag(`/home/veblen/maxlag.sh`);
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

  print "D " . $page->{'title'} . " " . $page->{'timestamp'} . "\n";

  if ( str2time($page->{'timestamp'}) <= $expiry   ) { 
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
     push @$archivablePages, $page;
     $currentPeerReviewDetails->{$page}->{'fac'} = 1;
  }
  if ( defined $currentFLC->{$currentPeerReviewTalks->{$page}} ) { 
     push @$archivablePages, $page;
     $currentPeerReviewDetails->{$page}->{'flc'} = 1;
  }
}

###########################################################################
###################  Look for PRs that can be archived

my $revisions = get_revisions($api, $currentPeerReviews);

#print Dumper($revisions);

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

  print 
    floor(($now - $timestampe) / (24*60*60) )
    . " " . $page . "\n    " . $timestamp . " " 
    . ceil(($timestampe - $expiry)/(24*60*60)) . "\n";

  if ( $timestampe < $expiry ) { 
    push @$archivablePages, $page;
    $currentPeerReviewDetails->{$page}->{'expired'} = 1;
  }
}

print "Want to archive " . (scalar @$archivablePages) . " pages\n";

###########################################################################
#### Go through archivable pages, archive the ones that pass a sanity check

my $prContent;
my $talkContent;

my $prTag;
my $talkTag;

my $badPRPages = [];
my $badTalkPages = [];
my $archive;

my $editsummary = "Archiving peer review (bot task 1)";

my $s;

my $log = [];
my $logErrors = [];
my $reason;

foreach $page ( @$archivablePages ) {
  print "go $page\n";
  $reason = start_reason($page);

  if ( defined $currentPeerReviewDetails->{$page}->{'fac'} ) { 
    $reason .= "article is on [[WP:FAC]]";
  }
  if ( defined $currentPeerReviewDetails->{$page}->{'flc'} ) { 
    $reason .= "article is on [[WP:FLC]]";
  }
  if ( defined $currentPeerReviewDetails->{$page}->{'expired'} ) { 
    $reason .= "no recent comments";
    if ( defined $currentPeerReviewDetails->{$page}->{'old'} ) { 
      $reason .= ", and over 30 days old";
    }
  }

  push @$log, $reason;

#  print "LOG: \n";
#  print Dumper($log);
#  print "\n";

  $prContent   = $api->content(encode("utf8", $page));
  $talkContent = $api->content(encode("utf8", 
                                      $currentPeerReviewTalks->{$page}));  

  print "TC: '$talkContent'\n";

  if ( $talkContent =~ m!#[Rr][Ee][Dd][Ii][Rr][Ee][Cc][Tt]\s*\[\[([^]]*)]]!) { 
    $currentPeerReviewTalks->{$page} = $1;
    
    print "Bypassing talk page redirect to :'" . $currentPeerReviewTalks->{$page} . "'\n";
    $talkContent = $api->content(encode("utf8", 
                                 $currentPeerReviewTalks->{$page}));  

  }


  if ( $prContent =~ m!({{[Pp]eer review page[^{}]*}})! ) { 
    $prTag = $1;
  } else { 
    push @$badPRPages, $page;
    print "\tSanity check failed for $page: bad PR tag\n";
    print "------------------  PR page:\n" . substr($prContent,0, 1000);
    next;
  }

#exit;

  if ( $page =~ m!archive(\d+)$! ) { 
    $archive = $1;
  } else { 
    print "Unexpected error: misnamed PR page $page has no archive number\n";
    push @$badPRPages, $page;
    next;
  }

  # There are several "correct" ways for templates to be on the article
  # talk page. Only one of them requires an edit on archiving: the
  # {{Peer review}} template is replaced by {{Oldppeerreview}}. 
  # If the oldpeerreview template is already on the talk page,
  # we can just leave it.

  # Also, the Articlehistory template can be used. This is more difficult
  # to detect with regular expressions, but I think we can get 99% 
  # right by looking for the articlehistory template and the link to the
  # peer review page. It's still somewhat hackish. 

  my $skipTalkReplace = 0;

  if ( $talkContent =~ m!({{[Pp]eer ?review[^{}]*}})! ) { 
    $talkTag = $1;
  } elsif ( $talkContent =~ m!{{[Oo]ldpeerreview\s*|\s*archive=\Q$archive\E\s*}}! ) { 
    $skipTalkReplace = 1;
    print "Talk page already has oldpeerreview template\n";
  } elsif ( $talkContent =~ m!{{[Aa]rticleHistory!  
            && $talkContent =~ m!action\d+link\s*=\s*\Q$page\E! ) { 
    $skipTalkReplace = 1;
    print "Talk page has articlehistory template!\n";
  } else { 
    print "\tSanity check failed for $page: bad talk page tag\n";
    print "------------------  Talk page:\n" . substr($talkContent,0, 1000);
    push @$badTalkPages, $page;
    next;
  }

#  print "\tSanity check OK: archive # $archive\n\t$prTag\n\t$talkTag\n";
  
  # Now replace templates with archive versions and commit

  $prContent =~ s!{{[Pp]eer review page[^{}]*}}!{{subst:PR/archive}}!;

  $s = "{{oldpeerreview|archive=$archive}}";
  $talkContent =~ s!{{[Pp]eer ?review[^{}]*}}!$s!e;

  if ( $dryrun == 0) { 
    $edit->edit(encode("utf8", $page), 
                encode("utf8", $prContent), 
                $editsummary);

    if ( $skipTalkReplace == 0) { 
      $edit->edit(encode("utf8", $currentPeerReviewTalks->{$page}), 
                  encode("utf8", $talkContent), 
                  $editsummary);
    }
  } else { 
    print "Dryrun, but $page looks OK\n";
    open OUT, ">>DryRun";
    binmode OUT, ":utf8";
    print OUT "-- $page\n";
    print OUT "----------------  New PR page:\n" 
               . substr($prContent,0, 1000);
    print OUT "\n\n";
    print OUT "----------------  New talk page:\n" 
               . substr($talkContent,0, 1000);
    print OUT "\n\n";
  }
}

my $reason;

foreach $page ( @$badTalkPages ) { 
  $reason = start_reason($page);
  $reason .= "Missing or unrecognizable peerreview template on talk page";
  push @$logErrors, $reason;
}

foreach $page ( @$badPRPages ) { 
  $reason = start_reason($page);
  $reason .= "Missing or unrecognizable PR/header template on PR page";
  push @$logErrors, $reason;
}

print "Commit log entry\n";

commit_log_entry($edit, $log, $logErrors);

print "Done\n";

exit;

##########################################################################
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

#########################################################################
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
      $result = $api->makeXMLrequest([ 
                                 'action' => 'query', 
                                 'prop'   => 'revisions', 
                                 'format' => 'xml',
                                 'titles' => encode("utf8", $title),
                                 'rvprop' => 'timestamp|user|comment|flags' ], 
                                  [ 'page' ]);
  
      $result = $result->{'query'}->{'pages'}->{'page'};
      $results = [ @$results , @$result ];
      $titles = [];
    }
  }

  if ( scalar @$titles > 0 ) { 
    $title = join "|", @$titles;
    print "Fetching revisions for " . (scalar @$titles) . " titles\n";
    $result = $api->makeXMLrequest([ 
         'action' => 'query', 
         'prop'   => 'revisions', 
         'format' => 'xml',
         'titles' => encode("utf8", $title),
         'rvprop' => 'timestamp|user|comment|flags' ], 
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


#######################################################################3
## Log today's changes

sub commit_log_entry {
  my $editor = shift;
  my $log = shift;
  my $logError = shift;

  my $message = "";

  open LOG, ">>Log";
  binmode LOG, ":utf8";

  my $dateLong = `/bin/date`;
  chomp $dateLong;

  my $date = `/bin/date +'%b %d'`;
  chomp $date;
  
  my $count = scalar @$log;
  my $line;

  my $header = "Peer review archiving log for $date";
  $message .= "Script executed $dateLong.\n\nResult: ";

  if ( $count == 0) { 
    $message .= "no peer review pages archived today.\n";
  } else {
    $message .= "$count peer review pages ready to archive.\n";
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

  open LOG, ">>Log";
  binmode LOG, ":utf8";
  print LOG "== $header ==\n";
  print LOG $message;
  close LOG;

  my $logpage = "User:PeerReviewBot/Logs/Archive";
  if ( $dryrun == 0) {
    $editor->append($logpage, encode("utf8",$message), $header);
  }

}

#######################################################################3
## Format links to pr page and article talk page

sub start_reason { 
  my $page = shift;

  my $title = $page;
  $title =~ s!^Wikipedia:Peer review/!!;
  $title =~ s!/archive\d+$!!;
  return sprintf "[[%s]] ([[%s|peer review]] - [[%s|article talk]]): ",
          $title, $page, $currentPeerReviewTalks->{$page} ;

}

__END__
