use strict vars;
use Data::Dumper;
our $api;
our $global_timestamp;
our $global_timestamp_wiki;

######################################################################
# i18n

my $categoryNS = 14;

my $Articles = 'articles';   
my $By_quality = 'by quality';
my $By_importance = 'by importance';
my $Category = 'Category';
my $Lang = 'en';
my $Root_category = 'Category:Wikipedia 1.0 assessments';

my $Class = 'Class';
my $No_Class = 'No-Class';
my $Unassessed_Class = 'Unassessed-Class';
my $Assessed_Class = 'Assessed-Class';

my %Quality=('FA-Class' => 100, 'FL-Class' => 200, 'A-Class' => 300, 
             'GA-Class' => 400, 'B-Class' => 500, 'C-Class' => 600, 
             'Start-Class'=>700, 'Stub-Class' => 800, 'List-Class' => 900, 
             $Assessed_Class => 1000, $Unassessed_Class => 1100);

my %Importance=('Top-Class' => 100, 'High-Class' => 200, 
                    'Mid-Class' => 300,
                    'Low-Class' => 400, $Unassessed_Class => 1100); 

my $Extra;

my @Months=("January", "February", "March", "April", "May", "June",
            "July", "August",  "September", "October", "November", 
            "December");

######################################################################
# Download list of projects based on $Root_category

sub download_project_list {
  my ($projects, $res, $cat);

  $res = $api->pages_in_category($Root_category,$categoryNS);

  $projects = [];

  foreach $cat ( @$res ) { 
    next unless ( $cat =~ m/\Q$By_quality\E/ );
    next if (   $Lang eq 'en' 
             && $cat =~ /\Q$Category\E:Articles \Q$By_quality\E/); 
    
    $cat =~ s/^\Q$Category\E://;
    $cat =~ s/ \Q$Articles\E \Q$By_quality\E//;

    push @$projects, $cat;       
  }

  return $projects;
}

#################################################################
# Download data for one project

sub download_project {

  my $project = shift;
  print "\n-- Download ratings data for $project\n";

  download_project_quality_ratings($project);
  download_project_importance_ratings($project);

  update_project($project,$global_timestamp);
}

#################################################################
# Make list of categories storing quality data for project
# Return hash ref:  name => category
# name guaranteed to be a key in %Quality or a value in $Extra

sub get_project_quality_categories {
  my $project = shift;
  my $qcats = {};
  my $qual;

  clear_screen();
  print "--- Get project categories for $project by quality\n";

  if ( ! defined $Extra ) { 
    $Extra = get_extra_assessments();
  }

  my $cat = "Category:$project articles $By_quality";
  my $cats = $api->pages_in_category($cat, $categoryNS);
  my $value;

  foreach $cat ( @$cats ) { 
    if ( defined $Extra->{$cat} ) { 
      $qual = $Extra->{$cat}->{'class'} . "-" . $Class;
      $qcats->{$qual} = $cat;
      $value = $Extra->{$cat}->{'value'};
      print "Cat $qual $cat $value (extra)\n";
    } elsif ( $cat =~ /\Q$Category\E:(\w+)[\- ]/) {
      $qual=$1 . '-' . $Class; # e.g., FA-Class
#      print "\tCheck '$qual'\n";
      next unless (defined $Quality{$qual});
      $qcats->{$qual} = $cat;
      $value = $Quality{$qual};
      print "Cat $qual $cat $value\n";
    } else {
      next;
    }
    update_category_data( $project, $qual, 'quality', $cat, $value);
  }
 
#  die;
  return $qcats;
}

#################################################################
# Make list of categories storing importance data for project
# Return hash ref:  name => category
# name guaranteed to be a key in %Importance or a value in $Extra

sub get_project_importance_categories {
  my $project = shift;
  my $icats = {};
  my $imp;

  if ( ! defined $Extra ) { 
    $Extra = get_extra_categories();
  }

  clear_screen();

  print "--- Get project categories for $project by importance\n";

  my $cat = "Category:$project articles $By_importance";
  my $cats = $api->pages_in_category($cat, $categoryNS);
  my $value;

  if ( 0 == scalar @$cats) { 
    print "  Fall back to 'priority' naming\n";
    $cat = "Category:$project articles by priority";
    $cats = $api->pages_in_category($cat, $categoryNS);
  }

  foreach $cat ( @$cats ) { 
    if ( defined $Extra->{$cat} ) { 
      $imp = $Extra->{$cat}->{'title'} . "-" . $Class;
      $icats->{$imp} = $cat;
      $value = $Extra->{$cat}->{'value'};
      next;
    } elsif ($cat =~ /\Q$Category\E:(\w+)[\- ]/) { 
      $imp=$1 . '-' . $Class; # e.g., Top-Class
      next unless (defined $Importance{$imp});
      $icats->{$imp} = $cat;
      $value = $Importance{$imp};
    } else {
      next;
    }
    update_category_data($project, $imp, 'importance', $cat, $value);
  }

  return $icats;
}

#################################################################
# Download quality assessments for project, update database

sub download_project_quality_ratings { 
  my $project = shift;

  print "Get stored quality ratings for $project\n";

  my $oldrating = get_project_ratings($project, 'quality');

  my $seen = {};
  my $qcats = get_project_quality_categories($project);
  my ($cat, $tmp_arts, $qual, $art, $d);

  foreach $qual ( keys %$qcats ) { 
    clear_screen();
    print "Fetching list for quality $qual\t" . $qcats->{$qual} . "\n";

    $tmp_arts = $api->pages_in_category_detailed($qcats->{$qual});

    my $count = scalar @$tmp_arts;
    my $i = 0;

    foreach $d ( @$tmp_arts) {
       $i++;
       $art = $d->{'title'};

       clear_screen();
#       print "\nSee $qual : $i / $count : $art \n";

       next unless ( $art =~ /^Talk:/);
       $art =~ s/^Talk://;
       $seen->{$art} = 1;

       if ( ! defined $oldrating->{$art} ) { 
         update_article_data($global_timestamp, $project, $art, "quality", 
                             $qual, $d->{'timestamp'}, undef);
         next;
       }

       if ( $oldrating->{$art} eq $qual ) { 
         # No change
#         print "No change for $art $qual \n";
       } else {
         update_article_data($global_timestamp, $project, $art, 'quality', 
                             $qual, $d->{'timestamp'}, $oldrating->{$art} );
       } 
    }

  } 

  foreach $art ( keys %$oldrating ) { 
    next if ( exists $seen->{$art} );    
    print "NOT SEEN '$art'\n";
    update_article_data($global_timestamp, $project, $art, 'quality', 
                        'undef', $global_timestamp_wiki, 
                        $oldrating->{$art} );
  }

}

#################################################################
# Download importance assessments for project, update database

sub download_project_importance_ratings { 
  my $project = shift;

  clear_screen();
  print "Get importance ratings for $project\n";

  print "Getting old data from database\n";

  my $oldrating = get_project_ratings($project, 'importance');

  my $seen = {};
  my $icats = get_project_importance_categories($project);
  my ($cat, $tmp_arts, $imp, $art, $d);

  foreach $imp ( keys %$icats ) { 
    clear_screen();
    print "Fetching list for importance $imp\t" . $icats->{$imp} . "\n";

    $tmp_arts = $api->pages_in_category_detailed($icats->{$imp});

    my $count = scalar @$tmp_arts;
    my $i = 0;

    foreach $d ( @$tmp_arts) {
       $i++;
       clear_screen();
#       print "See $imp : $i / $count\n";
       $art = $d->{'title'};
       next unless ( $art =~ /^Talk:/);
       $art =~ s/^Talk://;
       $seen->{$art} = 1;

       if ( ! defined $oldrating->{$art} ) { 
         update_article_data($global_timestamp, $project, $art, "importance", 
                             $imp, $d->{'timestamp'}, undef);
         next;
       }

       if ( $oldrating->{$art} eq $imp ) { 
         # No change
#         print "No change for $art $imp \n";
       } else {
         update_article_data($global_timestamp, $project, $art, "importance",
                             $imp, $d->{'timestamp'}, $oldrating->{$art} );
       } 
    }
  } 

  foreach $art ( keys %$oldrating ) { 
    # for importance only, NULL values are OK
    next if ( ! defined $oldrating->{$art} ) ;
    next if ( exists $seen->{$art} );    
    print "NOT SEEN $art\n";
    update_article_data($global_timestamp, $project, $art, "importance",
                        'undef', $global_timestamp_wiki, $oldrating->{$art});
  }

}

#######################################3

sub get_extra_assessments { 
  my $data = {};

  my $res = $api->pages_in_category_detailed("X1");

  my ($r, $value, $class);
  foreach $r ( @$res ) { 
    next unless ( $r->{'title'}  =~ /^Category/);
    next unless ( $r->{'sortkey'} =~ /^\d+(\.\d+)?-/);
    ($value, $class) = split /-/, $r->{'sortkey'}, 2;
    $data->{$r->{'title'}} = { 'class' =>$class, 'value' => $value };
  }

  return $data;
}


#######################################################################
sub clear_screen {
#  system "clear";
  return 0;
}

# Load successfully
1;


__END__


