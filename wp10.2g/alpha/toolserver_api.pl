use strict;
use DBI;
use Encode;

our $Opts;

my $Prefix = {
    '-2' => 'Media:',
    '-1' => 'Special:',
     '0' => '',
     '1' => 'Talk:',
     '2' => 'User:',
     '3' => 'User talk:',
     '4' => 'Wikipedia:',
     '5' => 'Wikipedia talk:',
     '6' => 'Image:',
     '7' => 'Image talk:',
     '8' => 'Mediawiki',
     '9' => 'Mediawiki talk:',
    '10' => 'Template:',
    '11' => 'Template talk:',
    '12' => 'Help',
    '13' => 'Help talk:',
    '14' => 'Category:',
    '15' => 'Category talk:',
   '100' => 'Portal:',
   '101' => 'Portal talk' 
     };
 
my $dbh = toolserver_connect();

######################################################################

sub toolserver_connect {
  my $opts = shift;

  my $host = 'sql-s1';
  my $database = 'enwiki_p';
  my $cred = '/home/cbm/.my.cnf';

  my $connect = "DBI:mysql"
           . ":database=" . $database;

  $connect .= ":host="  . $host ;


  $connect .= ":mysql_read_default_file="  . $cred;


  my $db = DBI->connect($connect, "","",  {'RaiseError' => 1} ) 
     or die "Couldn't connect to database: " . DBI->errstr;
   
  return $db;
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


  my $r = $sth->execute(@qparam);
  print "R: $r \n";

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

  my $r = $sth->execute(@qparam);


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
