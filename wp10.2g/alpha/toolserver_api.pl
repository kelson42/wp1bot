#!/usr/bin/perl

use strict;
use DBI;
use Encode;
use Data::Dumper;

our $Opts;
my  $Prefix;

=head1 SYNOPSIS
 
 Routines to update the local database from information 
 on the Wikimedia Toolserver

=head1 FUNCTIONS

=over
 
=cut

#####################################################################

=item B<toolserver_connect>(OPTIONS )
 
 <Establishes a connection with the toolserver's copy of the wiki's 
 database>
 
 Parameters:
 
 OPTIONS: options from the ~/.wp10.conf configuration file
 
 Returns:
 
 DB: database handler object
 
=cut

sub toolserver_connect {
	my $opts = shift;
	
	die "No 'database_wiki_ts' given in database conf file\n"
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

=item B<get_prefixes>(OPTIONS, DB )
 
Loads a the namespace names of the "DB" wiki from the 
toolserver's global database
 
 Parameters:
 
 OPTIONS: options from the ~/.wp10.conf configuration file

 DB: database handler object

 Returns:
 
 $Prefix: hash map of a wiki's namespaces
 
=cut

sub get_prefixes { 
	my $opts = shift;
	my $db = shift;
	
	die "No 'database_ts' given in database conf file\n"
	unless ( defined $opts->{'database_ts'} );
	
	my $connect = "DBI:mysql" . ":database=" . $opts->{'database_ts'};
	
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
	
	$dbt->disconnect();
}

######################################################################
=item B<toolserver_pages_in_category>(CATEGORY, [NS])
 
  Returns an array reference listing pages in CATEGORY
 
  CATEGORY _must_ be UTF-8 encoded
  
  The NS parmater, optional, is a numeric namespace for 
  filtering the results.
  
  The pages in the rsulting array _do_ have the namespace
  prefix attached (for example C<Talk:Foo> and C<Wikipedia:Bar>)
  
  The titles returned are UTF-8 encoded
 
=cut
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
		#    $title = decode("utf8", $title);
		$title =~ s/_/ /g;
		push @results, $title;
	}                             
	
	return \@results;
}

######################################################################
=item B<toolserver_pages_in_category_detailed>(CATEGORY, [NS]) 
 
 Returns a reference to an array of hashes, 
 one for each page in CATEGORY.
 
 The output format is
 
 {  'ns'        => NAMESPACE, 
 'title'     => TITLE,
 'pageid'    => PAGEID,
 'sortkey'   => SORTKEY,
 'timestamp' => TIMESTAMP }
 
 CATEGORY _must_ be UTF-8 encoded. 
 
 The NS parmater, optional, is a numeric namespace for 
 filtering the results.
 
 The page titles in the resulting array _do_not_ have the namespace
 prefix attached (for example, the page C<Talk:Foo> will show
 
 { 'ns' => '1',
 'title' => 'Foo',
 ...  }
 
 The data returned is all UTF-8 encoded.
  
=cut

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
		# obselete behavior
		#      $title =  $Prefix->{$row[0]} . $row[1];
		#      $title = decode("utf8", $title);
		
		$title = $row[1];
		$title =~ s/_/ /g;
		$data->{'title'} = $title;
		
		$data->{'pageid'} = $row[2];
		$data->{'sortkey'} = $row[3];
		
		$ts = $row[4];
		$ts =~ s/ /T/;
		$ts = $ts . "Z";
		#      print "T '$row[4]' '$ts'\n";
		
		$data->{'timestamp'} = $ts;
		push @results, $data;
	}    
	return \@results;
}

######################################################################

1;
