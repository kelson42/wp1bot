use strict vars;
use Data::Dumper;

=head1 SYNOPSIS

Routines to connect, query, and commit to the database

Note that autocommit is turned off, so C<db_commit()> must
be called to finish each transaction.

=head1 FUNCTIONS

=over 

=item Standard parameters:

=over 

=item TIMESTAMP

Current time

=item PROJECT

The name of a rated project

=item ARTICLE

The name of an article

=item RTYPE

Either 'quality' or 'importance'

=item RATING

A quality or importance rating name, e.g. Start-Class, Top-Class

=item REV_TIMESTAMP

A timestamp used to describe a particular revision of an article; used in 
conjunction with the ARTICLE parameter

=back

=cut

$Data::Dumper::Sortkeys = 1;

our $Opts;

use DBI;
my $dbh = db_connect($Opts);

#######################################################################

=item B<update_article_data>(TIMESTAMP, PROJECT, ARTICLE, RTYPE, RATING, 
REV_TIMESTAMP, PREVIOUS_RATING)

Top-level routine for updating data for a single article. Updates the
I<ratings> table and I<logging> table. 

Parameters:

=over

=item PREVIOUS_RATING

Previous rating value, used for I<logging>

=back

=cut

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

#  print "U:" . "$project // $art // $timestamp // $value // was '$oldvalue'\n";

  $art = encode("utf8", $art);
  $project = encode("utf8", $project);
  $value = encode("utf8", $value);
  $oldvalue = encode("utf8", $oldvalue);

  my $sth_insert_logging = $dbh->prepare_cached("INSERT INTO logging " . 
                                         "values (?,?,?,?,?,?,?)");

  $sth_insert_logging->execute($project, $art, $table, $global_timestamp,
                               $oldvalue, $value, $timestamp);

  
update_article_rating_data($project, $art, $table, $value, $timestamp);
}


#######################################################################

=item B<update_category_data>
(PROJECT, RATING, RTYPE, CATEGORY, RANKING, REPLACEMENT)

Update information about a rating for a project

=over

=item CATEGORY

The wikipedia category listing these articles.
e.g. C<Category:B-Class mathematics articles>

=item RANKING

A numeric sort ranking used to sort tables

=item REPLACEMENT

A standard rating (e.g. B-Class) used to replcae this rating in
global statistics

=back

=cut

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
       "UPDATE categories SET c_category = ?, c_ranking = ?, c_replacement = ?
        WHERE c_project = ? and c_rating= ? and c_type = ? "
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

=item B<update_article_rating_data>(PROJECT, ARTICLE, RTYPE, RATING, REV_TIMESTAMP)

Update I<ratings> table for a single article

=cut

sub update_article_rating_data { 
  my $project = shift;
  my $article = shift;
  my $type = shift;
  my $rating = shift;
  my $rating_timestamp = shift;

  if ( !( $type eq 'importance' || $type eq 'quality' ) ) { 
    die "Bad ratings type:  $type\n";
  }

  my $sth = $dbh->prepare_cached ("UPDATE ratings SET r_$type = ?, " 
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

=item B<update_articles_table>(PROJECT)

Update I<articles> table, which stores the highest quality and
importance assigned to an article. Must be run after updating
a project's data, to keep database coherent.

=cut

sub update_articles_table { 
  my $project = shift;
  $project = encode("utf8", $project);

  my $query = <<"HERE";
REPLACE INTO global_articles
SELECT r_article, max(qual.gr_ranking), max(imp.gr_ranking) 
FROM ratings 
JOIN categories as ci
   ON r_project = ci.c_project AND ci.c_type = 'importance'      
      AND r_importance = ci.c_rating 
JOIN categories as cq
   ON r_project = cq.c_project AND cq.c_type = 'quality'      
      AND r_quality = cq.c_rating
JOIN global_rankings AS qual 
  ON qual.gr_type = 'quality' AND qual.gr_rating = cq.c_replacement  
JOIN global_rankings AS imp 
  ON imp.gr_type = 'importance' AND imp.gr_rating = ci.c_replacement 
WHERE r_project = ? 
GROUP BY r_article
HERE

  my $sth = $dbh->prepare($query);

  print "Updating articles table for $project\n";
  my $start = time();
  my $r = $sth->execute($project);
  print "Result: $r rows in "  .(time() - $start) . " seconds\n";
  return;
}

############################################################

=item B<update_project>(PROJECT, TIMESTAMP, WIKIPAGE, PARENT, SHORTNAME)

Update the project table with data for PROJECT

Parameters:

=over

=item TIMESTAMP

when PROJECT was last updated

=item WIKIPAGE

wikipeida homepage for PROJECT

=item PARENT

Parent project, or undef

=item SHORTNAME

Abbreviated name to display for PROJECT

=back

=cut

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

  my $sth_qcount = $dbh->prepare("SELECT COUNT(r_article) FROM ratings "
	        . "WHERE r_project = ? AND r_quality='Unassessed-Class'");
  $sth_qcount->execute($project);
  @row = $sth_qcount->fetchrow_array();
  my $qcount = $proj_count - $row[0];
  print "Quality-assessed articles: $qcount\n";

  my $sth_icount = $dbh->prepare("SELECT COUNT(r_article) FROM ratings "
	       . "WHERE r_project = ? AND r_importance='Unknown-Class'");
  $sth_icount->execute($project);

  @row = $sth_icount->fetchrow_array();
  my $icount = $proj_count - $row[0];
  print "Importance-assessed articles: $icount\n";
	
  my $sth = $dbh->prepare ("UPDATE projects SET p_timestamp  = ?, "
                         . " p_wikipage = ?, p_parent = ?, p_shortname = ?," 
                         . " p_count  = ?, p_qcount = ?, p_icount  = ? "
                         . " WHERE p_project = ?" );

  my $count = $sth->execute($timestamp, $wikipage, $parent, 
                            $shortname, $proj_count, $qcount, 
			    $icount, $project);

  if ( $count eq '0E0' ) { 
    $sth = $dbh->prepare ("INSERT INTO projects VALUES (?,?,?,?,?,?,?,?)");
    $count = $sth->execute($project, $timestamp, $wikipage, 
                           $parent, $shortname, $proj_count, $qcount, $icount);
  }

  update_category_data( $project, 'Unknown-Class', 'quality', 
                        '', 10, 'Unassessed-Class'); 
  update_category_data( $project, 'Unknown-Class', 'importance',
                        '', 10, 'Unassessed-Class');

}

############################################################
## Query project table for a particular project

=item B<project_exists>(PROJECT)

Returns true if PROJECT exists in the I<projects> table, false otherwise

=cut

sub project_exists {
  my $project = shift;
  $project = encode("utf8", $project);

  my $sth = $dbh->prepare ("SELECT * FROM projects WHERE p_project = ?");
  my $r = $sth->execute($project);

  return ($r == 1 ? 1 : 0);
}

############################################################

=item B<get_project_ratings>(PROJECT, TYPE)

Fetch assessments of TYPE for PROJECT. 

Returns a hash: C<article> => C<rating>

=cut

sub get_project_ratings {
  my $project = shift;
  my $type = shift;

  if ( ! ( $type eq 'quality' || $type eq 'importance') ) { 
    die "Bad type: $type\n";
  }

  print "Getting $type ratings for $project from database\n";

  $project = encode("utf8", $project);

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

=item B<db_commit>()

Commit current DB transaction

=cut

sub db_commit { 
  print "Commit database\n";
  $dbh->commit();
  return 0;
}

############################################################

=item B<db_rollback>()

Rollback current DB transaction

=cut

sub db_rollback { 
  print "Rollback database\n";
  $dbh->rollback();
  return 0;
}

############################################################

=item B<db_cleanup_project>(PROJECT)

Deletes data forr articles that were once assessed but aren't
anymore. Also gets rid of NULL values in I<ratings> table.

First, delete rows from I<ratings> table for PROJECT where
quality and importance are both C<Unknown-Class>. Then
replace any NULL I<ratings> quality or importance values
with C<Unknown-Class>.

=cut

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

=item B<db_connect>()

Connect to DB. Runs automatically when file is loaded.

Parameters:

=over

=item OPTS

The options hash returned by read_conf()

=back

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

=item B<db_list_projects>()

Returns an array ref containing all projects names in
I<projects> table

=cut

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

=item B<db_get_project_details>()

Returns a hash reference:

 PROJECT => { 'count' => COUNT, 
              'timestamp' => TIMESTAMP }

=cut

sub db_get_project_details { 
  my $sth = $dbh->prepare("SELECT p_project, p_timestamp, p_count FROM projects;");
  $sth->execute();

  my ($proj, $count, $timestamp);

  my $data ={};

  my @row;
  while( @row = $sth->fetchrow_array() ){
    $proj = decode("utf8", $row[0]);
    $timestamp = $row[1];
    $count = $row[2];
 
    $data->{$proj} = {};
    $data->{$proj}->{'count'} = $count;
    $data->{$proj}->{'timestamp'} = $timestamp;
  }
    
  return $data;
}


############################################################

=item B<update_review_data>(TIMESTAMP, ARTICLE, RATING, REV_TIMESTAMP,
PREVIOUS_RATING)

Update review status (FA, FL, GA) for ARTICLE.

=cut

sub update_review_data {
	# Process all the parameters
	my $global_timestamp = shift;
	my $art = shift;
	my $value = shift;
	my $timestamp = shift;
	my $oldvalue = shift;
	
	unless ( ($value eq 'GA') || ($value eq 'FA') || ($value eq 'FL') ) {
		print "Unrecognized review state: $value \n"; 
		return -1;
	};
		
	my $sth = $dbh->prepare ("UPDATE reviews SET rev_value = ?, " 
	. "rev_timestamp = ? WHERE rev_article = ?");
	
	# Executes the UPDATE query. If there are no entries matching the 
        # article's name in the table, the query will return 0, allowing us 
        # to create an INSERT query instead.
	my $count = $sth->execute($value, $timestamp, $art);
	
	if ( $count eq '0E0' ) { 
		$sth = $dbh->prepare ("INSERT INTO reviews VALUES (?,?,?)");
		$count = $sth->execute($value, $art, $timestamp);
	}
	
#	print "U:" . "$art // $value // $timestamp // was '$oldvalue'\n";
	
}

############################################################
## Probably needs to be merged with update_review_data()

=item B<remove_review_data>(ARTICLE, RATING, PREVIOUS_RATING)

Removes ARTICLE from I<reviews> table. Asserts RATING='None'.

=cut

sub remove_review_data {
	# Process all the parameters
	my $art = shift;
	my $value = shift;
	my $oldvalue = shift;

	unless ( ($value eq 'None') ) {
		print "Unrecognized review state: $value \n"; 
		return -1;
	}	

	my $sth = $dbh->prepare ("DELETE FROM reviews
                                  WHERE rev_value = ? AND rev_article = ?");
	# Executes the DELETE query. 
	my $count = $sth->execute($oldvalue, $art);

#	print "U:" . "$art // $value // removed // was '$oldvalue'\n";

}

############################################################

=item B<get_review_data>(RATING)

Fetch articles with review status RATING

Returns a hash ref ARTICLE => RATING

=cut

sub get_review_data {
  my $value = shift;
  my $sth;

  if ( ! defined $value ) {
    $sth = $dbh->prepare ("SELECT rev_article, rev_value
                           FROM reviews");
    $sth->execute();
  } else {
    $sth = $dbh->prepare ("SELECT rev_article, rev_value
                           FROM reviews WHERE rev_value = ?");
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

=item B<db_get_release_data>()

Get data about released articles from I<releases>

Returns a hash reference:

 PROJECT => { '0.5:category' => CAT,
              '0.5:timestamp' => TIMESTAMP }

=cut

sub db_get_release_data {
  my $sth;

  $sth = $dbh->prepare ("SELECT * FROM releases");
  $sth->execute();

  my @row;
  my $data = {};
  my ($art, $cat, $timestamp);

  while ( @row = $sth->fetchrow_array() ) {
    $art = decode("utf8", $row[0]);
    $cat = decode("utf8", $row[1]);
    $timestamp = $row[2];
    $data->{$art} = {};
    $data->{$art}->{'0.5:category'} = $cat;
    $data->{$art}->{'0.5:timestamp'} = $timestamp;
  }

  return $data;	
}

############################################################

=item B<db_set_release_data>(ARTICLE, RELEASE, CATEGORY, REV_TIMESTAMP)

<description>

Parameters:

=over

=item RELEASE

The name of the relase. Only C<0.5> is supported.

=item CATEGORY

The release category - C<Arts> etc.

=back

=cut

sub db_set_release_data { 
    my $art = shift;
    my $type = shift;
    my $cat = shift;
    my $timestamp = shift;

    $art = encode("utf8", $art);
    $cat = encode("utf8", $cat);

    if ( $type ne '0.5' ) { 
	die "Bad type: $type\n";
    }

    my $sth = $dbh->prepare("UPDATE releases
                             SET rel_0p5_category = ?, rel_0p5_timestamp = ?
                             WHERE rel_article = ?");
    my $res = $sth->execute($cat, $timestamp, $art);

    if ( $res eq '0E0' ) { 
      $sth = $dbh->prepare("INSERT INTO releases VALUES (?,?,?)");
      $sth->execute($art, $cat, $timestamp);
    }                     

}

############################################################

=item B<db_cleanup_releases>()

Remove articles from I<releases> table that are no longer 
included in any release versions.

=cut

sub db_cleanup_releases { 
    my $sth = $dbh->prepare("DELETE FROM releases 
                             WHERE rel_0p5_category = 'None'");

    my $count = $sth->execute();

    print "Cleanup releases table: $count rows removed\n";
}

############################################################

=item B<db_lock>(LOCKNAME)

Gets an advisory lock from the database. Does not block.

Returns true if the lock wa acquired, false otherwise.

=cut

sub db_lock {
  my $lock = shift;

  my $sth = $dbh->prepare("SELECT GET_LOCK(?,0)");
  my $r = $sth->execute($lock);
  my @row = $sth->fetchrow_array();
  return $row[0];
}

=item B<db_unlock>(LOCKNAME)

Release an advisory lock 

=cut

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
