use Data::Dumper;
use Encode;

sub db_connect {
  my $opts = shift;

  die "No database given in database conf file\n"
    unless ( defined $opts->{'database'} );

  my $connect = "DBI:mysql"
           . ":database=" . $opts->{'database'};

  if ( defined $opts->{'host'} ) {
    $connect .= ":host="     . $opts->{'host'} ;
  }

  if ( defined $opts->{'credentials-readonly'} ) {
    $opts->{'password'} = $opts->{'password'} || "";
    $opts->{'username'} = $opts->{'username'} || "";

    $connect .= ":mysql_read_default_file=" 
              . $opts->{'credentials-readonly'};
  }

  my $db = DBI->connect($connect, $opts->{'username'}, $opts->{'password'})
     or die "Couldn't connect to database: " . DBI->errstr;
   
  return $db;
}

###########################################################

sub get_project_data {
	my $project = shift;
	
	my $sth = $dbh->prepare ("SELECT * FROM projects WHERE p_project = ?");
	$sth->execute($project);
	
	my @row;
	# There really shouldn't be more than one row here,
	# so a while loop is not needed
	@row = $sth->fetchrow_array();
	
	my $p_project = $row[0];
	my $p_timestamp =  $row[1];
	my $p_wikipage =  $row[2];
	my $p_parent =  $row[3];
	
	return ( $p_project, $p_timestamp, $p_wikipage, $p_parent );
	
}


# Load successfully
1;
