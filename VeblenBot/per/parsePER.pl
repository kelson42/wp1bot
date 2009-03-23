#!/usr/bin/perl
# 
# part of VeblenBot
# Carl Beckhorn, 2008
# Copyright: GPL 2.0
#

use Date::Parse; 
use strict vars; 
use LWP::UserAgent; 
use Encode;

use Data::Dumper;
$Data::Dumper::Useqq = 1;

binmode STDOUT, ":utf8";

use lib '/home/veblen/VeblenBot/';
require Mediawiki::API;

my $Root_category = 'Category:Wikipedia_protected_edit_requests';

my $art;
my %Dates;
my $date = `/bin/date --rfc-3339=date`;
chomp $date;

my %Cached; 
my %Articles;
my $count;

my %Comments;
my %Times;
my %TimesEpoch;
my %Users;
my %Actions;
my %Expiries;
my %Types;
my %Talks;
my %Blacklist;

my $now;
$now =  `/bin/date +'%F %H:%M'`;
chop $now;

print "Now: $now.\n";


##### Log in to API
my $api;
$api = new Mediawiki::API;
$api->base_url('http://en.wikipedia.org/w/api.php');
$api->debug_level(5);
$api->login_from_file("/home/veblen/api.credentials");

read_cache();
read_blacklist();
get_protected_page_data();
make_pertable();
update_cache();
update_log();
log_queue_length();

exit;

######################################################################

sub get_protected_page_data {
  my ($talk, $art, $type, $expiry, $art, $oldart, $comment, $action,
      $time, $timeEpoch, $user, $d);

  my @tmp_articles = @{$api->pages_in_category_detailed($Root_category)};

  foreach $d ( @tmp_articles) { 
    print Dumper($d);
    $art = $d->{'title'};

    next if ($art eq 'Category:Wikipedia semi-protected edit requests');

    $talk = $art;
    $art =~ s/^Talk://;
    $art =~ s/Template talk:/Template:/;
    $art =~ s/MediaWiki talk:/MediaWiki:/;
    $art =~ s/Wikipedia talk:/Wikipedia:/;
    $art =~ s/Image talk:/Image:/;
    $art =~ s/User talk:/User:/;
    $art =~ s/Help talk:/Help:/;
    $art =~ s/Portal talk:/Portal:/;
    $art =~ s/Category talk:/Category:/;

    next if ( defined $Blacklist{$art} );

    # Escape Category and Image links
    $art =~ s/^Category/:Category/;
    $art =~ s/^Image/:Image/;
    $talk =~ s/^Category/:Category/;
    $talk =~ s/^Image/:Image/;

    $Talks{$art} = $talk;
    $Articles{$art} = 1;

    if ( ! defined $Dates{$art} ) { 
      $Dates{$art} = substr($d->{'timestamp'}, 0, 10);
      print "New request: $art: " . $Dates{$art} . "\n";
    }
  }

  print Dumper(%Articles);

  foreach $art ( sort by_name keys %Articles ) { 
    if ( $art =~ /MediaWiki/) {
      $type = "mw";
      $expiry = "infinite";   
      $user = "";
      $expiry = "";
      $time = "";
      $action = "";
      $timeEpoch = "";
    } else {
      ($type, $expiry) = get_protection_info($art);
      ($comment, $time, $timeEpoch, $user, $action) = get_protection_log($art);
      if ( ! defined $comment) { 
        $oldart = get_former_name($art);
        if ( defined $oldart) { 
          ($comment, $time, $timeEpoch, $user, $action) = get_protection_log($oldart);
        }   
      } 
    }

#    if ( $type eq 'sysop') { 
#      $type = "Fully protected";
#    } elsif ( $type eq 'autoconfirmed') { 
#       $type = 'Semiprotected';
#    } 

    $Types{$art} = $type;
    $Comments{$art} = $comment;
    $Times{$art} = $time;
    $TimesEpoch{$art} = $timeEpoch;
    $Users{$art} = $user;
    $Expiries{$art} = $expiry;
    $Actions{$art} = $action;
  }

  $count = scalar keys %Articles;

}

##########################################################

sub get_protection_info() {
  my $art = shift;

  $art =~ s/^://;

  my $pr;
  my $type = 'Not protected';
  my $expiry = 'infinite';

  my $info = $api->page_info(encode("utf8",$art));
  
  if ( defined $info->{'protection'} ) { 
    $info= $info->{'protection'}->{'pr'};
    if (  ref($info) eq "HASH") { $info = [ $info ]; }
 
    print Dumper($info);
    foreach $pr ( @$info) { 
      if ( $pr->{'type'} eq 'edit' || $pr->{'type'} eq 'create' ) { 
        $type = $pr->{'level'};
        $expiry = $pr->{'expiry'}
      }
    }      
  } else { 
    print "PAGE INFO NOT DEFINED $art\n";
  }

  print "$art $type $expiry\n";

  return ($type, $expiry);
}

#######################################################

sub get_protection_log {

  my $art = shift;
  my ($tmp, $Action, $Type, $Comment, $Time, $TimeEpoch,
      $User, $Expiry);

  my @logevents  = @{$api->log_events(encode("utf8",$art))};
   
  my $event;
  foreach $event ( @logevents) { 
    next unless ( ${$event}{'type'} eq 'protect');     

#   print Dumper($event);

    my $time = str2time(${$event}{'timestamp'});
    $Time = $event->{'timestamp'};

    $Time =~ s/(\d\d\d\d-\d\d-\d\d).*/$1/;
    $TimeEpoch = $time;
    $User = $event->{'user'};
    $Comment = $event->{'comment'};
    $Comment =~ s/\s*\[[^]]*]( \(expires [\w\d ,:()]*\))?$//;
    $Action = $event->{'action'};

    last;

  } 
  
  return ($Comment, $Time, $TimeEpoch, $User, $Action);
}

###################################################

sub get_former_name { 
  my $art = shift;
  my $revs= $api->revisions(encode("utf8",$art), 2500);

  my ($rev, $newpage, $oldpage);

  foreach $rev ( @$revs) { 
#    print $rev->{'comment'} . "\n";
    if ( $rev->{'comment'} =~
                  /[Mm]oved \[\[([^\]]*)]] to \[\[([^\]]*)]]/) { 
      $oldpage = $1;
      $newpage = $2;
      print "\tNote: $oldpage moved to $newpage\n";
      last;
    }
  }

  return $oldpage;
}

###################  Make wikitable of requests

sub make_pertable {

  my %ColorScheme = ( 'yellow' =>  '#FFF9BF',
                      'blue'   => '#E4FFCC',
                      'red' => '#FFBFDC' );

  my %ActVerb = ( 'protect' => 'Protected',
                  'modify' => 'Modified',
                  'unprotect' => 'Unprotected' );


  my %TypeVerb = ( 'sysop' => 'Fully protected',
                   'Not protected' => 'Not protected',
                   'autoconfirmed' => 'Semiprotected' );

  open OUT, ">PERtable.new";
  binmode OUT, ":utf8";

  my $s = 's';
  if ( $count == 1) { 
    $s = '';
  }

  print OUT << "HERE";
<div class="veblenbot-pertable">
{| class="wikitable" style="padding: 0em;"
|-
! $count [[WP:PER|protected edit request$s]]
|-
|
{| class="wikitable sortable" width=100% style="margin: 0em;"
! Page
! Tagged since
! Protection level
! class = "unsortable" | Last protection log entry
HERE

  my $log;
  foreach $art ( sort by_name keys %Articles ) { 
    $log = 'http://en.wikipedia.org/w/index.php?title=Special:Log&type=protect&page='
           . html_encode($art);

    if ( ! defined $Comments{$art} ) { 
      $Comments{$art} = "";
    }

    if ( ! defined $Expiries{$art} ) { 
      $Expiries{$art} = '';
    }

    my ($typeLine, $logLine, $exp, $verb);
    my $bg = "";

    if ( $Types{$art} eq 'mw') { 
      $typeLine = 'Mediawiki page';
      $logLine = '';
      $bg = "style=\"background-color: " . $ColorScheme{'yellow'} . ";\"";
    } else { 
      $verb = $TypeVerb{$Types{$art}};
      if ( $Expiries{$art} =~ /infinit[ey]/ ) { 
        $typeLine = "$verb <span class=\"plainlinks\">([$log log])</span>"; 
      } else {
        $exp = $Expiries{$art};
        $exp =~ s/Z/ UTC/;
        $exp =~ s/T/ at /;
        $typeLine = "$verb, expires $exp <span class=\"plainlinks\">([$log log])</span>"; 
      }

       $Comments{$art} =~ s/{/&#123;/g;

      if ( defined $Actions{$art} ) { 
       print "$art '$Actions{$art}'\n";
        $logLine = "$ActVerb{$Actions{$art}} by [[User:$Users{$art}|$Users{$art}]] on $Times{$art}: &#8220;$Comments{$art}&#8221;";
      } else { 
        $logLine = "";
     }

      if ( ! ($Types{$art} eq 'sysop')) { 
        $bg = "style=\"background-color: " . $ColorScheme{'red'} . ";\"";
      }	elsif ( $art =~ /^Template:/) { 
        $bg = "style=\"background-color: " . $ColorScheme{'blue'} . ";\"";
      }        

    }


    print OUT << "HERE";
|- $bg
| [[$art]] ([[$Talks{$art}#editprotected|request]])
| $Dates{$art}
| $typeLine
| $logLine
HERE

    print << "HERE";
Article:    $art
Date:       $Dates{$art}
Action:     $Actions{$art}
Type:       $Types{$art}
Expiry:     $Expiries{$art}
User:       $Users{$art}
Comment:    $Comments{$art}
LogTime:    $Times{$art}

HERE

  }


  my $date = `/bin/date`;
  chomp $date;
  print OUT << "HERE";
|}
|-
| style="text-align: right; font-size: smaller;"| Updated on the half hour. Last updated: $date
|}</div>
HERE

# |-
# | style="font-size: smaller;" | '''Work in progress''': The code that 
# generates this table has been upgraded to find more log entries. The 
# layout has also been rearranged. Please direct any bug reports or 
# comments to [[User talk:CBM]]. Especially let me know if I should 
# improve or remove the colored rows.


  close OUT;

  return;
}

###########################################################################

sub read_cache { 
  my ($date, $art);
  if ( -r "Cache.new") { 
    open IN, "<Cache.new";
    while ( $art = <IN>){
      chomp $art;
      ($date, $art) = split /\t/, $art, 2;
      $Dates{$art} = $date;
      $Cached{$art} = 1;
      print "Cached: $art $date\n";
    }
  }
}

sub update_cache { 
  open OUT, ">Cache.new";
  foreach $art ( keys %Articles) { 
    print OUT "$Dates{$art}\t$art\n";
  }
  close OUT;
}

###########################################################################

sub update_log {

  open LOG, ">>Log.new";
  my $msg;

  foreach $art ( keys %Articles) { 
#    print "Protected article: $art\n";

    if ( ! defined $Actions{$art} ) { 
      $msg = 'unknown';
    } elsif ( $Actions{$art} eq 'protect') { 
      $msg = $Types{$art};
    } elsif ( $Actions{$art} eq 'unprotect') { 
      $msg = 'Not protected';
    } elsif ( $Actions{$art} eq 'mw' || $art =~ /^MediaWiki:/) { 
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
    if ( ! defined $Articles{$art} ) { 
      print "Resolved $art\n";
      print LOG "R\t$now\t$msg\t$art\n";
    }
  }

  close LOG;
} 


###########################################################################

sub log_queue_length { 

  open LOG, ">>Log2.new";
  print LOG "$count $now\n";
  close LOG;

}

###########################################################################

sub html_encode {
  local $_=$_[0];
  s/ /_/g;
  s/([^A-Za-z0-9_\-.:\/])/sprintf("%%%02x",ord($1))/eg;
  return($_);
}

###########################################################################

sub by_name { 
  $_ = $Dates{$a} cmp $Dates{$b};
  if ( $_ != 0) { return $_;}
     return $a cmp $b;
}

###########################################################################

sub read_blacklist {
  open BL, "<Blacklist";
  while ( <BL> ) { 
    chomp;
    $Blacklist{$_} = 1;
    print "Blacklist '$_'\n";
  }
}

###########################################################################
# EOF


