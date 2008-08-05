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

#  print Dumper($params);
#  print "<hr/>\n";

  my $projecta = $params->{'projecta'};

  return if ( ! defined $projecta);

  my $projectb = $params->{'projectb'};

  return if ( ! defined $projectb);

  if ( ! defined $projects->{$projecta}) { 
    print "Project '$projecta' not available\n";
    return;
  }

  if ( ! defined $projects->{$projectb}) { 
    print "Project '$projectb' not available\n";
    return;
  }

  my $limit = $params->{'limit'} || 10;
  if ( $limit > 50 ) { $limit = 50;}

  my $offset = $params->{'offset'} || 0;

  if ( $offset > 0 ) { $offset --; }


  my $query = "SELECT ra.r_article, ra.r_quality, ra.r_importance, rb.r_quality, rb.r_importance ". 
              "  FROM ratings as ra join ratings as rb on rb.r_article = ra.r_article" . 
              " WHERE ra.r_project = ? AND rb.r_project = ?";
  my $queryc = "SELECT count(ra.r_article) FROM ratings as ra join ratings as rb on rb.r_article = ra.r_article" . 
              " WHERE ra.r_project = ? AND rb.r_project = ?";

  my @qparam = ($projecta, $projectb);
  my @qparamc = ($projecta, $projectb);

  my $quality = $params->{'quality'};

  if ( defined $quality && $quality =~ /\w|\d/) {
    $query .= " AND ra.r_quality = ?";
    $queryc .= " AND ra.r_quality = ?";
    push @qparam, $quality;
    push @qparamc, $quality;
  }

  my $importance =  $params->{'importance'};

  if ( defined $importance && $importance =~ /\w|\d/) {
    $query .= " AND ra.r_importance = ?";
    $queryc .= " AND ra.r_importance = ?";
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
        . "</b>.<br/> Displaying up to $limit results beginning with #" 
        . ($offset +1) . "</p><hr/>\n";


  my $sth = $dbh->prepare($query);

  my $c = $sth->execute(@qparam);

  my $i = $offset;

  print << "HERE";
<table class="wikitable">
<tr>
  <td><b>Result</b></td>
  <td><b>Article</b></td>
  <td colspan="2"><b>$projecta</b></td>
  <td colspan="2"><b>$projectb</b></td>
</tr>
HERE
     
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


  my $projecta = $params->{'projecta'} || 'Mathematics';
  my $projectb = $params->{'projectb'} || 'Computer science';

  print "<h1>Demo: intersect assessments for two categories</h1>\n";

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

  print "<tr><td colspan=\"2\"><b>List articles matching:</b></td></tr>\n";

  print "<tr><td>Project A</td><td><select name=\"projecta\">\n";

  my $p;
  foreach $p ( sort { $a cmp $b} keys %$projects) { 
    if ( $p eq $projecta ) { 
      print "<option value=\"" . $p . "\" selected>" . $p ."</option>\n";
    } else { 
      print "<option value=\"" . $p . "\">" . $p ."</option>\n";
    }
  }
  print "</select></td></tr>\n";

  print << "HERE";
  <tr><td>Quality</td>
      <td><input type="text" value="$quality" name="quality"/></td></tr>
  <tr><td>Importance</td>
      <td><input type=\"text\" value="$importance" name="importance"/></td></tr>
  <tr><td>Results per page</td>
      <td><input type="text" value="$limit" name="limit"/></td></tr>
  <tr><td>Start with result #</td>
      <td><input type="text" value="$offset" name="offset"/></td></tr>
  <tr><td></td>
HERE

  print "<tr><td colspan=\"2\"><b>That are also assessed by:</b></td></tr>\n";
  print "<tr><td>Project B</td><td><select name=\"projectb\">\n";

  my $p;
  foreach $p ( sort { $a cmp $b} keys %$projects) { 
    if ( $p eq $projectb ) { 
      print "<option value=\"" . $p . "\" selected>" . $p ."</option>\n";
    } else { 
      print "<option value=\"" . $p . "\">" . $p ."</option>\n";
    }
  }
  print "</select></td></tr>\n";


print << "HERE";
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
