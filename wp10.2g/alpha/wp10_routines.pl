use strict vars;
use Data::Dumper;
our $api;
our $global_timestamp;
our $global_timestamp_wiki;

######################################################################
# i18n

my $categoryNS = 14;
my $talkNS = 1;

my $Articles = 'articles';   
my $By_quality = 'by quality';
my $By_importance = 'by importance';
my $Category = 'Category';
my $Lang = 'en';
my $Root_category = 'Category:Wikipedia 1.0 assessments';
my $goodCat = "$Category:Wikipedia good articles";
my $featuredCat = "$Category:Wikipedia featured articles";

my $Class = 'Class';
my $No_Class = 'No-Class';
my $Unassessed_Class = 'Unassessed-Class';
my $Assessed_Class = 'Assessed-Class';

my %Quality=( 'FA-Class' => 500, 'FL-Class' => 480, 'A-Class' => 425, 
              'GA-Class' => 400, 'B-Class' => 300, 'C-Class' => 225, 
              'Start-Class'=>150, 'Stub-Class' => 100, 'List-Class' => 80, 
              $Assessed_Class => 20, $Unassessed_Class => 0);

my %Importance=( 'Top-Class' => 400, 'High-Class' => 300, 
                 'Mid-Class' => 200, 'Low-Class' => 100, 
                 $Unassessed_Class => 0); 

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
    next if ( $Lang eq 'en' 
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


  if ( ! db_lock("PROJECT:$project") ) { 
    print "Cannot get lock for $project, exiting.\n";
    return;
  }

  print "\n-- Download ratings data for $project\n";
  my ($homepage, $parent, $extra, $shortname);
  
  eval {
	($homepage, $parent, $extra, $shortname) = 
          get_extra_assessments($project); 
	download_project_quality_ratings($project, $extra);
	download_project_importance_ratings($project, $extra);
	db_cleanup_project($project);
	update_project($project, $global_timestamp, $homepage, 
                       $parent, $shortname);
    db_commit();
	};

	if ($@) {
    print "Transaction aborted: $@";
    db_rollback();
	}

  db_unlock("PROJECT:$project");

  return 0;
}

#################################################################
# Make list of categories storing quality data for project
# Return hash ref:  name => category
# name guaranteed to be a key in %Quality or a value in $extra

sub get_project_quality_categories {
  my $project = shift;
  my $extra = shift;
  my $qcats = {};
  my $qual;

  print "--- Get project categories for $project by quality\n";

  my $cat = "Category:$project articles $By_quality";
  my $cats = $api->pages_in_category(encode("utf8",$cat), $categoryNS);
  my $value;

  foreach $cat ( @$cats ) { 
    if ( defined $extra->{$cat} ) { 
      $qual = $extra->{$cat}->{'title'};
      $qcats->{$qual} = $cat;
      $value = $extra->{$cat}->{'ranking'};
      print "Cat $qual $cat $value (extra)\n";
    } elsif ( $cat =~ /\Q$Category\E:(\w+)[\- ]/) {
      $qual=$1 . '-' . $Class; # e.g., FA-Class
      next unless (defined $Quality{$qual});
      $qcats->{$qual} = $cat;
      $value = $Quality{$qual};
      print "Cat $qual $cat $value\n";
    } else {
      next;
    }
    update_category_data( $project, $qual, 'quality', $cat, $value);
  }
 
  return $qcats;
}

#################################################################
# Make list of categories storing importance data for project
# Return hash ref:  name => category
# name guaranteed to be a key in %Importance or a value in $extra

sub get_project_importance_categories {
  my $project = shift;
  my $extra = shift;
  my $icats = {};
  my $imp;

  print "--- Get project categories for $project by importance\n";

  my $cat = "Category:$project articles $By_importance";
  my $cats = $api->pages_in_category(encode("utf8",$cat), $categoryNS);
  my $value;

  if ( 0 == scalar @$cats ) { 
    print "Fall back to 'priority' naming\n";
    $cat = "Category:$project articles by priority";
    $cats = $api->pages_in_category(encode("utf8",$cat), $categoryNS);
  }

  foreach $cat ( @$cats ) { 
    if ( defined $extra->{$cat} ) { 
      $imp = $extra->{$cat}->{'title'};
      $icats->{$imp} = $cat;
      $value = $extra->{$cat}->{'ranking'};
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
  my $extra = shift;

  print "Get stored quality ratings for $project\n";

  my $oldrating = get_project_ratings($project, 'quality');
  my $newrating = {};

  my $seen = {};
  my $qcats = get_project_quality_categories($project, $extra);
  my ($cat, $tmp_arts, $qual, $art, $d);

  foreach $qual ( keys %$qcats ) { 
    print "\nFetching list for quality $qual\n";

    $tmp_arts = $api->pages_in_category_detailed(encode("utf8",$qcats->{$qual}));

    my $count = scalar @$tmp_arts;
    my $i = 0;

    foreach $d ( @$tmp_arts ) {
       $i++;
       $art = $d->{'title'};
       next unless ( $art =~ /^Talk:/);

       $art =~ s/^Talk://;
       $seen->{$art} = 1;

       if ( ! defined $oldrating->{$art} ) { 
         update_article_data($global_timestamp, $project, $art, "quality", 
                             $qual, $d->{'timestamp'}, 'Unknown-Class');
         next;
       }

       if ( $oldrating->{$art} eq $qual ) {
         # No change
       } else {
         update_article_data($global_timestamp, $project, $art, 'quality', 
                             $qual, $d->{'timestamp'}, $oldrating->{$art} );
       } 
    }
  } 




  foreach $art ( keys %$oldrating ) { 
    next if ( exists $seen->{$art} );   
    next if ( $oldrating->{$art} eq 'Unknown-Class' ); 
    print "NOT SEEN (quality) '$art'\n";
    update_article_data($global_timestamp, $project, $art, 'quality', 
                        'Unknown-Class', $global_timestamp_wiki, 
                        $oldrating->{$art} );
  }

  return 0;
}

#################################################################
# Download importance assessments for project, update database

sub download_project_importance_ratings { 
  my $project = shift;
  my $extra = shift;

  print "Get importance ratings for $project\n";

  print "Getting old data from database\n";
  my $oldrating = get_project_ratings($project, 'importance');

  my $seen = {};
  my $icats = get_project_importance_categories($project, $extra);
  my ($cat, $tmp_arts, $imp, $art, $d);

  foreach $imp ( keys %$icats ) { 
    print "\nFetching list for importance $imp\n";

    $tmp_arts = $api->pages_in_category_detailed(encode("utf8",$icats->{$imp}));

    my $count = scalar @$tmp_arts;
    my $i = 0;

    foreach $d ( @$tmp_arts ) {
       $i++;
       $art = $d->{'title'};
       next unless ( $art =~ /^Talk:/);
       $art =~ s/^Talk://;
       $seen->{$art} = 1;

       if ( ! defined $oldrating->{$art} ) { 
         update_article_data($global_timestamp, $project, $art, "importance", 
                             $imp, $d->{'timestamp'}, 'Unknown-Class');
         next;
       }

       if ( $oldrating->{$art} eq $imp ) { 
         # No change
       } else {
         update_article_data($global_timestamp, $project, $art, "importance",
                             $imp, $d->{'timestamp'}, $oldrating->{$art} );
       } 
    }
  } 

  foreach $art ( keys %$oldrating ) { 
    # for importance only, NULL values are OK
    next if ( $oldrating->{$art} eq 'Unknown-Class' ); 
    next if ( exists $seen->{$art} );    
    print "NOT SEEN (importance) $art\n";
    update_article_data($global_timestamp, $project, $art, "importance",
                        'Unknown-Class', $global_timestamp_wiki, 
                        $oldrating->{$art});
  }

}

###################################################################
# Parse the ReleaseVersionParameters from the main
# category page for the project

sub get_extra_assessments { 
  my $project = shift;

  my $cat = "Category:$project articles $By_quality";
  my $txt = $api->content_section(encode("utf8", $cat), 0);
  my @lines = split /\n+/, $txt;

  my $Starter = '{{ReleaseVersionParameters';
  my $Ender = '}}';

  my ($homepage, $parent, $shortname, $line, $param, $num, $left, $right);
  my $extras = {};
  my $data = {};

  my $state = 0;
  # 0 - outside the template
  # 1 - inside the template
  # Can alternate back and forth

  # General parsing strategy is to assemble partial information into
  # the $extras hash, and then verify at the end that the info is
  # complete. If it is complete, it is added to $data to be returned

  foreach $line ( @lines ) {
    if ( $state == 0 ) { 
      if ( $line =~ /^\s*\Q$Starter\E\s*/ ) { 
        $state = 1;
      }
      next;
    } elsif ( $state == 1) { 
      if ( $line =~ /\s*}}/) { 
        $state = 0;
        next;
      }

      next unless ( $line =~ /\s*\|([^|=]*)\=([^|]*)$/ ); 
      $left = $1;
      $right = $2;

      if ( $left eq 'homepage') { 
        $homepage = substr($right, 0, 255);
      }

	  if ( $left eq 'parent') { 
        $parent = substr($right, 0, 255);
	  }

	if ( $left eq 'shortname') { 
        $shortname = substr($right, 0, 255);
	}
	
      if ( $left =~ /^extra(\d+)-(\w+)$/ ) {
        $num = $1;
        $param = $2;
        if ( ! defined $extras->{$num} ) { 
          $extras->{$num} = {};
        }
        $extras->{$num}->{$param} = $right;
      }       
      next;
    } else { 
      die "bad state $state\n";
    }
  }

  print "--\nWikiProject information from ReleaseVersionParameters template\n";

  if ( defined $homepage) { 
    print "Homepage: '$homepage'\n";
  }

  if ( defined $parent) { 
    print "Parent project: '$parent'\n";
  }

  if ( defined $shortname) { 
    print "Display name: '$shortname'\n";
  }

  print "Extra assessments:\n";

  foreach $num ( keys %$extras ) { 
    next unless ( defined $extras->{$num}->{'title'} );
    next unless ( defined $extras->{$num}->{'type'} );
    next unless ( defined $extras->{$num}->{'category'} );
    next unless ( defined $extras->{$num}->{'ranking'} );

    next unless ( $extras->{$num}->{'type'} eq 'quality'
                 || $extras->{$num}->{'type'} eq 'importance' );

    if ( ! ( $extras->{$num}->{'category'} =~ /^Category:/ ) ) { 
      $extras->{$num}->{'category'} = "Category:" .  
                                       $extras->{$num}->{'category'};
    }

    $data->{$extras->{$num}->{'category'}} = $extras->{$num};
    print Dumper($extras->{$num}); 
  }

  return ($homepage, $parent, $data, $shortname);
}

#######################################################################

sub download_review_data { 

  eval {
    download_review_data_internal();
    db_commit();
  };

  if ($@) {
    print "Transaction aborted: $@";
    db_rollback();
  }
}

#######################################################################

sub download_review_data_internal {
	my (%rating);
	
	# Get older featured and good article data from database
	my ($oldrating) = get_review_data();
	
	my $seen = {};
	my %qcats = ('GA', $goodCat, 'FA', $featuredCat);
	my ($cat, $tmp_arts, $qual, $art, $d);
	
	foreach $qual ( keys %qcats ) { 
		print "\nFetching list for $qual\n";
		
		$tmp_arts = $api->pages_in_category_detailed(encode("utf8",%qcats->{$qual}));
		
		my $count = scalar @$tmp_arts;
		my $i = 0;
		
		foreach $d ( @$tmp_arts ) {
			$i++;
			$art = $d->{'title'};
			next unless ( $art =~ /^Talk:/);
			
			$art =~ s/^Talk://;
			$seen->{$art} = 1;
			
			# New entry
			if ( ! defined %$oldrating->{$art} ) { 
				update_review_data($global_timestamp, $art, $qual, $d->{'timestamp'}, 'None');
				#print $global_timestamp . " " . $art . " " . $qual . $d->{'timestamp'} . "\n";
				next;
			}
			
			# Old entry, although it could have been updated, so we need to check
			if ( %$oldrating->{$art} eq $qual ) {
				# No change
			} else {
				update_review_data($global_timestamp, $art, $qual, $d->{'timestamp'}, %$oldrating->{$art});
				#print $global_timestamp . " " . $art . " " . $qual . " " . $d->{'timestamp'} . " " . %$oldrating->{$art};
			} 
		}
	} 
	
	# Check if every article from the old listing is available
	foreach $art ( keys %$oldrating ) { 
		next if ( exists $seen->{$art} );   
		print "NOT SEEN ($oldrating->{$art}) '$art' \n";
		remove_review_data($art, 'None', $oldrating->{$art});
	}
	return 0;
}

# Load successfully
1;

__END__
