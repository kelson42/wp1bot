#!/usr/bin/perl

# manualsel.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for more information

=head1 SYNOPSIS

CGI script to maintain the manual selection

=cut

my $App = "Manual selection maintenance";

use strict;
use Encode;
use URI::Escape;
use Digest::MD5;
use Data::Dumper;
use DBI;
use POSIX 'strftime';
use URI::Escape;

my $maxadds = 10;
my $pagesize = 10;

require 'read_conf.pl';
our $Opts = read_conf();

my $url = $Opts->{"manual-url"} || die "Manual-url must be specified\n";
$url =~ s/\?$//;

require 'layout.pl';

require 'database_www.pl';
our $dbh = db_connect_rw($Opts);

use CGI;
CGI::Carp->import('fatalsToBrowser');

my $cgi;
my $loop_counter = 0;
if ( $Opts->{'use_fastcgi'} ) {
  require CGI::Fast;
  while ( $cgi = CGI::Fast->new() ) { 
    main_loop($cgi);
  }
} else {
  $cgi = new CGI;
  $loop_counter = -5;
  main_loop($cgi);
}

############################################################

sub main_loop { 
  my $cgi = shift;
  my %param = %{$cgi->Vars()};

  my $pass = $param{'pass'} || CGI::cookie('wp10pass') || '';
  my $user = $param{'user'} || CGI::cookie('wp10user') || '';
  $pass =~ s/^[^a-zA-Z]*//;
  $user =~ s/^[^a-zA-Z]*//;

  my $authenticated = 0;

  if ( defined($pass)  ) {
    $authenticated = check_auth($user, $pass);
  }

  my $value = '';
  my $authline;
  my $logincookiepass;
  my $logincookieuser;

  if ( $authenticated == 1) { 
    $value = $pass;
    $authline = << "HERE";
      <div class="authline loggedin">
        <img src="http://upload.wikimedia.org/wikipedia/commons/4/4d/Lock-open.png">
        You are logged in as <b>$user</b>
      </div>
HERE

    $logincookiepass = CGI::cookie(-name => 'wp10pass',
                                   -value => $pass, -path=>"/");
    $logincookieuser = CGI::cookie(-name => 'wp10user',
                                  -value => $user, -path=>"/");
  } else { 
    my $pa = Dumper($pass);
    my $ua = Dumper($user);

    $authline = << "HERE";
      <div class="authline notloggedin">
        <img src="http://upload.wikimedia.org/wikipedia/commons/1/1b/Lock-closed.png"> 
        You are not logged in
      </div>
HERE

    $logincookiepass = CGI::cookie(-name => 'wp10user',
                                   -value => "", -path=>"/");
    $logincookieuser = CGI::cookie(-name => 'wp10pass',
                                   -value => "", -path=>"/");
  }

  print CGI::header(-type=>'text/html', -charset=>'utf-8', 
                    -cookie=>[$logincookiepass,$logincookieuser]);


  my $mode = $param{'mode'} || $ARGV[0] || '';

  if ( $mode eq 'add' ) {
    layout_header("Add articles", $authline, "Add articles to the manual selection");
    do_add(\%param, 1, $user, $pass);
  } elsif ( $mode eq 'processadd' ) {
    layout_header("Processing added articles", $authline);
    process_add(\%param, $authenticated, $user, $pass);
  } elsif ( $mode eq 'processremoves' ) {
    layout_header("Remove articles", $authline, "Remove articles from the manual selection");
    process_removes(\%param, $authenticated, $user, $pass);
  } elsif ( $mode eq 'logs' ) { 
    layout_header("Changelog", $authline, "Manual selection changelog");
    do_log(\%param);
  } elsif ( $mode eq 'login' ) { 
    layout_header("Log in", $authline);
    auth_form_manual($user, $value);
  } elsif ( $mode eq 'processlogin' ) { 
    layout_header("Log in", $authline);
    processlogin($authenticated);
  } else { 
    layout_header("List manual selection", $authline);
    do_list(\%param);
  }

  $loop_counter++;
  layout_footer("Debug: PID $$ has handled $loop_counter requests");

  if ( $loop_counter >= $Opts->{'max-requests'} ) { exit; }
}

############################################################################

sub processlogin {
  my $authenticated = shift;
  if( $authenticated == 1) { 
    print "<b>Login successful</b>";
  }   else  {
    print "<b>Login unsuccessful; try again. $authenticated. </b>";
    auth_form_manual();
  }
 print "<div class=\"clear\">&nbsp;</div>\n";
}

############################################################################

sub process_add {
  my $params = shift;
  my $authenticated = shift;
  my $user = shift;
  my $pass= shift;

  if ( $authenticated != 1 ) { 
    print << "HERE";
    <span class="notauthenticatederror">Action not performed: You must log in to perform this action.</span>
HERE
    do_add($params, 1, $user, $pass);
    return;
  }

  my $sthart = $dbh->prepare("INSERT INTO manualselection VALUES (?,?,?)");
  my $sthlog = $dbh->prepare("INSERT INTO manualselectionlog
                                VALUES (?,?,?,?,?,?)");
  my $timestamp = strftime("%Y%m%d%H%M%S", gmtime(time()));

  my ($art, $type, $reason, $result, $r1, $r2);

  print << "HERE";
    <center>
    <table class="wikitable">
    <tr>
    <th>#</th>
    <th>Article</th>
    <th>Type</th>
    <th>Reason</th>
    <th>Result</th>
    </tr>
HERE

  my $i;

  for ( $i = 1; $i < $maxadds+1; $i++ ) {
    next unless ( defined $params->{"addart$i"} );
    $art = $params->{"addart$i"};
    $art =~ s/^\s*//;
    $art =~ s/\s*$//;
    next if ( $art eq '');

    $type = $params->{"addtype$i"};
    next unless ( ($type eq 'release' ) || ($type eq 'norelease'));

    $reason = $params->{"addreason$i"};
    $reason =~ s/^\s*//;
    $reason =~ s/\s*$//;

    my $error = "OK";

    $r1 = $sthart->execute($art,$type,$timestamp);


    if ( 1 == $r1 ) { 
      $r2 = $sthlog->execute($art, $type, $timestamp, "add", $user, $reason);
      if ( 1 != $r2 ) { 
        $error = "Failed";
      }
    } else { 
      $error = "Failed";
    }

    print << "HERE";
    <tr>
      <td>$i</td>
      <td>$art</td>
      <td>$type</td>
      <td>$reason</td>
      <td>$error</td>
    </tr>
HERE
  }

  $dbh->commit();

  print << "HERE";
    </table>
HERE

}

############################################################################

sub process_removes {
  my $params = shift;
  my $authenticated = shift;
  my $user = shift;

  if ( $authenticated != 1) { 
    print << "HERE";
    <span class="notauthenticatederror">Error: You must log in to perform this action.</span>

HERE
    return;
  } 

  my $sthart = $dbh->prepare("DELETE FROM manualselection 
                              WHERE ms_article = ?");
  my $sthlog = $dbh->prepare("INSERT INTO manualselectionlog
                                VALUES (?,?,?,?,?,?)");

  my $timestamp = strftime("%Y%m%d%H%M%S", gmtime(time()));

  print << "HERE";
      <table class="wikitable">
       <tr>
        <th>Article</th>
        <th>Type</th>
        <th>Reason</th>
        <th>Result</th>
       </tr>
HERE

  my ($p, $art, $type, $reason, $r1, $r2);
  foreach $p ( keys %{$params} ) {
#    print $p . " &rarr; ".  $params->{$p} . "<br/>";

    next unless ( $p =~ /^key:(.*)$/);
    $art = uri_unescape($1);
    $reason = $params->{"reason:$1"};
    $type = $params->{"type:$1"};

#   print "SEE: " . $art . " '$type' &rarr; ".  $reason . "<br/>";

    my $error = "OK";

    $r1 = $sthart->execute($art);

    if ( $r1 == 1 ) { 
      $r2 = $sthlog->execute($art, $type, $timestamp, 
                                "remove", $user, $reason);
      if ( 1 != $r2) { 

        $error = "Failed step 2 '$art' '$type' ";
     }
    } else { 
      $error = "Failed step 1 '$art' '$type'";
    }

    print << "HERE";
    <tr>
    <td>$art</td>
    <td>$type</td>
    <td>$reason</td>
    <td>$error</td>
    </tr>
HERE

    print "</table>";
  }
}

############################################################################

sub do_add {
  my $params = shift;
  my $show_login = shift;
  my $user = shift;
  my $pass = shift;

  print << "HERE";
    <form action="$url" method="post">
      <input type="hidden" name="user" value="$user">
      <input type="hidden" name="pass" value="$pass">
      <input type="hidden" name="mode" value="processadd">
    <center>
      <table class="wikitable">
       <tr>
        <th>#</th>
        <th>Article</th>
        <th>Type</th>
        <th>Reason</th>
       </tr>
HERE

  my $i;
  my (@arts, @reasons, @types);
  push @arts, "";
  push @types, "";
  push @reasons, "";


  for ( $i = 1; $i < $maxadds+1; $i++) { 
    push @arts, $params->{"addart$i"};
    push @types, $params->{"addtype$i"};
    push @reasons, $params->{"addreason$i"};
  }

 for ( $i = 1; $i < $maxadds+1; $i++ ) { 
    print << "HERE";
    <tr>
    <td>$i</td>
    <td><input type="text" name="addart$i" value="$arts[$i]"></td>
    <td><select name="addtype$i">
          <option value="release">release</option>
           <option value="norelease">norelease</option>
        </select></td>
    <td><input type="text" name="addreason$i" value="$reasons[$i]"></td>
    </tr>
HERE
  }

  print << "HERE";
  <tr>
  <td colspan="3" style="text-align: center;">
HERE

#  if ( $show_login == 1 ) { 
#    print << "HERE"; 
#  <table>
#  <tr><td>User</td><td><input type="text" name="user" ></td></tr> 
#  <tr><td>Password</td>
#     <td><input type="password" name="pass"></td></tr>
#  </table>
#HERE
#  }

  print << "HERE";
    <input type="submit" value="Add articles">
    </td></tr>
    </table></center>
    </form>
HERE

}

############################################################################

sub do_list {
  my $params = shift;

  my $offset = $params->{'offset'} || 0;
  my $farticle = $params->{'farticle'} || "";  
  $farticle =~ s/^\s*//;
  $farticle =~ s/\s*$//;

  my $artenc = uri_escape($farticle);

  my $ftype = $params->{'ftype'};

  my $select = '<select name="ftype">' . "\n";
  $select .= "<option value=\"\">Any</option>\n";
  my $sel;
  my $v;
  foreach $v ( ('release', 'norelease')) { 
    $sel = "";
    if ( $ftype eq $v ) { $sel = 'selected'; }
    $select .= "<option value=\"$v\" $sel>$v</option>\n";
  }
  $select .= "</select>\n";


  print << "HERE";
    <form action="$url" method="post">
    <fieldset class="inner">
    <legend>List articles in the manual selection</legend>
    <input type="hidden" name="mode" value="list">
      Article:&nbsp;<input type="text" name="farticle" value="$artenc">
   <br/>
      Type:&nbsp;$select<br/>
    <div class="submit">
      <input type="submit" value="Filter results">
    </div>
    </fieldset>
    </form>
HERE

  my @qparams;
  
  my $query = "select * from manualselection where ";

  if ( 0 < length $farticle ) { 
    $query .= " ms_article regexp ?";
    push @qparams, $farticle;
  }
 
  if ( ($ftype eq 'release') || ($ftype eq 'norelease') ) { 
    $query .= " and ms_type = ?";
    push @qparams, $ftype;
  }

  # in case no options were selected
  $query =~ s/where $//; 
  $query =~ s/where and/where /;

  $query .= " order by ms_timestamp desc limit ? offset ? ";
  push @qparams, $pagesize;
  push @qparams, $offset;

#  print "Q: '$query'\n";

  my $sth = $dbh->prepare($query);

  my $count = $sth->execute(@qparams);

  if ( $count eq '0E0') { $count = 0; }

  my $poffset = $offset - $pagesize;

  if ( $poffset < 0) { $poffset = 0 };

  my $noffset = $offset + $pagesize;

  print << "HERE";
    <div class="results navbox">
HERE

  if ( $count > 0 ) { 
    print "Showing $count results starting with #" . ($offset + 1) . "<br/>";
  } else { 
    print "No more results<br/>\n";
  }

  if ( $offset > 0 ) { 
    print << "HERE";
    <a href="$url?mode=list&offset=$poffset&farticle=$artenc">&larr; Previous $pagesize</a>&nbsp;&nbsp;
HERE
  }

  if ( $count > 0) { 
    print << "HERE";
      <a href="$url?mode=list&offset=$noffset&farticle=$artenc">Next $pagesize &rarr;</a>
HERE
  }

  print "</div>\n"; 

  if ( $count == 0) { return; }

    print << "HERE";
      <center>
      <form action="$url" method="post">
      <input type="hidden" name="mode" value="processremoves">

      <table class="wikitable">
      <tr>
        <th colspan="4">
      </th>
      </tr>
      <tr>
        <th>Article</th>
        <th>Type</th>
        <th>Timestamp</th>
        <th colspan="2">Remove</th>
     </td>
HERE

  my @row;

  while ( @row = $sth->fetchrow_array() ) { 
    my $link = make_article_link(0, $row[0]);
    my $type = $row[1];
    my $ts = fix_timestamp($row[2]);
    $ts =~ s/T/ /g;
    chop $ts;

    my $key = uri_escape($row[0]);

    print << "HERE";
    <tr>
      <td>$link</td>
      <td><input type="hidden" name="type:$key" value="$type"/>$type</td>
      <td>$ts</td>
      <td><input type="checkbox" name="key:$key"></td>
      <td><input type="text" name="reason:$key"></td>
    </tr>
HERE
  }

  print << "HERE";
    <tr><td colspan="4" style="text-align: right;">
    <input type="submit" value="Remove checked">
    </td></tr>
    </table>
    </form>
    </center>
HERE

}

############################################################################

sub do_log {
  my $params = shift;

  my $offset = $params->{'offset'} || 0;
  my $fuser = $params->{'fuser'} || "";  
  my $farticle = $params->{'farticle'} || "";  
  $fuser =~ s/^\s*//;
  $fuser =~ s/\s*$//;
  $farticle =~ s/^\s*//;
  $farticle =~ s/\s*$//;

  my $artenc = uri_escape($farticle);
  my $userenc = uri_escape($fuser);

print << "HERE";
  <form action="$url" method="post">
  <fieldset class="inner">
  <legend>Show changelog for the manual selection</legend>
  <input type="hidden" name="mode" value="logs">
  Article:&nbsp;<input type="text" name="farticle" value="$artenc"><br/>
  User:&nbsp;<input type="text" name="fuser" value="$userenc"><br/>
  <div class="submit>"
    <input type="submit" value="Filter results">
  </div>
  </fieldset>
  </form>
HERE

  my @qparams;  
  my $query = "select * from manualselectionlog";

  if ( 0 < length $fuser ) { 
    $query .= " where ms_user regexp ? ";
    push @qparams, $fuser;

    if ( 0 < length $farticle ) { 
      $query .= " and ms_article regexp ? ";
      push @qparams, $farticle;
    }
  } else { 
    if ( 0 < length $farticle ) { 
      $query .= " where ms_article regexp ? ";
      push @qparams, $farticle;
    }
  }

  $query .= " order by msl_timestamp desc limit ? offset ? ";
  push @qparams,  $pagesize;
  push @qparams, $offset;

# print "Query: $query<br/>Params: ";
#  print (join "<br/>", @qparams);

  my $sth = $dbh->prepare($query);

  my $r = $sth->execute(@qparams);

  my $message;
  if ( $r eq "0E0" ) { 
    $message = "No more log entries to display";
  } else { 
    my $initial = $offset + 1;
    $message = "showing $r log entries starting with #$initial"
  }

print << "HERE";
<div class="results navbox">
<b>Changelog:</b> $message.
</div>
HERE

  if ( $r eq '0E0' ) { return; }

  print << "HERE";
  <center>
  <table class="wikitable">
   <tr>
    <th>Article</th>
    <th>Type</th>
    <th>Timestamp</th>
    <th>Action</th>
    <th>User</th>
    <th>Reason</th>
   </td>
HERE

  my @row;

  while ( @row = $sth->fetchrow_array() ) { 
    my $link = make_article_link(0, $row[0]);
    my $type = $row[1];
    my $ts = fix_timestamp($row[2]);

    $ts =~ s/T/ /g;
    chop $ts;

    print << "HERE";
  <tr>
    <td>$link</td>
    <td>$type</td>
    <td>$ts</td>
    <td>$row[3]</td>
    <td>$row[4]</td>
    <td>$row[5]</td>
  </tr>
HERE
  }

  print << "HERE";
    </table>
    </center>
HERE

  my $poffset = $offset - $pagesize;

  if ( $poffset < 0) { $poffset = 0 };

  my $noffset = $offset + $pagesize;

  if ( $offset > 0 ) { 
    print << "HERE";
     <a href="$url?mode=logs&offset=$poffset&farticle=$artenc&fuser=$userenc">&larr; Previous $pagesize</a>&nbsp;&nbsp;
HERE
  }

  if ( $r eq $pagesize) { 
    print << "HERE";
      <a href="$url?mode=logs&offset=$noffset&farticle=$artenc&fuser=$userenc">Next $pagesize &rarr;</a>
    </div>
HERE
  }
}

############################################################################

sub check_auth { 
  my $user = shift;
  my $pass = shift;

  if ( ! $user =~ /./ ) { 
    return 0;
  }

  my $md5sum = Digest::MD5->new();
  $md5sum->add($user);
  $md5sum->add($pass);
  
  my $d = $md5sum->hexdigest();

  my $sth = $dbh->prepare("SELECT pw_password FROM passwd WHERE pw_user = ?");
  my $r = $sth->execute($user);

  if ( $r == 0) { 
    return -1;
  }

  my @res = $sth->fetchrow_array();
  if ( $res[0] eq $d ) {
    return 1;
  } else {
    return -2;
  }
}

##################################################################

sub auth_form_manual { 
  my $user = shift;
  my $value = shift;
  $user = uri_escape($user);
  $value = uri_escape($value);  

  print << "HERE";
  <form action="$url" method="post">
  <fieldset class="inner">
  <legend>Manual selection login</legend>
  <input type="hidden" name="mode" value="processlogin">
  User:&nbsp;<input type="text" name="user" value="$user"><br/>
  Password:&nbsp;<input type="password" name="pass" value="$value"><br/>
  <div class="manual">
    <input type="submit" value="Log in">
  </div>
  </fieldset>
  </form>
HERE
}
