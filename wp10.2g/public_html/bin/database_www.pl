#!/usr/bin/perl

# database_www.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for additional information

=head1 SYNOPSIS

Routines for the CGI programs to connect to the database

=cut

use Data::Dumper;
use Encode;

#####################################################################

=item B<db_connect>(OPTS)

Connect to the database using the readonly credentials

=cut

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

#####################################################################


=item B<db_connect_rw>(OPTS)

Connect to the database using the readwrite credentials

=cut

sub db_connect_rw {
  my $opts = shift;

  die "No database given in database conf file\n"
    unless ( defined $opts->{'database'} );

  my $connect = "DBI:mysql"
           . ":database=" . $opts->{'database'};

  if ( defined $opts->{'host'} ) {
    $connect .= ":host="     . $opts->{'host'} ;
  }

  if ( defined $opts->{'credentials-readwrite'} ) {
    $opts->{'password'} = $opts->{'password'} || "";
    $opts->{'username'} = $opts->{'username'} || "";

    $connect .= ":mysql_read_default_file=" 
                . $opts->{'credentials-readwrite'};
  }

  my $db = DBI->connect($connect, $opts->{'username'}, $opts->{'password'})
     or die "Couldn't connect to database: " . DBI->errstr;
   
  return $db;
}

#####################################################################

=item B<get_project_data>(PROJECT)

Return data from the I<projects> table for PROJECT

=cut

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
  my $p_shortname =  $row[4];

  return ( $p_project, $p_timestamp, $p_wikipage, $p_parent, $p_shortname );
}

###########################################################

=item B<db_get_project_details>()

Get all information from the I<projects> table. 

Returns hash ref indexed by project name.

=cut

sub db_get_project_details { 
  my $sth = $dbh->prepare("SELECT * FROM projects;");
  $sth->execute();
  return $sth->fetchall_hashref('p_project');
}

###########################################################

=item B<db_get_move_target>(NAMESPACE, ARTICLE, TIMESTAMP)

Get the destination where NAMESPACE:ARTICLE was moved
at TIMESTAMP.

Returns (DEST_NAMESPACE, DEST_ARTICLE)

=cut

sub db_get_move_target{ 
  my $old_ns = shift;
  my $old_art = shift;
  my $timestamp = shift;

  my $sth = $dbh->prepare("SELECT m_new_namespace, m_new_article " .
                          "FROM moves WHERE m_timestamp = ? " . 
                          "and m_old_namespace = ? " .
                          "and m_old_article = ? ");

  my $r = $sth->execute($timestamp, $old_ns, $old_art);

# print   "<!-- " 
#        . " move target r: '$r' for '$old_ns' '$old_art' '$timestamp' " 
#        .  " -->\n";

  return $sth->fetchrow_array();
}

###########################################################

=item B<db_get_namespaces>() 

Return a hash reference that maps NAMESPACE_NUMBER => NAMESPACE_TITLE

=cut

sub db_get_namespaces {
  my $sth = $dbh->prepare("SELECT ns_id, ns_name " 
                        . "FROM toolserver.namespace where dbname = ?");
  $sth->execute('enwiki_p');

  my $input = $sth->fetchall_hashref('ns_id');
  my $output = {};
  my $key;
  foreach $key ( keys %$input ) { 
    $output->{$key} = $input->{$key}->{'ns_name'};
  }
  return $output;
}

###########################################################

# Load successfully
1;
