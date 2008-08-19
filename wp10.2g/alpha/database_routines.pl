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

  print "U:" . "$project // $art // $timestamp // $value // was '$oldvalue'\n";

  $art = encode("utf8", $art);
  $project = encode("utf8", $project);
  $value = encode("utf8", $value);
  $oldvalue = encode("utf8", $oldvalue);

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
  my $replacement = shift;

  if ( ! defined $replacement ) { 
    $replacement = $rating;
  }
  
  $project = encode("utf8", $project);
  $rating = encode("utf8", $rating);
  $type = encode("utf8", $type);
  $category = encode("utf8", $category);
  $replacement = encode("utf8", $replacement);

  my $sth = $dbh->prepare (
       "UPDATE categories SET c_category = ?, c_ranking = ?, c_replacement = ? " .
       "WHERE c_project = ? and c_rating= ? and c_type = ? "
     );

  my $count = $sth->execute($category, $ranking, $replacement, 
                            $project, $rating, $type);

  if ( $count eq '0E0' ) { 
    $sth = $dbh->prepare ("INSERT INTO categories VALUES (?,?,?,?,?,?)");
    $count = $sth->execute($project, $type, $rating, 
                           $replacement, $category, $ranking);
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
  my $shortname = shift;

  my $proj_count;
  my @row;

  my $sth = $dbh->prepare("SELECT COUNT(r_article) FROM ratings " 
                        . "WHERE r_project = ?");
  $sth->execute($project);
  @row = $sth->fetchrow_array();
  $proj_count = $row[0];

  my $sth = $dbh->prepare ("UPDATE projects SET p_timestamp  = ?, "
                         . " p_wikipage = ?, p_parent = ?, p_shortname = ?," 
                         . " p_count  = ? " 
                         . " WHERE p_project = ?" );

  my $count = $sth->execute($timestamp, $wikipage, $parent, 
                            $shortname, $proj_count, $project);

  if ( $count eq '0E0' ) { 
    $sth = $dbh->prepare ("INSERT INTO projects VALUES (?,?,?,?,?,?)");
    $count = $sth->execute($project, $timestamp, $wikipage, 
                           $parent, $shortname, $proj_count);
  }

  update_category_data( $project, 'Unknown-Class', 'quality', 
                        '', 10, 'Unassessed-Class'); 
  update_category_data( $project, 'Unknown-Class', 'importance',
                        '', 10, 'Unassessed-Class');

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

  my $sth = $dbh->prepare("delete from ratings " 
                        . "where r_quality = 'Unknown-Class' " 
                        . " and r_importance = 'Unknown-Class' "
                        . " and r_project = ?");
  my $count = $sth->execute($proj);
  print "Deleted articles: $count\n";

  # It's possible for the quality to be NULL if the article has a 
  # rated importance but no rated quality (not even Unassessed-Class).
  # This will always happen if the article has a quality rating that the 
  # bot doesn't recognize. Change the NULL to 'Unassessed-Class'.

  $sth = $dbh->prepare("update ratings set r_quality = 'Unknown-Class', " 
                     . "r_quality_timestamp = r_importance_timestamp "
                     . "where isnull(r_quality) and r_project = ?");
  $count = $sth->execute($proj);
  print "Null quality rows: $count\n";

  $sth = $dbh->prepare("update ratings set r_importance = 'Unknown-Class', " 
                     . "r_importance_timestamp = r_quality_timestamp "
                     . "where isnull(r_importance) and r_project = ?");
  $count = $sth->execute($proj);
  print "Null importance rows: $count\n";

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

sub db_list_projects { 
  my $projects = [];

  my $sth = $dbh->prepare("SELECT * FROM projects " 
                        . "order by p_timestamp asc;");
  $sth->execute();

  my @row;
  while ( @row = $sth->fetchrow_array ) { 
    push @$projects, $row[0];
  }

  return $projects;
}

###########################################################

sub db_get_project_details { 
  my $sth = $dbh->prepare("SELECT * FROM projects;");
  $sth->execute();
  return $sth->fetchall_hashref('p_project');
}


############################################################

sub update_review_data {
	# Process all the parameters
	my $global_timestamp = shift;
	my $art = shift;
	my $value = shift;
	my $timestamp = shift;
	my $oldvalue = shift;
	
	unless ( ($value eq 'GA') || ($value eq 'FA') ) {
		print "Unrecognized review state: $value \n"; 
		return -1;
	};
		
	my $sth = $dbh->prepare ("UPDATE review SET rev_value = ?, " 
	. "rev_timestamp = ? WHERE rev_article = ?");
	
	# Executes the UPDATE query. If there are no entries matching the 
        # article's name in the table, the query will return 0, allowing us 
        # to create an INSERT query instead.
	my $count = $sth->execute($value, $timestamp, $art);
	
	if ( $count eq '0E0' ) { 
		$sth = $dbh->prepare ("INSERT INTO review VALUES (?,?,?)");
		$count = $sth->execute($value, $art, $timestamp);
	}
	
	print "U:" . "$art // $value // $timestamp // was '$oldvalue'\n";
	
}

############################################################
## Probably needs to be merged with update_review_data()

sub remove_review_data {
	# Process all the parameters
	my $art = shift;
	my $value = shift;
	my $oldvalue = shift;
	
	unless ( ($value eq 'None') ) {
		print "Unrecognized review state: $value \n"; 
		return -1;
	}	

	my $sth = $dbh->prepare ("DELETE FROM review WHERE rev_value = ? AND " 
	. "rev_article = ?");
	
	# Executes the DELETE query. 
	my $count = $sth->execute($oldvalue, $art);
		
	print "U:" . "$art // $value // removed // was '$oldvalue'\n";
	
}

############################################################

sub get_review_data {
	my $value = shift;
	my $sth;
	
	if ( ! defined $value ) 
	{ 
		$sth = $dbh->prepare ("SELECT rev_article, rev_value FROM review");
		$sth->execute();
	}
	else
	{
		$sth = $dbh->prepare ("SELECT rev_article, rev_value FROM review WHERE rev_value = ?");
		$sth->execute($value);
	}
	
	# Iterate through the results
	my $ratings = {};
	my @row;
	while ( @row = $sth->fetchrow_array() ) {
		$row[0] = decode("utf8", $row[0]);
		$ratings->{$row[0]} = $row[1];
	}
	
	return $ratings;	
}

############################################################

sub db_lock { 
  my $lock = shift;

  my $sth = $dbh->prepare("SELECT GET_LOCK(?,0)");
  my $r = $sth->execute($lock);
  my @row = $sth->fetchrow_array();
  return $row[0];
}

sub db_unlock { 
  my $lock = shift;
  my $sth = $dbh->prepare("SELECT RELEASE_LOCK(?)");
  my $r = $sth->execute($lock);
  my @row = $sth->fetchrow_array();
  return $row[0];
}

############################################################


# Load successfully
1;


__END__
