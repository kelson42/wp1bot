use Data::Dumper;

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


# Load successfully
1;
