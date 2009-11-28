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
my $pagesize = 5;

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
You are not logged in.
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

layout_footer();
exit;


############################################################################

sub processlogin {
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
  print "<h2>Processing added articles</h2><br/>\n";

  if ( $authenticated != 1 ) { 
    print << "HERE";
    <span class="notauthenticatederror">Action not performed: You must log in to perform this action.</span>

HERE
    do_add(1);
    return;
  }

  my $dbh = db_connect_rw($Opts);
  my $sthart = $dbh->prepare("INSERT INTO manualselection VALUES (?,?)");
  my $sthlog = $dbh->prepare("INSERT INTO manualselectionlog
                                VALUES (?,?,?,?,?)");
  my $timestamp = strftime("%Y%m%d%H%M%S", gmtime(time()));

  my ($art, $reason, $result, $r1, $r2);

  print << "HERE";
<center>
<table class="wikitable">
<tr>
<th>#</th>
<th>Article</th>
<th>Reason</th>
<th>Result</th>
</tr>
HERE

  my $i;

  for ( $i = 1; $i < $maxadds+1; $i++ ) {
    next unless ( defined $param{"addart$i"} );
    $art = $param{"addart$i"};
    $art =~ s/^\s*//;
    $art =~ s/\s*$//;
    next if ( $art eq '');
    $reason = $param{"addreason$i"};
    $reason =~ s/^\s*//;
    $reason =~ s/\s*$//;

    my $error = "OK";

    $r1 = $sthart->execute($art,$timestamp);

    if ( 1 == $r1 ) { 
      $r2 = $sthlog->execute($art, $timestamp, "add", $user, $reason);
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
  print "<h2>Processing removed articles</h2><br/>\n";

  if ( $authenticated != 1) { 
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
      <table class="wikitable">
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

    my $error = "OK";

    $r1 = $sthart->execute($art);

    if ( $r1 == 1 ) { 
      $r2 = $sthlog->execute($art, $timestamp, "remove", $user, $reason);
      if ( 1 != $r2) { 
        $error = "Failed";
     }
    } else { 
      $error = "Failed";
    }

    print << "HERE";
    <tr>
    <td>$art</td>
    <td>$reason</td>
    <td>$error</td>
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
    <center>
      <table class="wikitable">
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
  </table></center>
</form>
HERE

}

############################################################################

sub do_list {

  $dbh  = db_connect($Opts);

  my $offset = $param{'offset'} || 0;
  my $farticle = $param{'farticle'} || "";  
  $farticle =~ s/^\s*//;
  $farticle =~ s/\s*$//;

  my $artenc = uri_escape($farticle);

  print << "HERE";
    <form action="$url" method="post">
    <fieldset class="manual">
    <legend>List articles in the manual selection</legend>
    <input type="hidden" name="mode" value="list">
      Article:&nbsp;<input type="text" name="farticle" value="$artenc">
    <input type="submit" value="Filter results">
    </fieldset>
    </form>
HERE

  my @params;
  
  my $query = "select * from manualselection ";

   if ( 0 < length $farticle ) { 
     $query .= " where ms_article regexp ? ";
     push @params, $farticle;
   }

  $query .= " order by ms_timestamp desc limit ? offset ? ";
  push @params, $pagesize;
  push @params, $offset;

  my $sth = $dbh->prepare($query);

  my $count = $sth->execute(@params);

  if ( $count eq '0E0') { $count = 0; }

  my $poffset = $offset - $pagesize;

if ( $poffset < 0) { $poffset = 0 };

my $noffset = $offset + $pagesize;


print << "HERE";
<div class="results navbox">
HERE

if ( $count > 0 ) { 
  print "Showing $count results starting with #$offset<br/>";
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


}

############################################################################

sub do_log {

  my $offset = $param{'offset'} || 0;
  my $fuser = $param{'fuser'} || "";  
  my $farticle = $param{'farticle'} || "";  
  $fuser =~ s/^\s*//;
  $fuser =~ s/\s*$//;
  $farticle =~ s/^\s*//;
  $farticle =~ s/\s*$//;

  my $artenc = uri_escape($farticle);
  my $userenc = uri_escape($fuser);

print << "HERE";
  <form action="$url" method="post">
  <fieldset class="manual">
  <legend>Show changelog for the manual selection</legend>
  <input type="hidden" name="mode" value="logs">
  Article:&nbsp;<input type="text" name="farticle" value="$artenc"><br/>
  User:&nbsp;<input type="text" name="fuser" value="$userenc"><br/>
  <input type="submit" value="Filter results">
  </fieldset>
  </form>
HERE

  $dbh  = db_connect($Opts);


  my @params;
  
  my $query = "select * from manualselectionlog";

  if ( 0 < length $fuser ) { 
    $query .= " where ms_user regexp ? ";
    push @params, $fuser;

    if ( 0 < length $farticle ) { 
      $query .= " and ms_article regexp ? ";
      push @params, $farticle;
    }
  } else { 
    if ( 0 < length $farticle ) { 
      $query .= " where ms_article regexp ? ";
      push @params, $farticle;
    }
  }

  $query .= " order by ms_timestamp desc limit ? offset ? ";
  push @params,  $pagesize;
  push @params, $offset;

# print "Query: $query<br/>Params: ";
#  print (join "<br/>", @params);

  my $sth = $dbh->prepare($query);

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
  <a href="$url?mode=logs&offset=$poffset&farticle=$artenc&fuser=$userenc">&larr; Previous $pagesize</a>&nbsp;&nbsp;
HERE

}

print << "HERE";
  <a href="$url?mode=logs&offset=$noffset&farticle=$artenc&fuser=$userenc">Next $pagesize &rarr;</a>
</div>
HERE


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

sub layout_header_manual {
  my $subtitle = shift;

  $App = "Manual selection maintenance";
  my $App2 = "Wikipedia Release Version Data";

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
<div class="superhead">
<a href="http://toolserver.org">
  <img id="poweredbyicon" alt="Powered by Wikimedia Toolserver" 
       src="http://toolserver.org/images/wikimedia-toolserver-button.png"/>
</a>    
<a href="index.html">$App2</a>
</div>
<div class="head">
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

<div class="content content-manual">
HERE

}

##################################################################

sub auth_form_manual { 
  print << "HERE";
  <form action="$url" method="post"><br/>
  <fieldset class="manual">
  <legend>Log in</legend>
  <input type="hidden" name="mode" value="processlogin">
  User:&nbsp;<input type="text" name="user" value="$user"><br/>
  Password:&nbsp;<input type="password" name="pass" value="$value"><br/>
   <input type="submit" value="Log in">
   </fieldset>
   </form>
HERE
}
