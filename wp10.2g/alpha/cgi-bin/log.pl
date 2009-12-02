#!/usr/bin/perl

# log.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for additional information

=head1 SYNOPSIS

CGI program to display assessment logs

=cut

use strict;
use Encode;
use URI::Escape;

require 'read_conf.pl';
our $Opts = read_conf();

my $logurl = $Opts->{'log-url'};

require 'database_www.pl';
require 'layout.pl';

require CGI;
require CGI::Carp; 
CGI::Carp->import('fatalsToBrowser');

use Date::Parse 'strptime';

require DBI;
require POSIX;
POSIX->import('strftime');

my $cgi = new CGI;
my %param = %{$cgi->Vars()};

if ( $param{'limit'} > 1000 ) { 
  $param{'limit'} = 1000;
}

my $p;
my $logFile = "log." . time() . "." . $$;
my $logEntry = $logFile;

foreach $p ( keys %param ) { 
  $param{$p} =~ s/^\s*//;
  $param{$p} =~ s/\s*$//;
  $logEntry .= "&" . uri_escape($p) . "=" . uri_escape($param{$p});
}

if ( defined $Opts->{'log-dir'} 
     && -d $Opts->{'log-dir'} ) { 
  open LOG, ">", $Opts->{'log-dir'} . "/" . $logFile;
  print LOG $logEntry . "\n";
  close LOG;
}

my $proj = $param{'project'} || $ARGV[0];

our $dbh = db_connect_rw($Opts); # Needs r-w access for the cache

print CGI::header(-type=>'text/html', -charset=>'utf-8');      

layout_header("Assessment logs");

my $projects = list_projects($dbh);
query_form(\%param, $projects);

print "<!-- HERE -->\n";

if ( ! defined $param{'entry'} || 1 ) { 
  log_table(\%param, $projects);
}

layout_footer();

exit;
###########################################################################

sub log_table { 
   my $params = shift;
   my $projects = shift;
  
   my ($project, $pagename, $oldrating, $newrating , 
       $pagenameWC, $offset, $limit, $ns, $newerthan, $olderthan);
  
   $project = $params->{'project'} || "";
   $pagename = $params->{'pagename'} || "";
   $ns = $params->{'ns'} || "";

   $oldrating = $params->{'oldrating'} || "";
   $newrating = $params->{'newrating'} || "";
   $pagenameWC = $params->{'pagenameWC'} || 0;
   $offset = $params->{'offset'} || 1;
   $limit = $params->{'limit'} || 1000;
   $newerthan = $params->{'newerthan'} || "";
   $olderthan = $params->{'olderthan'} || "";

   my $olderthandate =   format_date($olderthan);
   my $newerthandate =   format_date($newerthan);
  
   if ( $offset > 0) { $offset--; }
   if ( $limit > 1000 ) { $limit = 1000; } 
   if ( $oldrating =~ /\w|\d/ && ! $oldrating =~ /-Class/) { 
     $oldrating .= "-Class";
   }
  
   if ( $newrating =~ /\w|\d/ && ! $newrating =~ /-Class/) { 
     $newrating .= "-Class";
   }
  
   if ( (! $project =~ /\w|\d/) && (! $pagename =~ /\w|\d/ ) ) { 
     return;
#     print "No projct!\n";
   }
  
   my @qparam;
   my @qparamc;
  
   my $queryc = 'SELECT count(l_article) FROM logging ';

   my $query = << "HERE";
 SELECT l_project, l_article, l_action, l_timestamp, 
        l_old, l_new, l_revision_timestamp, l_namespace
 FROM logging
HERE
	  
   $query .= " WHERE ";
   $queryc .= " WHERE ";
  
   if ( $project =~ /\w|\d/ ) { 
     if ( defined $projects->{$project} ) { 
       $query .= " l_project = ?";
       $queryc .= " l_project = ?";
       push @qparam, $project;
       push @qparamc, $project;
     } else { 
       print << "HERE";
         <div class="navbox">
          Project '$project' is not in the database.
        </div>
HERE
       return;
     }
   }
  
   if ( $olderthandate =~ /\w|\d/ ) {
     $query .=  " AND l_revision_timestamp <= ?";
     $queryc .= " AND l_revision_timestamp <= ?";
     push @qparam, $olderthandate;
     push @qparamc, $olderthandate;
   }

   if ( $newerthandate =~ /\w|\d/ ) {
     $query .=  " AND l_revision_timestamp >= ?";
     $queryc .= " AND l_revision_timestamp >= ?";
     push @qparam, $newerthandate;
     push @qparamc, $newerthandate;
   }

   if ( $oldrating =~ /\w|\d/) {
     # 'Assessed' is a magic word that means "not unassessed".
     if ( $oldrating eq 'Assessed-Class' ) { 
       $query .= " AND NOT l_old = 'Unassessed-Class'";
       $queryc .= " AND NOT l_old = 'Unassessed-Class'";
     } else { 
       $query .= " AND l_old = ?";
       $queryc .= " AND l_old = ?";
       push @qparam, $oldrating;
       push @qparamc, $oldrating;
     }
   }
  
   if ( $newrating =~ /\w|\d/) {
     # 'Assessed' is a magic word that means "not unassessed".
     if ( $newrating eq 'Assessed-Class' ) { 
       $query .= " AND NOT l_old = 'Unassessed-Class'";
       $queryc .= " AND NOT l_old = 'Unassessed-Class'";
     } else { 
       $query .= " AND l_new = ?";
       $queryc .= " AND l_new = ?";
       push @qparam, $newrating;
       push @qparamc, $newrating;
     }
   }

   if ( defined $pagename and $pagename =~ /\w|\d/ ) { 
     if ( $params->{'pagenameWC'} eq 'on' ) { 
       $query .= " AND l_article REGEXP ?";
       $queryc .= " AND l_article REGEXP ?";
       push @qparam, $pagename;
       push @qparamc, $pagename;
     } else { 
       $query .= " AND l_article = ?";
       $queryc .= " AND l_article = ?";
       push @qparam, $pagename;
       push @qparamc, $pagename;
     }
   }

   if ( defined $ns && $ns =~/\d/) { 
     $query .= " AND l_namespace = ? ";
     $queryc .= " AND l_namespace = ? ";
     push @qparam, $ns;
     push @qparamc, $ns;
   }

   $query .= " ORDER BY l_revision_timestamp DESC, l_article";
  
   $query .= " LIMIT ?";
   push @qparam, $limit;
  
   $query .= " OFFSET ?";
   push @qparam, $offset;
 
   # clean up the SQL for edge cases 
   $query =~ s/WHERE\s*AND/WHERE /;
   $queryc =~ s/WHERE\s*AND/WHERE /;
  
   $query =~ s/WHERE\s*ORDER/ORDER/;
   $queryc =~ s/WHERE\s*ORDER/ORDER/;  
   $queryc =~ s/WHERE\s*$//;

#   print "<pre>Q:\n$queryc</pre>\n";
#   my @lparam = @qparamc;
#   print join "<br/>", map { $_ = "'" . $_ . "'" } @lparam;

  my $sthcount = $dbh->prepare($queryc);
  my $res = $sthcount->execute(@qparamc);
  	
#  print "<br/>Res: $res <br/>\n";

  my @row = $sthcount->fetchrow_array() ;
#  print join "<br/>", map { $_ = "'" . $_ . "'" } @row;
#  print "<br/>--<br/>\n";

  my $total = $row[0];
  
  print "<div class=\"navbox\">\n";
  print_header_text($project);

  my ($displaystartdate, $displayenddate);

  if ( $newerthandate eq "" ) { 
    $displaystartdate = "beginning of project";
  } else { 
    $displaystartdate = $newerthandate;
    $displaystartdate =~ s/T/ /g;    
    $displaystartdate =~ s/Z//g;
    $displaystartdate = "<i>$displaystartdate</i>";
  }

  if ( $olderthandate eq "" ) { 
    $displayenddate = "present";
  } else { 
    $displayenddate = $olderthandate;
    $displayenddate =~ s/T/ /g;
    $displayenddate =~ s/Z//g;
    $displayenddate = "<i>$displayenddate</i>";
  }

  print "&nbsp;&nbsp;<b>Total results:&nbsp;" . $total 
        . "</b><br/> Displaying up to $limit results beginning with #" 
        . ($offset +1) . "<br/>\n"
        . "Displaying results from $displaystartdate to $displayenddate.\n";
   
  print "</div>\n";

#  print "RQ: '$query'<br/>\n";
#  my @lparam = @qparam;
#  print join "<br/>", map { $_ = "'" . $_ . "'" } @lparam;

  my $sth = $dbh->prepare($query);
  my $c = $sth->execute(@qparam);
  my $i = $offset;

  print "<!-- count: '$c' -->\n";

# SELECT l_project, l_article, l_action, l_timestamp, 
#             0           1       2            3

#        l_old, l_new, l_revision_timestamp, l_namespace
#           4       5      6                     7

  print << "HERE";
  <center><table class="wikitable">
  <tr>
    <th><b>Result</b></th>
HERE

    if (  ! ( $project =~ /\w|\d/ ) ) { 
      print "    <th>Project</th>\n";
    }

print << "HERE";
    <th><b>Article</b></th>
    <th><b>Revision</b></th>
    <th><b>Type</b></th>
    <th><b>Old value</b></th>
    <th><b>New value</b></th>
  </tr>
HERE

  while ( @row = $sth->fetchrow_array ) {
    $i++;  
    print "<!-- $i -->\n";

    if ( $row[2] eq 'moved' ) { 

      print "<tr><td>$i</td>\n";

      if (  ! ( $project =~ /\w|\d/ ) ) { 
        print "    <td>" . $row[0] . "</td>\n";
      }

      print "    <td>" . make_article_link($row[7], $row[1]) . "</td>\n";
      print "    <td>" . make_history_link($row[7], $row[1], $row[6],"l",1) 
            . "</td>\n";

     my ($dest_ns, $dest_art) = db_get_move_target($row[7], $row[1], $row[6]);
     my $link = make_article_link($dest_ns, $dest_art);
     print << "HERE";
      <td>redirected</td>
      <td colspan="2">$link</td>
HERE
      print "</tr>\n";

    } else {  # the quality or importance was changed
      print "<tr><td>$i</td>\n";

      if (  ! ( $project =~ /\w|\d/ ) ) { 
        print "    <td>" . $row[0] . "</td>\n";
      }

#     print "    <td>" . $row[3] . "</td>\n";
      print "    <td>" . make_article_link($row[7], $row[1]) . "</td>\n";
      print "    <td>" . make_history_link($row[7], $row[1],$row[6],"l",1) 
          . "</td>\n";
      print "    <td>" . $row[2] . "</td>\n";
      print "    " . get_cached_td_background($row[4]) . "\n";
      print "    " . get_cached_td_background($row[5]) . "\n";
      print "</tr>\n";
    }
  }
  print "</table>\n</center>\n";

  my $p;
  my $params_enc;
  foreach $p ( keys %$params ) { 
    next if ( $p eq 'offset' ) ;
    $params_enc .= "$p=" . uri_escape($params->{$p}) . "&";   
  }

  # For display purposes - whether we use a pipe between "previous" and "next"
  # depends on whether "previous" is defined or not 
  my $prev = 0;

  my $newURL;
  if (($offset - $limit + 1) > 0) {
    $newURL =   $logurl. "?" . $params_enc
              . "offset=" . ($offset - $limit + 1);	  
    print "<a href=\"" . $newURL . "\">Previous $limit entries</a>";
    $prev = 1;
  }
	
  if ($limit + $offset < $total){ 
    if ($prev == 1) {
      print " | ";
    }
    $newURL =   $logurl . "?" . $params_enc
             . "&offset=" . ($offset + $limit + 1);	  
    print "<a href=\"" . $newURL . "\">Next $limit entries</a>";
  }
  print "\n";	

  get_previous_name($params->{'ns'}, $params->{'pagename'});
}

###########################################################################

sub query_form {
  my $params = shift;
  
  my $project = $params->{'project'} || '';
  my $oldrating = $params->{'oldrating'} || "";
  my $newrating = $params->{'newrating'} || "";

  my $olderthan = $params->{'olderthan'} || "";
  my $newerthan = $params->{'newerthan'} || "";

  my $limit = $params->{'limit'} || "1000";
  my $offset = $params->{'offset'} || "1";

  my $ns = $params->{'ns'};
  if ( ! defined $ns ) { 
    $ns = "";
  }  

  my $pagename = $params->{'pagename'} || "";
  my $pagenameWC = $params->{'pagenameWC'} || "";

  my $pagename_wc_checked = "";
  if ( $pagenameWC eq 'on' ) { 
    $pagename_wc_checked = "checked=\"yes\" ";
  }

  print << "HERE";
<form>

<table class="outer">
<tr><td>
<table class="mainform">
<td id="projecta" class="toprow"><b>Project info</b><br/>
  <table class="subform">
    <tr><td>Project name</td>
      <td><input type="text" value="$project" name="project"/></td></tr>
    <tr><td>Namespace<br/>number</td>
      <td><input type="text" value="$ns" name="ns"/></td></tr>
    <tr><td>Page name</td>
      <td><input type="text" value="$pagename" name="pagename"/></td></tr>
    <tr><td colspan="2"><input type="checkbox" $pagename_wc_checked  
                               name="pagenameWC" />
      Treat page name as a 
      <a href="http://en.wikipedia.org/wiki/Regular_expression">regular expression</a></td>
    </tr>

    <tr><td>Old rating</td>
      <td><input type="text" value="$oldrating" name="oldrating"/></td></tr>
    <tr><td>New rating</td>
      <td><input type=\"text\" value="$newrating" name="newrating"/></td></tr>

    <tr><td>Assessments before</td>
      <td><input type="text" value="$olderthan" name="olderthan"/></td></tr>
    <tr><td>Assessments after</td>
      <td><input type=\"text\" value="$newerthan" name="newerthan"/></td></tr>
    <tr><td colspan="2" class="note">Note: leave any field blank to 
                       select all values.</td></tr>
</table>

<tr><td colspan="2" class="submit-td">
<div style="text-align: center;"><input type="submit" value="Generate list"/></div>
</td></tr>
  </table>
</td>

<td>
<table class="mainform">
<tr>
<td id="output" class="toprow">
<b>Output options</b><br/>
<table class="subform">
  <tr><td>Results per page</td>
      <td><input type="text" value="$limit" name="limit"/></td></tr>
  <tr><td>Start with result #</td>
      <td><input type="text" value="$offset" name="offset"/></td></tr>
</table>
</td></tr></table>
</td>
</tr>
</table>
</form>
HERE

}

###########################################################################

sub print_header_text {
  my $project = shift;
  my ($timestamp, $wikipage, $parent, $shortname);
  my $tableURL = $Opts->{'table-url'};
  my @t = split('log.pl',$tableURL);
  $tableURL = @t[0] . "table.pl";

  if ( $project =~ /\w|\d/ ) { 
    $tableURL = $tableURL . "?project=" . $project;

    ($project, $timestamp, $wikipage, $parent, $shortname) = 
      get_project_data($project);

    if ( ! defined $wikipage) {
      print "Data for <b>$project</b> "; 	
    } elsif ( ! defined $shortname) {
      print "Data for <b>" . get_link_from_api("[[$wikipage]]") . "</b> "; 
    } else {
      print "Data for <b>" . get_link_from_api("[[$wikipage|$shortname]]") . "</b> ";
    }
  } else { 
    print " Data for all projects ";
  }

  print "(<b>list</b> \| <a href=\"" . $tableURL 
        . "\">summary table</a>)\n";
}


###########################################################################

sub get_previous_name {
  my $ns = shift;
  my $title = shift;

  return unless ( defined $ns && defined $title);

  my $sth = $dbh->prepare('select m_timestamp, m_old_namespace, m_old_article
                           from moves where m_new_namespace = ? 
                                        and m_new_article = ?');

  my $r = $sth->execute($ns, $title);

  if ( $r > 0 ) { 
    print "<b>Previous names:</b><ul>\n";
    print << "HERE";
      <table class="wikitable">
      <tr><th>Article</th>
      <th>Date redirected</th>
      </tr>
HERE

    my @row;
    while ( @row = $sth->fetchrow_array ) { 
      print "<tr>\n";
      print "  <td>" . make_article_link($row[1], $row[2]) . "</td>\n";
      print "  <td>$row[0]</td>\n";
      print "<tr>\n";
    }
    print "</table>\n";
  }

  return;
}

###########################################################

sub format_date {
  my $date = shift;
  if ( $date eq "" ) { return ""};

  my @dateparts = strptime($date);

  return sprintf("%4d-%02d-%02dT%02d:%02d:%02dZ",
                 1900 + $dateparts[5],
                 1 + ($dateparts[4] || 0) ,
                 $dateparts[3] || 1,
                 $dateparts[2] || 0,
                 $dateparts[1] || 0,
                 $dateparts[0] || 0 );
}

############################################################

# Load successfully
1;
