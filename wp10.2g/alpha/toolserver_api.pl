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

  die "No database given in database conf file\n"
  unless ( defined $opts->{'database_wiki_ts'} );
	
  my $connect = "DBI:mysql"
    . ":database=" . $opts->{'database_wiki_ts'};

	# For the enwiki_p db, this should be sql-s1
  if ( defined $opts->{'host_wiki_ts'} ) {
		$connect .= ":host="     . $opts->{'host_wiki_ts'} ;
  }


  if ( defined $opts->{'credentials-toolserver'} ) {
		$opts->{'password'} = $opts->{'password'} || "";
		$opts->{'username'} = $opts->{'username'} || "";
		
		$connect .= ":mysql_read_default_file=" 
		. $opts->{'credentials-toolserver'};
  }

  my $db = DBI->connect($connect, 
  $opts->{'username'}, 
  $opts->{'password'},
  {'RaiseError' => 1, 
  'AutoCommit' => 0} )
  or die "Couldn't connect to database: " . DBI->errstr;
	
  get_prefixes($opts, $opts->{'database_wiki_ts'});
  
  return $db;
}

#####################################################################

sub get_prefixes { 
  my $opts = shift;
  my $db = shift;
	#my $cred = '/home/cbm/.my.cnf';

	die "No database given in database conf file\n"
	unless ( defined $opts->{'database_toolserver'} );
	
	my $connect = "DBI:mysql"
    . ":database=" . $opts->{'database_toolserver'};
	
	if ( defined $opts->{'host_ts'} ) {
		$connect .= ":host="     . $opts->{'host_ts'} ;
	}
	
	if ( defined $opts->{'credentials-toolserver'} ) {
		$opts->{'password'} = $opts->{'password'} || "";
		$opts->{'username'} = $opts->{'username'} || "";
		
		$connect .= ":mysql_read_default_file=" 
		. $opts->{'credentials-toolserver'};
  }
	
  my $dbt = DBI->connect($connect, 
  $opts->{'username'}, 
  $opts->{'password'},
  {'RaiseError' => 1, 
  'AutoCommit' => 0} )
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
  my $ts;
  while (@row = $sth->fetchrow_array) { 
      $data = {};
      $data->{'ns'} = $row[0];
      $title =  $Prefix->{$row[0]} . $row[1];
      $title = decode("utf8", $title);
      $title =~ s/_/ /g;

      $data->{'title'} = $title;
      $data->{'pageid'} = $row[2];
      $data->{'sortkey'} = $row[3];

      $ts = $row[4];
      $ts =~ s/ /T/;
      $ts = $ts . "Z";
      print "T '$row[4]' '$ts'\n";

      $data->{'timestamp'} = $ts;
      push @results, $data;
  }    
  return \@results;
}

######################################################################

1;

