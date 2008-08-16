sub db_connect { 
  my $filename;

  if ( ! defined $ENV{'HOME'} )   { 
        $filename = $ENV{'SCRIPT_FILENAME'}; 
        $filename =~ s/public_html.*//; 
  } else {
        $filename = $ENV{'HOME'}; 
  }
  $filename = $filename . "/.wp10.conf.www";
  
  if ( defined $ENV{'WP10_CREDENTIALS'} ) {
    $filename = $ENV{'WP10_CREDENTIALS'};
  }

  die "Can't open database configuration '$filename'\n"
    unless -r $filename;

  open CONF, "<", $filename;
  my ($opt, $val, $line);
  my %opts;
  while ( $line = <CONF> ) {
    chomp $line;
    ($opt, $val) = split /\s+/, $line, 2;

    $opts{$opt} = $val;
  }
  close CONF;

  die "No database given in database conf file\n"
    unless ( defined $opts{'database'} );

  my $connect = "DBI:mysql"
           . ":database=" . $opts{'database'};

  if ( defined $opts{'host'} ) {
    $connect .= ":host="     . $opts{'host'} ;
  }

  if ( defined $opts{'credentials'} ) {
    $opts{'password'} = $opts{'password'} || "";
    $opts{'username'} = $opts{'username'} || "";
    $connect .= ":mysql_read_default_file=" . $opts{'credentials'};
  }

  my $db = DBI->connect($connect, $opts{'username'}, $opts{'password'})
     or die "Couldn't connect to database: " . DBI->errstr;
   
  return $db;
}



# Return success
1;
