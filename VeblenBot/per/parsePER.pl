#!/usr/bin/perl
# 
# part of VeblenBot
# Carl Beckhorn, 2008
# Copyright: GPL 2.0

binmode STDOUT, ":utf8";

use Date::Parse;
use strict vars;
use LWP::UserAgent;
use POSIX qw(strftime);

use Data::Dumper;

use Encode;

$Data::Dumper::Useqq = 1;

use lib '/home/veblen/VeblenBot/wikipedia_perl_bot';
require 'bin/wikipedia_login.pl';
require 'bin/fetch_articles_cats.pl';

use lib '/home/veblen/VeblenBot/';
require Mediawiki::API;

#log in (make sure you specify a login and password in bin/wikipedia_login.pl
&wikipedia_login();
  
my $Root_category = 'Category:Wikipedia_protected_edit_requests';
my @tmp_cats;
my @tmp_articles;

my $art;
my %Dates;
my $date;

my %Cached; 
my %Seen;

my @articles;

##### Log in to API
my $api;
$api = new Mediawiki::API;
$api->base_url('http://en.wikipedia.org/w/api.php');
$api->debug_level(3);
$api->login_from_file("/home/veblen/api.credentials");
$api->{'botlimit'} = 1000;


#################### Read cache of when tag was added
my $tmp = $/; #This is ugly but I want to be paranoid about global vars

$/ = "\n";  

if ( -r "Cache") { 
  open IN, "<Cache";
  while ( $art = <IN>){
    chomp $art;
    ($date, $art) = split /\t/, $art, 2;
    $Dates{$art} = $date;
    $Cached{$art} = 1;
  }
}

$/ = $tmp;

################### Fetch list of editprotected requests from wiki

$date =  `/bin/date --rfc-3339=date`;
chop $date;  # $/ is likely wrong

my $now;
$now =  `/bin/date +'%F %H:%M'`;
chop $now;

print "Now: $now.\n";

my $talk;
my %Talks;

#&fetch_articles_cats($Root_category, \@tmp_cats, \@tmp_articles);

@tmp_articles = @{$api->pages_in_category($Root_category)};

#print Dumper(@tmp_articles). "\n";

foreach $art ( @tmp_articles) { 
  $talk = $art;
  $art =~ s/^Talk://;
  $art =~ s/Template talk:/Template:/;
  $art =~ s/MediaWiki talk:/MediaWiki:/;
  $art =~ s/Wikipedia talk:/Wikipedia:/;
  $art =~ s/Image talk:/:Image:/;
  $art =~ s/User talk:/User:/;
  $art =~ s/Help talk:/Help:/;
  $art =~ s/Portal talk:/Portal:/;
  $art =~ s/Category talk:/Category:/;

  $Talks{$art} = $talk;

  push @articles, $art; 

  $Seen{$art} = 1;

  if ( ! defined $Dates{$art} ) { 
    $Dates{$art} = $date;
  }
}

@articles = sort   { $_ = $Dates{$a} cmp $Dates{$b};
                     if ( $_ != 0) { return $_;}
                     return $a cmp $b;
                   }
                 @articles;


#@articles = ('Super Mario Galaxy');
#########################
## screen scraping to find protection (last resort) 

sub scrape() {
  my $art = shift;
  my $type = "unknown";
  print STDOUT "\tFalling back to HTML scraping\n";
  sleep 2;
         
  my $tmp = $/;
  $/ = "\n";
        
  open NET, "/usr/bin/wget -q -O - http://en.wikipedia.org/wiki/"          
                                         . html_encode($art) . "|";
  my $line;
  my $found = 0;
  while ( $line = <NET> ) {
    if ( $line =~ /^var wgRestrictionEdit = \["?([^"]*)"?\]/) { 
      $line = $1;
      $found = 1;
      last;
     } 
  }
  close NET;
  $/ = $tmp;
  
  if ( $found == 1) { 
    print "\tHTML scraping found '$line'\n"    ;
    if ( $line eq 'sysop' || $line eq 'autoconfirmed') {
      $type = $line;
    }
    if ( $line eq '') { 
      $type = "Not protected";
    }
  }          

  return $type;
}


#####################
##################### main function 

my $count = 0;

my $min = 0;
my $max = 10000;

my $res;
my $obj;
my $query;
my @logevents;
my $event;

my %Comments;
my %Times;
my %TimesEpoch;
my %Users;
my %Actions;
my %Expiries;
my %Types;

my $total = scalar @articles;

$count = 0;

##### Parse protection log for each article

foreach $art ( @articles) { 
  $count++;
  printf "\n%04d/%04d %s\n", $count, $total, html_encode($art);

  if ( $art =~ /^MediaWiki/) { 
    $Actions{$art} = "mw"; 
    $Types{$art} = "mw";
    next;
  }

  @logevents  = @{$api->log_events(encode("utf8",$art))};
#  print Dumper(@logevents);
   

  foreach $event ( @logevents) { 
    next unless ( ${$event}{'type'} eq 'protect');     

    my $time = str2time(${$event}{'timestamp'});
    $Times{$art} = ${$event}{'timestamp'};
    $Times{$art} =~ s/(\d\d\d\d-\d\d-\d\d).*/$1/;
    $TimesEpoch{$art} = $time;

    $Users{$art} = ${$event}{'user'};
#    print "User: " . $Users{$art} . "\n";
    $Comments{$art} = ${$event}{'comment'};
   
    if ( ${$event}{'action'} eq 'modify') { 
      ${$event}{'action'} = 'protect';
    }

    $Actions{$art} = ${$event}{'action'};

    if ( ${$event}{'action'} eq 'protect') { 
      my ($comment, $type, $expiry);
      $expiry = ""; 

      if ( $Comments{$art} =~ /^(.*)? ?\[edit=(.*):move=.*]( \(expires (.*)\))?/) 
      {
         $comment = $1;
         $type = $2;
         if ( defined $3 ) {          
           $expiry= $3; 
           $expiry =~ s/\(expires (.*)\)/$1/;
           $expiry =~ s/^\s*//;
           $time = str2time($expiry);
           $expiry = strftime "%Y-%m-%d", gmtime($time);
         } 
      } else {
         $comment = $Comments{$art};
         $type = 'Unknown protection';
         $type = &scrape($art);
      }

      if ( $type eq 'sysop') { $type = "Fully protected";} 
      elsif ( $type eq 'autoconfirmed') { $type = 'Semiprotected'}
      $Types{$art} = $type;

      $Expiries{$art} = $expiry;
      $Comments{$art} = $comment;
    } else {  # it was an unprotection event
      if ( defined $Comments{$art}  ) { 
        # will be undef if no comment was left
        $Comments{$art} =~ s/Unprotection,\s*//;
      }
    }
    last; # we only want the most recent protection event from the log
  }

  if ( ! defined $Actions{$art} ) { 
    my $type = &scrape($art);
    if ( $type eq 'sysop') { 
      $type = "Fully protected";
      $Actions{$art} = "protect";
    } elsif ( $type eq 'autoconfirmed') { 
      $type = 'Semiprotected';
      $Actions{$art} = "protect";
    } elsif ( $type eq 'Not protected') {  
      $Actions{$art} = "notprotected";
    }

    $Types{$art} = $type;
  }
}


###################  Make wikitable of requests

open OUT, ">PERtable";
binmode OUT, ":utf8";

print OUT << "HERE";
{| class="wikitable" style="padding: 0em;"
|-
! $count [[WP:PER|protected edit requests]]
|-
|
{| class="wikitable sortable" width=100% style="margin: 0em;"
! Article
! Tagged since
! Protection
! When / Expires
! class = "unsortable" | Why
HERE


my $log;
foreach $art ( @articles) { 
  $log = 'http://en.wikipedia.org/w/index.php?title=Special:Log&type=protect&page='
         . html_encode($art);

  if ( ! defined $Comments{$art} ) { 
    $Comments{$art} = "";
  }

  if ( ! defined $Actions{$art} ) {
    print OUT << "HERE";
|-
| [[$art]] ([[$Talks{$art}#editprotected|request]])
| $Dates{$art}
| Never protected at this name (possibly moved after protection). <span class="plainlinks">([$log log])</span>
| 
| 
HERE
  } else {
#    print STDERR "See action $Actions{$art}\n";
  }

if ( $Actions{$art} eq 'protect') { 
     if ( defined $Users{$art}) { 
# print "User 2: " . $Users{$art} . "\n";
    print OUT << "HERE";
|-
| [[$art]] ([[$Talks{$art}#editprotected|request]])
| $Dates{$art}
| $Types{$art} by [[User talk:$Users{$art}|$Users{$art}]] <span class="plainlinks">([$log log])</span>
| $Times{$art} $Expiries{$art}
| <nowiki>$Comments{$art}</nowiki>
HERE
     } else {
  if ( ! defined $Times{$art} ) { 
    $Times{$art} ="";
    $Expiries{$art} = "";
  }
print OUT << "HERE";
|-
| [[$art]] ([[$Talks{$art}#editprotected|request]])
| $Dates{$art}
| $Types{$art} by magic. <span class="plainlinks">([$log log])</span>
| $Times{$art} $Expiries{$art}
| 
HERE
     }

  } elsif ($Actions{$art} eq 'unprotect')  { 
    print OUT << "HERE";
|-
| [[$art]] ([[$Talks{$art}#editprotected|request]])
| $Dates{$art}
| Unprotected by [[user:$Users{$art}|$Users{$art}]] <span class="plainlinks">([$log log])</span>
| $Times{$art}
| <nowiki>$Comments{$art}</nowiki>
HERE
  } elsif ($Actions{$art} eq 'notprotected')  { 
    print OUT << "HERE";
|-
| [[$art]] ([[$Talks{$art}#editprotected|request]])
| $Dates{$art}
| Not protected  <span class="plainlinks">([$log log])</span>
| 
| 
HERE
  } elsif ( $Actions{$art} eq 'mw') { 
    print OUT << "HERE";
|-
| [[$art]] ([[$Talks{$art}#editprotected|request]])
| $Dates{$art}
| MediaWiki page
| 
| 
HERE
  }
}	


#########################3### Update cache
$date = `/bin/date`;

print OUT << "HERE";
|}
|-
| style="text-align: right; font-size: smaller;"| Updated on the half hour. Last updated: $date
|}
HERE

close OUT;

open OUT, ">Cache";
foreach $art ( @articles) { 
  print OUT "$Dates{$art}\t$art\n";
}
close OUT;


############## Log entries

open LOG, ">>Log";
my $msg;

foreach $art ( keys %Seen) { 
  print "Protected article: $art\n";

  if ( ! defined $Actions{$art} ) { 
    $msg = 'unknown';
  } elsif ( $Actions{$art} eq 'protect') { 
    $msg = $Types{$art};
  } elsif ( $Actions{$art} eq 'unprotect') { 
    $msg = 'Not protected';
  } elsif ( $Actions{$art} eq 'mw') { 
    $msg= 'mediawiki';
  } elsif ( $Actions{$art} eq 'notprotected') { 
    $msg= 'Not protected';
  } else {
    $msg = "error";
  }

  if ( ! defined $Cached{$art} ) { 
    print LOG "N\t$now\t$msg\t$art\n";
  }
}

foreach $art ( keys %Cached) { 
  $msg = 'resolved';
  if ( ! defined $Seen{$art} ) { 
    print "Resolved $art\n";
    print LOG "R\t$now\t$msg\t$art\n";
  }
}

close LOG;


##################  Log queue length 

open LOG, ">>Log2";
print  "$count $now\n";
close LOG;

