use strict vars;
use Data::Dumper;

$Data::Dumper::Sortkeys = 1;

our $Opts;

use DBI;
my $dbh = db_connect($Opts);

#######################################################################

sub update_article_data {
  my $global_timestamp = shift;
  my $project = shift;
  my $art = shift;
  my $table = shift;
  my $value = shift;
  my $timestamp = shift;
  my $oldvalue = shift;

  die "Bad table: $table" 
    unless ( ($table eq 'quality') || ($table eq 'importance') );

  $art = encode("utf8", $art);
  $project = encode("utf8", $project);
  $value = encode("utf8", $value);
  $oldvalue = encode("utf8", $oldvalue);

  print "U:" . "$project // $art // $timestamp // $value // was '$oldvalue'\n";

  my $sth_insert_logging = $dbh->prepare("INSERT INTO logging " . 
                                         "values (?,?,?,?,?,?,?)");

  $sth_insert_logging->execute($project, $art, $table, $global_timestamp,
                               $oldvalue, $value, $timestamp);

  update_article_rating_data($project, $art, $table, $value, $timestamp);
}


#######################################################################

sub update_category_data { 
  my $project = shift;
  my $rating = shift;
  my $type = shift;
  my $category = shift;
  my $ranking = shift;
  
  $project = encode("utf8", $project);
  $rating = encode("utf8", $rating);
  $type = encode("utf8", $type);
  $category = encode("utf8", $category);

  my $sth = $dbh->prepare (
       "UPDATE categories SET c_category = ?, c_ranking = ? " .
       "WHERE c_project = ? and c_rating= ? and c_type = ? "
     );

  my $count = $sth->execute($category, $ranking, $project, $rating, $type);

  if ( $count eq '0E0' ) { 
    $sth = $dbh->prepare ("INSERT INTO categories VALUES (?,?,?,?,?)");
    $count = $sth->execute($project, $type, $rating, $category, $ranking);
  }

}

######################################################################
## Internal function to update the ratings table when article is 
## reassessed

sub update_article_rating_data { 
  my $project = shift;
  my $article = shift;
  my $type = shift;
  my $rating = shift;
  my $rating_timestamp = shift;

  if ( !( $type eq 'importance' || $type eq 'quality' ) ) { 
    die "Bad ratings type:  $type\n";
  }

  my $sth = $dbh->prepare ("UPDATE ratings SET r_$type = ?, " 
                         . "r_" . $type . "_timestamp = ?  " 
                         . "WHERE r_project = ? and r_article = ?");

  my $count = $sth->execute($rating, $rating_timestamp, $project, $article);

  if ( $count eq '0E0' ) { 
    my ($quality, $importance, $qualityTS, $importanceTS);
    if ( $type eq 'quality' ) {
      $quality = $rating; 
      $qualityTS = $rating_timestamp;
    }
    if ( $type eq 'importance' ) { 
      $importance = $rating; 
      $importanceTS = $rating_timestamp;
    }
    $sth = $dbh->prepare ("INSERT INTO ratings VALUES (?,?,?,?,?,?)");
    $count = $sth->execute($project, $article, $quality, 
                           $qualityTS, $importance, $importanceTS);
  }
}

############################################################

sub update_project { 
  my $project = shift;
  my $timestamp = shift;
  my $wikipage = shift;
  my $parent = shift;

  my $sth = $dbh->prepare ("UPDATE projects SET p_timestamp  = ?, "
                         . "p_wikipage = ?, p_parent = ? " 
                         . "WHERE p_project = ?" );

  my $count = $sth->execute($timestamp, $wikipage, $parent, $project);

  if ( $count eq '0E0' ) { 
    $sth = $dbh->prepare ("INSERT INTO projects VALUES (?,?,?,?)");
    $count = $sth->execute($project, $timestamp, $wikipage, $parent);
  }
}

############################################################
## Query project table for a particular project

sub project_exists {
  my $project = shift;
  $project = encode("utf8", $project);

  my $sth = $dbh->prepare ("SELECT * FROM projects WHERE p_project = ?");
  my $r = $sth->execute($project);

  return ($r == 1 ? 1 : 0);
}

############################################################

sub get_project_ratings {
  my $project = shift;
  my $type = shift;

  if ( ! ( $type eq 'quality' || $type eq 'importance') ) { 
    die "Bad type: $type\n";
  }

  $project = encode("utf8", $project);

  print "Getting $type ratings for $project from database\n";

  my $sth = $dbh->prepare("SELECT r_article, r_$type " 
                        . "FROM ratings WHERE r_project = ?");
  $sth->execute($project);

  my $ratings = {};
  my @row;
  while ( @row = $sth->fetchrow_array() ) {
    $row[0] = decode("utf8", $row[0]);
    $ratings->{$row[0]} = $row[1];
  }

  return $ratings;
}

###########################################################

sub get_project_data {
	my $project = shift;
	$project = encode("utf8", $project);
	
	my $sth = $dbh->prepare ("SELECT * FROM projects WHERE p_project = ?");
	$sth->execute($project);
	
	my @row;
	# There really shouldn't be more than one row here,
	# so a while loop is not needed
	@row = $sth->fetchrow_array();

	$p_project->{"project"} = decode("utf8", $row[0]);
	$p_timestamp->{"timestamp"} = decode("utf8", $row[1]);
	$p_wikipage->{"wikipage"} = decode("utf8", $row[2]);
	$p_parent->{"parent"} = decode("utf8", $row[3]);
	
	return ( $p_project, $p_timestamp, $p_wikipage, $p_parent );
	
}


############################################################

sub db_commit { 
  print "Commit database\n";
  $dbh->commit();
  return 0;
}

############################################################

sub db_rollback { 
  print "Rollback database\n";
  $dbh->rollback();
  return 0;
}

############################################################

sub db_cleanup_project {
  my $proj = shift;
  print "Cleanup $proj\n";

  # If both quality and importance are NULL, that means the article
  # was once rated but isn't any more, so we delete the row

  my $sth = $dbh->prepare("delete from ratings where isnull(r_quality) " 
                        . "and isnull(r_importance) and r_project = ?");
  my $count = $sth->execute($proj);
  print "Deleted articles: $count\n";

  # It's possible for the quality to be NULL if the article has a 
  # rated importance but no rated quality (not even Unassessed-Class).
  # This will always happen if the article has a quality rating that the 
  # bot doesn't recognize. Change the NULL to 'Unassessed-Class'.

  $sth = $dbh->prepare("update ratings set r_quality = 'Unassessed-Class', " 
                     . "r_quality_timestamp = r_importance_timestamp "
                     . "where isnull(r_quality) and r_project = ?");
  $count = $sth->execute($proj);
  print "Null quality rows: $count\n";

  return 0;
}

############################################################

sub db_connect {
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

  my $db = DBI->connect($connect, 
                        $opts->{'username'}, 
                        $opts->{'password'},
                       {'RaiseError' => 1, 
                        'AutoCommit' => 0} )
     or die "Couldn't connect to database: " . DBI->errstr;
   
  return $db;
}

############################################################

# Load successfully
1;


__END__


