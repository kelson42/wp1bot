#!/usr/bin/perl
#
# policyCache.pl
# Purpose: notification when a page becomes a policy or guideline
#
# Run with the argument 'no' to prevent sending messages, but update cache
#
# Carl Beckhorn 2008
# Copyright: GPL 2.0

use strict;
use Encode;

use lib '/home/veblen/VeblenBot';
use Mediawiki::API;
use Mediawiki::Edit;

binmode STDOUT, ":utf8";

my $maxlag = 30;

my $api = new Mediawiki::API;
$api->base_url('http://en.wikipedia.org/w/api.php');
$api->maxlag($maxlag);
$api->debug_level(3);
$api->login_from_file("/home/veblen/api.credentials");

my $editor = new Mediawiki::Edit;
$editor->base_url('http://en.wikipedia.org/w');
$editor->maxlag($maxlag);
$editor->debug_level(3);
$editor->login_from_file("/home/veblen/api.credentials");

my ($page, $arr, %CurrentPolicy, 
   %CurrentGuideline, %OldPolicy, %OldGuideline, %AnnouncedAlready);

#############################
# Fetch current data

my $userNS = 2;
my $wpNS = 4;

$arr = $api->pages_in_category('Wikipedia official policy', $wpNS);
foreach $page ( @$arr) { 
  $page =~ s/^Wikipedia://;
  $CurrentPolicy{$page} = 1; 
}

$arr = $api->pages_in_category('Wikipedia guidelines', $wpNS);
foreach $page ( @$arr) {  
  $page =~ s/^Wikipedia://;
  $CurrentGuideline{$page} = 1; 
}

#############################
# Load cached data

open IN, "<cache.policy";
binmode IN, ":utf8";
while ( <IN> ) { 
  chomp;
  $OldPolicy{$_} = 1;
}
close IN;

open IN, "<cache.guideline";
binmode IN, ":utf8";
while ( <IN> ) { 
  chomp;
  $OldGuideline{$_} = 1;
}
close IN;

open IN, "<cache.announced";
binmode IN, ":utf8";
while ( <IN> ) { 
  chomp;
  $AnnouncedAlready{$_} = 1;
}
close IN;

my $a = " no ";

#############################
# Make list of cached pages

$arr = [];

my $policyLink =  "[[Wikipedia:Policies and guidelines#Policies|policy]]";
my $guidelineLink =  "[[Wikipedia:Policies and guidelines#Guidelines|guideline]]";

my $isNowAGuideline = "has been marked as a guideline";
my $isNowAPolicy = "has been marked as a policy";
my $isNoLongerAGuideline = "no longer marked as a guideline";
my $isNoLongerAPolicy = "no longer marked as a policy";

my $taggedAsPolicy = "has recently been edited to mark it as a $policyLink";
my $taggedAsGuideline = "has recently been edited to mark it as a $guidelineLink";

my $wasGuideline = "It was previously marked as a $guidelineLink";
my $wasPolicy = "It was previously marked as a $policyLink";

my $removedGuideline = "has been edited so that it is no longer marked as a $guidelineLink";
my $removedPolicy = "has been edited so that it is no longer marked as a $policyLink";

my $closing = "This is an [[Wikipedia:Bots/Requests_for_approval/VeblenBot_6|automated notice]] of the change. -- ~~~~";

foreach $page ( keys %CurrentPolicy ) { 
  if ( defined $OldPolicy{$page} ) { 
    # OK - no change
  } elsif ( defined $OldGuideline{$page} ) { 
    push @$arr, [$page, "{{lw|$page}} $taggedAsPolicy. $wasGuideline. $closing", "Wikipedia:$page $isNowAPolicy"];
  } else { 
    push @$arr, [$page, "{{lw|$page}} $taggedAsPolicy. $closing", "Wikipedia:$page $isNowAPolicy"];
  }
}

foreach $page ( keys %CurrentGuideline ) {
  if ( defined $OldPolicy{$page} ) { 
    push @$arr, [$page, "{{lw|$page}} $taggedAsGuideline. $wasPolicy. $closing", "Wikipedia:$page $isNowAGuideline"];
  } elsif ( defined $OldGuideline{$page} ) { 
    # OK - no change
  } else { 
    push @$arr, [$page, "{{lw|$page}} $taggedAsGuideline. $closing", "Wikipedia:$page $isNowAGuideline"];
  }
}

foreach $page ( keys %OldGuideline ) {
  if ( defined $CurrentPolicy{$page} ) { 
    # OK - covered above
  } elsif ( defined $CurrentGuideline{$page} ) { 
    # OK - no change
  } else { 
    push @$arr, [$page, "{{lw|$page}} $removedGuideline. $wasGuideline. $closing", "Wikipedia:$page $isNoLongerAGuideline"];
  }
}

foreach $page ( keys %OldPolicy ) {
  if ( defined $CurrentPolicy{$page} ) { 
    # OK - no change
  } elsif ( defined $CurrentGuideline{$page} ) { 
    # OK - covered above
  } else { 
    push @$arr, [$page, "{{lw|$page}} $removedPolicy. $wasPolicy. $closing", "Wikipedia:$page $isNoLongerAPolicy"];
  }
}

#############################
# Write caches back to disk

open OUT, ">cache.policy";
binmode OUT, ":utf8";
foreach $page ( sort keys %CurrentPolicy) { 
  print OUT $page . "\n";
}
close OUT;

open OUT, ">cache.guideline";
binmode OUT, ":utf8";
foreach $page ( sort keys %CurrentGuideline) { 
  print OUT $page . "\n";
}
close OUT;

open OUT, ">cache.announced";
binmode OUT, ":utf8";
foreach $page ( @$arr ) { 
  print OUT ${$page}[0] . "\n";
}
close OUT;

#############################
# Make announcements on the wiki

if ( scalar @$arr > 5) { 
  print "Too many notices. Possibly due to a cache error. Aborting.\n";
  exit;
}

my (@recipients, $recip);
open IN, "<mailing.list" or die;
binmode IN, ":utf8";
while ( $recip = <IN> ) {
  chomp $recip;
  push @recipients, $recip;
}
close IN;

foreach $page ( @$arr ) { 
  if ( defined $AnnouncedAlready{${$page}[0]} ) { 
    print "Already announced '${$page}[0]'\n";
    next;
  }
  foreach $recip (@recipients) { 
    print "Tell '$recip' about '${$page}[0]'\n";
    next if ( $ARGV[0] =~ /no/); # update cache only
    $editor->append($recip, ${$page}[1], ${$page}[2]);
  }
}

#############################
# End
