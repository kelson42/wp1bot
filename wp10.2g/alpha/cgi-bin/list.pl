#!/usr/bin/perl

# WP 1.0 bot - second generation
# CGI to display table of ratings information
# 

use lib '/home/veblen/VeblenBot';

use strict;
use Data::Dumper;

use DBI;
use CGI;
use CGI::Carp qw(fatalsToBrowser);

my $cgi = new CGI;
my %param = %{$cgi->Vars()};

print CGI::header(-type=>'text/html', -charset=>'utf-8');      

my $proj = $param{'project'} || $ARGV[0];

my $pw = `/home/veblen/pw-db.sh`;

my $dbh = DBI->connect('DBI:mysql:wp10', 'wp10user', $pw)
                or die "Couldn't connect to database: " . DBI->errstr;

html_header();
my $projects = {};
query_form(\%param);
ratings_table(\%param);
html_footer();
exit;

#######################

sub ratings_table { 
  my $params = shift;

  my $project = $params->{'project'};

  return if ( ! defined $project);

  if ( ! defined $projects->{$project}) { 
    print "Project '$project' not available\n";
    return;
  }

  my $limit = $params->{'limit'} || 10;
  if ( $limit > 50 ) { $limit = 50;}

  my $offset = $params->{'offset'} || 0;

  if ( $offset > 0 ) { $offset --; }

  my $query = "SELECT * FROM ratings WHERE r_project = ?";
  my $queryc = "SELECT count(r_article) FROM ratings WHERE r_project = ?";
  my @qparam = ($project);
  my @qparamc = ($project);

  my $quality = $params->{'quality'};

  if ( defined $quality && $quality =~ /\w|\d/) {
    $query .= " AND r_quality = ?";
    $queryc .= " AND r_quality = ?";
    push @qparam, $quality;
    push @qparamc, $quality;
  }


  my $importance =  $params->{'importance'};

  if ( defined $importance && $importance =~ /\w|\d/) {
    $query .= " AND r_importance = ?";
    $queryc .= " AND r_importance = ?";
    push @qparam, $importance;
    push @qparamc, $importance;
  }

  $query .= " LIMIT ?";
  push @qparam, $limit;

  $query .= " OFFSET ?";
  push @qparam, $offset;

#  print "Q: $query<br/>\n";
#  print "Params:" . Dumper(@qparam). "<br/>\n";

  my $sthcount = $dbh->prepare($queryc);
  $sthcount->execute(@qparamc);
  my @row = $sthcount->fetchrow_array()	;

  print "<p><b>Total results: " . $row[0] 
        . "</b>.<br/> Displaying $limit results beginning with #" 
        . ($offset +1) . "</p><hr/>\n";


  my $sth = $dbh->prepare($query);

  my $c = $sth->execute(@qparam);

  my $i = $offset;

  print "<table border=1>\n";
  while ( @row = $sth->fetchrow_array ) {
    $i++;
    print "<tr><td>$i</td><td>";
    print join "</td><td>", @row;
    print "</td></tr>\n";
  }
  print "</table>\n";
}

#################################

sub query_form {
  my $params = shift;

  my @row;

  my $sth = $dbh->prepare("SELECT p_project FROM projects");
  $sth->execute();

  while ( @row = $sth->fetchrow_array ) { 
    $projects->{$row[0]} = 1;
  }

  my $quality = $params->{'quality'} || "";
  my $importance = $params->{'importance'} || "";
  my $limit = $params->{'limit'} || "20";
  my $offset = $params->{'offset'} || "1";


  print "<form><table>\n";
  print "<tr><td>Project</td><td><select name=\"project\">\n";

  my $p;
  foreach $p ( sort { $a cmp $b} keys %$projects) { 
   print "<option value=\"" . $p . "\">" . $p ."</option>\n";
  }


  print << "HERE";
  </select></td></tr>
 
  <tr><td>Quality</td>
      <td><input type="text" value="$quality" name="quality"/></td></tr>
  <tr><td>Importance</td>
      <td><input type=\"text\" value="$importance" name="importance"/></td></tr>
  <tr><td>Results per page</td>
      <td><input type="text" value="$limit" name="limit"/></td></tr>
  <tr><td>Start with result</td>
      <td><input type="text" value="$offset" name="offset"/></td></tr>
  <tr><td></td>
     <td><input type="submit" value="Make list"/></td></tr>
  </table></form>
  <hr/>
HERE

}

##############


sub html_header { 
print << "HERE";
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en" dir="ltr">
  <head>
  <base href="http://en.wikipedia.org">
  <style type="text/css" media="screen, projection">/*<![CDATA[*/
    \@import url("http://en.wikipedia.org/skins-1.5/common/shared.css?162");
    \@import url("http://en.wikipedia.org/skins-1.5/simple/main.css?162");
    \@import url("/w/index.php?title=MediaWiki:Common.css&usemsgcache=yes&action=raw&ctype=text/css&smaxage=2678400");
    \@import url("/w/index.php?title=MediaWiki:Monobook.css&usemsgcache=yes&action=raw&ctype=text/css&smaxage=2678400");

		/*]]>*/</style>
  </head>
  <body>
HERE

}

######################33

sub html_footer { 
print << "HERE";
  </body>
</html>
HERE
}
