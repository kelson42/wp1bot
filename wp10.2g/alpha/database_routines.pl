use strict vars;
use Data::Dumper;

$Data::Dumper::Sortkeys = 1;

use DBI;
my $pw = `/home/veblen/pw-db.sh`;
my $dbh = DBI->connect('DBI:mysql:wp10', 'wp10user', $pw)
                or die "Couldn't connect to database: " . DBI->errstr;

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

  print "\nU:" 
      . "$project // $art // $timestamp // $value // was '$oldvalue'\n";

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

#  print "CAT $category SORTKEY $ranking \n";

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

  if ( ! ( $type eq 'importance' || $type eq 'quality' ) ) { 
    die "Bad ratings type:  $type\n";
  }

#  $project = encode("utf8", $project);
#  $article = encode("utf8", $article);
#  $rating = encode("utf8", $rating);

  if ( $rating eq 'undef' ) { undef $rating; }

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

  my $sth = $dbh->prepare ( "UPDATE projects SET p_timestamp  = ?, "
                          . "p_wikipage = ?, p_parent = ? " .
                            "WHERE p_project = ?" );

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


############################################################

############################################################

############################################################

# Load successfully
1;


__END__


