#!/usr/bin/perl

use strict;
use DBI;
use Encode;
use Data::Dumper;

our $Opts;
my  $Prefix;

my $dbh = toolserver_connect($Opts);

#####################################################################

sub toolserver_connect {
  my $opts = shift;

  my $host = 'sql-s1';
  my $database = 'enwiki_p';
  my $cred = '/home/cbm/.my.cnf';

  my $connect = "DBI:mysql"
           . ":database=" . $database;
  $connect .= ":host="  . $host ;
  $connect .= ":mysql_read_default_file=$cred" ;
  
  my $db = DBI->connect($connect, "", "", {'RaiseError' => 1} ) 
     or die "Couldn't connect to database: " . DBI->errstr;
 
  get_prefixes($opts, $database);
  
  return $db;
}

#####################################################################

sub get_prefixes { 
  my $Opts = shift;
  my $db = shift;
  my $cred = '/home/cbm/.my.cnf';

  my $connect = "DBI:mysql:database=toolserver:host=sql";
  $connect   .= ":mysql_read_default_file=$cred" ;

  my $dbt = DBI->connect($connect, "", "", {'RaiseError'=>1})
     or die "Couldn't connect to database: " . DBI->errstr;

  my $query = "SELECT ns_id, ns_name FROM namespace WHERE dbname = ?";

  my $sth = $dbt->prepare($query);
  my $c = $sth->execute($db);

  my @row;

  while (@row = $sth->fetchrow_array()) {
    if ( $row[1] ne "" ) { 
      $row[1] .= ":";
    }
    $Prefix->{$row[0]} = $row[1];
  }
}

######################################################################

sub toolserver_pages_in_category { 
  my $cat = shift;
  my $ns = shift;

  my $query = "
SELECT page_namespace, page_title 
FROM page 
JOIN categorylinks ON page_id = cl_from
WHERE cl_to = ?";

  my @qparam = ($cat);

  if ( defined $ns ) {
    $query .= " AND page_namespace = ?";
    push @qparam, $ns;
  };

  my $sth = $dbh->prepare($query);
  my $t = time();
  my $r = $sth->execute(@qparam);
  print "\tListed $r articles in " . (time() - $t) . " seconds\n";

  my @row;
  my @results;
  my $title;
  while (@row = $sth->fetchrow_array) { 
    $title = $Prefix->{$row[0]} . $row[1];
    $title = decode("utf8", $title);
    $title =~ s/_/ /g;
    push @results, $title;
  }                             

  return \@results;
}

######################################################################

sub toolserver_pages_in_category_detailed { 
  my $cat = shift;
  my $ns = shift;

  my $query = "
SELECT page_namespace, page_title, page_id, cl_sortkey, cl_timestamp 
FROM page 
JOIN categorylinks ON page_id = cl_from
WHERE cl_to = ?";

  my @qparam = ($cat);

  if ( defined $ns ) {
    $query .= " AND page_namespace = ?";
    push @qparam, $ns;
  };

  my $sth = $dbh->prepare($query);

  my $t = time();
  my $r = $sth->execute(@qparam);
  print "\tListed $r articles in " . (time() - $t) . " seconds\n";

  my @row;
  my @results;
  my $data;
  my $title;
  while (@row = $sth->fetchrow_array) { 
      $data = {};
      $data->{'ns'} = $row[0];
      $title =  $Prefix->{$row[0]} . $row[1];
      $title = decode("utf8", $title);
      $title =~ s/_/ /g;

      $data->{'title'} = $title;
      $data->{'pageid'} = $row[2];
      $data->{'sortkey'} = $row[3];
      $data->{'timestamp'} = $row[4];
      push @results, $data;
  }    
  return \@results;
}

######################################################################

1;

