#!/usr/bin/perl

use strict;
use DBI;
use Encode;
use Data::Dumper;
use POSIX 'strftime';

require  'read_conf.pl';
our $Opts = read_conf();
my  $Prefix;
my  $PrefixRev;

=head1 SYNOPSIS
 
 Routines to update the local database from information 
 on the Wikimedia Toolserver

=head1 FUNCTIONS

=over
 
=cut

my $dbh = toolserver_connect($Opts);

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
toolserver's global database into internal variables
 
 Parameters:
 
 OPTIONS: options from the ~/.wp10.conf configuration file

 DB: database name
 
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
		$PrefixRev->{$row[1]} = $row[0];
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
=item B<toolserver_resolve_redirect>(NS, TITLE)

Resolves a redirect from NS:TITLE. 

Returns undef if page is not a redirect, returns
(TARGET_NS, TARGET_TITLE) if it is.

=cut

sub toolserver_resolve_redirect { 
  my $ns = shift;
  my $title = shift;

  $title =~ s/ /_/g;

  my $query = "select rd_namespace, rd_title from page 
               join redirect on page_id = rd_from 
                and page_title = ? and page_namespace = ?";

  my $sth = $dbh->prepare($query);
  my $r = $sth->execute($title, $ns);

  if ( $r == 1) { 
    my @row = $sth->fetchrow_array();
    $row[1] =~ s/_/ /g;
    return $row[0], $row[1];
  }
  
  return undef;
}

######################################################################
=item B<toolserver_get_move_log(NS, TITLE)

Gets move log entries for NS:TITLE 

Returns an array ref of log entries, sorted from newest to oldest

=cut

sub toolserver_get_move_log { 
  my $ns = shift;
  my $title = shift;

  $title =~ s/ /_/g;


  my $query = "select log_id, log_type, log_action, log_timestamp, 
                  user_name, log_namespace, log_title, log_comment 
               from logging 
               join user on log_user = user_id where log_namespace = ?
               and log_title = ?  and log_type = 'move' 
               order by log_timestamp DESC";

  my $sth = $dbh->prepare($query);
  my $r = $sth->execute($ns, $title);

  my @row;

  my $results = [];
  my $data;
  my @row;

  while ( @row = $sth->fetchrow_array() ) { 
    $row[4] =~ s/_/ /g;
    $row[6] =~ s/_/ /g;
    $row[7] =~ s/_/ /g;

    $data = {};
    $data->{'logid'} = $row[0];
    $data->{'type'} = $row[1];
    $data->{'action'} = $row[2];
    $data->{'timestamp'} =  fix_timestamp($row[3]);
    $data->{'user'} = $row[4];
    $data->{'ns'} = $row[5];
    $data->{'title'} = $row[6];
    $data->{'comment'} = $row[7];

    my $art = $row[8];
    my $ns = 0;
    my $n;
    foreach $n ( keys %$PrefixRev ) { 
      next if ( $n == 0);
      if ( $art =~ /^\Q$PrefixRev->{$n}\E/ ) {
        $ns = $n;
        $art =~ s/^\Q$PrefixRev->{$n}\E//;
        last;
      }
    }
    $data->{'dest-ns'} = $ns;
    $data->{'dest-title'} = $art;
    push @$results, $data;
  }

  return $results;
}


sub fix_timestamp { 
  my $t = shift;

  return substr($t, 0, 4) . "-" . substr($t, 4, 2) . "-"
           . substr($t, 6, 2) . "T" . substr($t, 8, 2) 
           . ":" . substr($t, 10, 2) . ":" . substr($t, 12, 2)  . "Z";
}

1;
