#!/usr/bin/perl

my $url = "http://localhost/~veblen/cgi-bin/wp10.2g/cgi-bin/manualsel.pl";
my $App = "Manual selection maintenance";

# manualsel.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for more information

use strict;
use Encode;
use URI::Escape;
use Digest::MD5;
use Data::Dumper;
use DBI;
use POSIX 'strftime';
use URI::Escape;

my $maxadds = 10;
my $pagesize = 2;

require 'read_conf.pl';
our $Opts = read_conf();

require 'layout.pl';

require 'database_www.pl';

use CGI ':standard';
CGI::Carp->import('fatalsToBrowser');

my $cgi = new CGI;
my %param = %{$cgi->Vars()};

my $pass = $param{'pass'} || CGI::cookie('wp10pass');
my $user = $param{'user'} || CGI::cookie('wp10user');
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

our $dbh;

if ( $authenticated == 1) { 
  $value = $pass;
  $authline = << "HERE";
<div class="authline loggedin">
<img src="http://upload.wikimedia.org/wikipedia/commons/4/4d/Lock-open.png">
You are logged in as <b>$user</b>.
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
You are not logged in ('$ua', '$pa').
</div>
HERE

  $logincookiepass = CGI::cookie(-name => 'wp10user',
                       -value => "", -path=>"/");
  $logincookieuser = CGI::cookie(-name => 'wp10pass',
                       -value => "", -path=>"/");
}

print CGI::header(-type=>'text/html', -charset=>'utf-8', -cookie=>[$logincookiepass,$logincookieuser]);

my $mode = $param{'mode'};

if ( $mode eq 'add' ) {
  layout_header_manual("Add articles");
  print($authline);
  do_add();
} elsif ( $mode eq 'processadd' ) {
  layout_header_manual("Add articles");
  print($authline);
  process_add();
} elsif ( $mode eq 'processremoves' ) {
  layout_header_manual("List manual selection");
  print($authline);
  process_removes();
} elsif ( $mode eq 'logs' ) { 
  layout_header_manual("Changelog");
  print($authline);
  do_log();
} elsif ( $mode eq 'login' ) { 
  layout_header_manual("Log in");
  print($authline);
  auth_form_manual();
} elsif ( $mode eq 'processlogin' ) { 
  layout_header_manual("Log in");
  print($authline);
  processlogin();
} else { 
  layout_header_manual("List manual selection");
  print($authline);
  do_list();
}

exit;


############################################################################

sub processlogin {
  if( $authenticated == 1) { 
    print "<b>Login successful</b>";
  }   else  {
    print "<b>Login unsuccessful; try again</b>";
    auth_form_manual();
  }
 print "<div class=\"clear\">&nbsp;</div>\n";
}

############################################################################

sub process_add {
  print "<h2>Processing added articles</h2><br/>\n";

  if ( $authenticated == 0) { 
    print << "HERE";
    <span class="notauthenticatederror">Error: You must log in to perform this action.</span>

HERE
    do_add(1);
    return;
  }

  my $dbh = db_connect_rw($Opts);
  my $sthart = $dbh->prepare("INSERT INTO manualselection VALUES (?,?)");
  my $sthlog = $dbh->prepare("INSERT INTO manualselectionlog
                                VALUES (?,?,?,?,?)");
print "Here 4\n";

  my $timestamp = strftime("%Y%m%d%H%M%S", gmtime(time()));

  my ($art, $reason, $result, $r1, $r2);

  print "<table border=\"1\">";
  my $i;

  for ( $i = 1; $i < $maxadds+1; $i++ ) {
  print "$i<br/>\n";
    next unless ( defined $param{"addart$i"} );
    $art = $param{"addart$i"};
#  $art =~ s/^\s*//;
#  $art =~ s/\s*$//;
    next if ( $art eq '');
    $reason = $param{"addreason$i"};

    $r1 = $sthart->execute($art,$timestamp);
    $r2 = $sthlog->execute($art, $timestamp, "add", $user, $reason);


    print << "HERE";
    <tr>
      <td>$i</td>
      <td>$art</td>
      <td>$reason</td>
       <td>$r1, $r2</td>
    </tr>
HERE
  }

$dbh->commit();

print << "HERE";
</table>
</body>
</html>
HERE

}


############################################################################

sub process_removes {
  print "<h2>Processing removed articles</h2><br/>\n";

  if ( $authenticated == 0) { 
    print << "HERE";
    <span class="notauthenticatederror">Error: You must log in to perform this action.</span>

HERE
    return;
  } 


  my $dbh = db_connect_rw($Opts);
  my $sthart = $dbh->prepare("DELETE FROM manualselection 
                              WHERE ms_article = ?");
  my $sthlog = $dbh->prepare("INSERT INTO manualselectionlog
                                VALUES (?,?,?,?,?)");

  my $timestamp = strftime("%Y%m%d%H%M%S", gmtime(time()));


  print << "HERE";
      <table border="1">
       <tr>
        <th>Article</th>
        <th>Reason</th>
       </tr>
HERE

  my ($p, $art, $reason, $r1, $r2);
  foreach $p ( keys %param ) {
    print $p . " &rarr; ".  $param{$p} . "<br/>";

    next unless ( $p =~ /^key:(.*)$/);
    $art = uri_unescape($1);
    $reason = $param{"reason:$1"};

    print "SEE: " . $art . " &rarr; ".  $reason . "<br/>";
    $r1 = $sthart->execute($art);
    $r2 = $sthlog->execute($art, $timestamp, "remove", $user, $reason);

    print << "HERE";
    <tr>
    <td>$art</td>
    <td>$reason</td>
    <td>$r1, $r2</td>
    </tr>
HERE

print "</table>";

  }
}

############################################################################

sub do_add {

  my $show_login = shift;

  print "<h2>Add articles to the manual selection</h2><br/>\n";

  print << "HERE";
    <form action="$url">
      <input type="hidden" name="user" value="$user">
      <input type="hidden" name="pass" value="$pass">
      <input type="hidden" name="mode" value="processadd">
      <table border="1">
       <tr>
        <th>#</th>
        <th>Article</th>
        <th>Reason</th>
       </tr>
HERE

  my $i;
  my (@arts, @reasons);
  push @arts, "";
  push @reasons, "";

  for ( $i = 1; $i < $maxadds+1; $i++) { 
    push @arts, $param{"addart$i"};
    push @reasons, $param{"addreason$i"};
  }

 for ( $i = 1; $i < $maxadds+1; $i++ ) { 
    print << "HERE";
    <tr>
    <td>$i</td>
    <td><input type="text" name="addart$i" value="$arts[$i]"></td>
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
  </table></form></body></html>
HERE

}

############################################################################

sub do_list {
  print "<h2>List articles in the manual selection</h2><br/>\n";

  $dbh  = db_connect($Opts);


  my $offset = $param{'offset'} || 0;
  
  my $query = <<"HERE";
    select * from manualselection 
    order by ms_timestamp desc limit ? offset ? 
HERE
#    limit 100 offset ?

  my $sth = $dbh->prepare($query);

my @params = ( $pagesize, $offset );

#  $sth->execute();
  $sth->execute(@params);
#  $sth->execute($offset);

  print << "HERE";
<center>
<form action="$url" method="post">
<input type="hidden" name="mode" value="processremoves">

  <table class="wikitable">
   <tr>
    <th>Article</th>
    <th>Timestamp</th>
    <th colspan="2">Remove</th>
   </td>
HERE

  my @row;

  while ( @row = $sth->fetchrow_array() ) { 
    my $link = make_article_link(0, $row[0]);
    my $ts = fix_timestamp($row[1]);
    $ts =~ s/T/ /g;
    chop $ts;

    my $key = uri_escape($row[0]);

    print << "HERE";
  <tr>
    <td>$link</td>
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


my $poffset = $offset - $pagesize;

if ( $poffset < 0) { $poffset = 0 };

my $noffset = $offset + $pagesize;

if ( $offset > 0 ) { 
print << "HERE";
  <a href="$url?mode=list&offset=$poffset">&larr; Previous 2</a>&nbsp;&nbsp;
HERE

}

print << "HERE";
  <a href="$url?mode=list&offset=$noffset">Next 2 &rarr;</a>
</div></body></html>
HERE


}

############################################################################

sub do_log {
  print "<h2>Show changelog for the manual selection</h2><br/>\n";

  $dbh  = db_connect($Opts);

  my $offset = $param{'offset'} || 0;
  
  my $query = <<"HERE";
    select * from manualselectionlog
    order by ms_timestamp desc limit ? offset ? 
HERE

  my $sth = $dbh->prepare($query);

  my @params = ( $pagesize, $offset );

  $sth->execute(@params);

  print << "HERE";
  <center>
  <table class="wikitable">
   <tr>
    <th>Article</th>
    <th>Timestamp</th>
    <th>Action</th>
    <th>User</th>
    <th>Reason</th>
   </td>
HERE

  my @row;

  while ( @row = $sth->fetchrow_array() ) { 
    my $link = make_article_link(0, $row[0]);
    my $ts = fix_timestamp($row[1]);

    $ts =~ s/T/ /g;
    chop $ts;

    print << "HERE";
  <tr>
    <td>$link</td>
    <td>$ts</td>
    <td>$row[2]</td>
    <td>$row[3]</td>
    <td>$row[4]</td>
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
  <a href="$url?mode=logs&offset=$poffset">&larr; Previous 2</a>&nbsp;&nbsp;
HERE

}

print << "HERE";
  <a href="$url?mode=logs&offset=$noffset">Next 2 &rarr;</a>
</div></body></html>
HERE


}

############################################################################


sub check_auth { 
  my $user = shift;
  my $pass = shift;

  my $users = { 'CBM' => 'fbbe7e01ed8b949d214a0734b7c7e46b' };

  my $md5sum = Digest::MD5->new();

  $md5sum->add($user);
  $md5sum->add($pass);
  
  my $d = $md5sum->hexdigest();

  if ( $users->{$user} eq $d ) {
    return 1;
  } else {
    return 0;
  }
}

##################################################################

sub layout_header_manual {
  my $subtitle = shift;

  $App = "Manual selection maintenance";

  my $stylesheet = $Opts->{'wp10.css'}
    or die "Must specify configuration value for 'wp10.css'\n";

  my $usableforms = $Opts->{'usableforms.js'}
    or die "Must specify configuration value for 'usableforms.js'\n";
  
  print << "HERE";
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" 
          "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr">
<head>
  <base href="http://en.wikipedia.org">
  <title>$subtitle - $App</title>
  <style type="text/css" media="screen">
     \@import "$stylesheet";
  </style>
<script type="text/javascript"  src="$usableforms"></script>
<script type="text/javascript"  src="http://toolserver.org/~cbm/foo.js"></script>
</head>
<body>
<div class="head">
<a href="http://toolserver.org">
  <img id="poweredbyicon" alt="Powered by Wikimedia Toolserver" 
       src="http://toolserver.org/images/wikimedia-toolserver-button.png"/>
</a>    
$App
</div>
<div class="subhead">
HERE

print "<!-- '$subtitle' -->\n";

if ( $subtitle eq "List manual selection" ) { 
  print "<span class=\"selectedtool\"><a href=\"$url?mode=list\">" 
      . "List manual selection</a></span> &middot; \n";
} else {
  print "<a href=\"$url?mode=list\">List manual selection</a> &middot; \n";
}

if ( $subtitle eq "Add articles" ) { 
  print "<span class=\"selectedtool\"><a href=\"$url?mode=add\">" 
      . "Add articles</a></span> &middot; \n";
} else {
  print "<a href=\"$url?mode=add\">Add articles</a> &middot; \n";
}

if ( $subtitle eq "Changelog" ) { 
  print "<span class=\"selectedtool\"><a href=\"$url?mode=logs\">" 
      . "Changelog</a></span> &middot; \n";
} else {
  print "<a href=\"$url?mode=logs\">Changelog</a> &middot; \n";
}


if ( $subtitle eq "Log in" ) { 
  print "<span class=\"selectedtool\"><a href=\"$url?mode=login\">" 
      . "Log in</a></span> \n";
} else {
  print "<a href=\"$url?mode=login\">Log in</a> \n";
}

print << "HERE";
</div>

<div class="content">
HERE

}

##################################################################

sub auth_form_manual { 
  print << "HERE";
  <div class="auth auth$authenticated">
  <h2>Log in</h2>
  <div class="loginform">
  <form action="$url" method="post"><br/>
  <input type="hidden" name="mode" value="processlogin">
  <table>
    <tr><td>
     User</td><td><input type="text" name="user" value="$user"></td></tr>
    <tr><td>
     Password
   </td><td><input type="password" name="pass" value="$value"></td></tr>
   <tr><td colspan="2" style="text-align: right;">
   <input type="submit" value="Login">
    </td></tr></table>
   </form>
   </div>
  </div>
HERE
}
