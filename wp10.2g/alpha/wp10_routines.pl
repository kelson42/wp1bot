use strict vars;
use Data::Dumper;
our $global_timestamp;
our $global_timestamp_wiki;
=head1 SYNOPSIS

Routines to update the local database from information on the wiki

=head1 FUNCTIONS

=over 

=item Standard parameters:

=over 

=item PROJECT

The name of a rated project

=item EXTRA

The hash ref returned by B<get_extra_assessments>()

=back

=cut

######################################################################
# i18n

my $categoryNS = 14;
my $talkNS = 1;
my $Category = 'Category';
my $Articles = 'articles';   
my $By_quality = 'by quality';
my $By_importance = 'by importance';

my $Lang = 'en';
my $Root_category = 'Category:Wikipedia 1.0 assessments';
my $GA_category = "$Category:Wikipedia good articles";
my $FA_category = "$Category:Wikipedia featured articles";
my $FL_category = "$Category:Wikipedia featured lists";
read_conf();
my $Class = 'Class';
my $No_Class = 'No-Class';
my $Unassessed_Class = get_conf('Unassessed_Class');
my $Assessed_Class = 'Assessed-Class';

my %Quality=get_conf('quality');
my %Importance=( 'Top-Class' => 400, 'High-Class' => 300,
                 'Mid-Class' => 200, 'Low-Class' => 100,
                 $Unassessed_Class => 0);

my @Months=("January", "February", "March", "April", "May", "June",
            "July", "August",  "September", "October", "November", 
            "December");

######################################################################

=item B<download_project_list>()

Download list of all participating projects from wiki

Returns array ref 
=cut

sub download_project_list {
  my ($projects, $res, $cat);

  $res = pages_in_category($Root_category,$categoryNS);

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
=item B<download_project>(PROJECT)

Update assessment data for PROJECT

=cut

sub download_project {
  my $project = shift;

  if ( ! db_lock("PROJECT:$project") ) { 
    print "Cannot get lock for $project, exiting.\n";
    return;
  }

  print "\n-- Download ratings data for '$project'\n";
  my ($homepage, $parent, $extra, $shortname);
  
  eval {
        update_timestamps();
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

=item B<get_project_quality_categories>(PROJECT, EXTRA)

Make list of categories storing quality data for project

Each returned rating is a key in %Quality or a value in EXTRA

Returns hash ref: C<rating> => C<category>

=cut

sub get_project_quality_categories {
  my $project = shift;
  my $extra = shift;
  my $qcats = {};
  my $qual;

  print "--- Get project categories for $project by quality\n";

  my $cat = "Category:$project articles $By_quality";
#  my $cats = pages_in_category(encode("utf8",$cat), $categoryNS);
  my $cats = pages_in_category($cat, $categoryNS);
  my $value;

  foreach $cat ( @$cats ) { 
    if ( defined $extra->{$cat} ) { 
      $qual = $extra->{$cat}->{'title'};
      $qcats->{$qual} = $cat;
      $value = $extra->{$cat}->{'ranking'};
      print "\tCat $qual $value $cat (extra)\n";
    } elsif ( $cat =~ /\Q$Category\E:(\w+)[\- ]/) {
      $qual=$1 . '-' . $Class; # e.g., FA-Class
      next unless (defined $Quality{$qual});
      $qcats->{$qual} = $cat;
      $value = $Quality{$qual};
      print "\tCat $qual $value $cat \n";
    } else {
      next;
    }
    update_category_data( $project, $qual, 'quality', $cat, $value);
  }
 
  return $qcats;
}

#################################################################

=item B<get_project_importance_categories>(PROJECT, EXTRA)

Make list of categories storing importance data for project

Each returned rating is a key in %Importance or a value in EXTRA

Returns hash ref: C<rating> => C<category>

=cut

sub get_project_importance_categories {
  my $project = shift;
  my $extra = shift;
  my $icats = {};
  my $imp;

  print "--- Get project categories for $project by importance\n";

  my $cat = "Category:$project articles $By_importance";
  my $cats = pages_in_category($cat, $categoryNS);
#  my $cats = pages_in_category(encode("utf8",$cat), $categoryNS);
  my $value;

  if ( 0 == scalar @$cats ) { 
    print "Fall back to 'priority' naming\n";
    $cat = "Category:$project articles by priority";
    $cats = pages_in_category($cat, $categoryNS);
#    $cats = pages_in_category(encode("utf8",$cat), $categoryNS);
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

=item B<download_project_quality_ratings>(PROJECT, EXTRA)

Download quality assessments for project, update database

=cut

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
#    print "\nFetching list for quality $qual\n";

    $tmp_arts = pages_in_category_detailed($qcats->{$qual});

    my $count = scalar @$tmp_arts;
    my $i = 0;

    foreach $d ( @$tmp_arts ) {
       $i++;
       next if ( ($d->{'ns'} < 0) || ($d->{'ns'} == 3) 
		 || ( 0 == $d->{'ns'} % 2));
       $d->{'ns'}--;
       $art = $d->{'ns'} . ":" . $d->{'title'};
       $seen->{$art} = 1;

       if ( ! defined $oldrating->{$art} ) { 
         update_article_data($global_timestamp, $project,
			     $d->{'ns'}, $d->{'title'}, "quality",
                             $qual, $d->{'timestamp'}, 'Unknown-Class');
         next;
       }

       if ( $oldrating->{$art} eq $qual ) {
         # No change
       } else {
         update_article_data($global_timestamp, $project,
			     $d->{'ns'}, $d->{'title'}, 'quality',
                             $qual, $d->{'timestamp'}, $oldrating->{$art} );
       } 
    }
  } 

  my ($ns, $title);

  foreach $art ( keys %$oldrating ) { 
    next if ( exists $seen->{$art} );   
    next if ( $oldrating->{$art} eq 'Unknown-Class' ); 
#    print "NOT SEEN (quality) '$art'\n";
    ($ns, $title) = split /:/, $art, 2;
    update_article_data($global_timestamp, $project, 
			$ns, $title, 'quality', 
                        'Unknown-Class', $global_timestamp_wiki, 
                        $oldrating->{$art} );
  }

  return 0;
}

#################################################################

=item B<download_project_importance_ratings>(PROJECT, EXTRA)

Download importance assessments for project, update database

=cut

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
#    print "\nFetching list for importance $imp\n";

    $tmp_arts = pages_in_category_detailed($icats->{$imp});

    my $count = scalar @$tmp_arts;
    my $i = 0;

    foreach $d ( @$tmp_arts ) {
       $i++;
       next if ( ($d->{'ns'} < 0) || ($d->{'ns'} == 3) 
		 || ( 0 == $d->{'ns'} % 2));
       $d->{'ns'}--;
       $art = $d->{'ns'} . ":" . $d->{'title'};
       $seen->{$art} = 1;

       if ( ! defined $oldrating->{$art} ) { 
         update_article_data($global_timestamp, $project, 
			     $d->{'ns'}, $d->{'title'}, "importance", 
                             $imp, $d->{'timestamp'}, 'Unknown-Class');
         next;
       }

       if ( $oldrating->{$art} eq $imp ) { 
         # No change
       } else {
         update_article_data($global_timestamp, $project, 
			     $d->{'ns'}, $d->{'title'}, "importance",
                             $imp, $d->{'timestamp'}, $oldrating->{$art} );
       } 
    }
  } 

  my ($title, $ns);
  foreach $art ( keys %$oldrating ) { 
    # for importance only, NULL values are OK
    next if ( $oldrating->{$art} eq 'Unknown-Class' ); 
    next if ( exists $seen->{$art} );    
    ($ns, $title) = split /:/, $art, 2;
#    print "NOT SEEN (importance) $art\n";
    update_article_data($global_timestamp, $project, 
			$ns, $title, "importance",
                        'Unknown-Class', $global_timestamp_wiki, 
                        $oldrating->{$art});
  }

}

###################################################################

=item B<get_extra_assessments>(PROJECT)

Parse the ReleaseVersionParameters template from the main
category page for PROJECT

=cut

sub get_extra_assessments { 
  my $project = shift;

  my $cat = "Category:$project articles $By_quality";
  my $txt = content_section($cat, 0);
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

=item B<download_review_data>()

Download review data from wiki, which concerns FA, GA, etc. Update database.

=cut

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

=item B<download_review_data_internal>()

Download review data from database. This function does not commit the
database.

=cut

sub download_review_data_internal {
  my (%rating);
  
  # Get older featured and good article data from database
  my ($oldrating) = get_review_data();
	
  my $seen = {};
  my $qcats = {'GA' => $GA_category,
               'FA' => $FA_category, 
               'FL' => $FL_category };

  my ($cat, $tmp_arts, $qual, $art, $d);
	
  foreach $qual ( keys %$qcats ) { 
#    print "\nFetching list for $qual\n";
    
    $tmp_arts = pages_in_category_detailed($qcats->{$qual});
    
    my $count = scalar @$tmp_arts;
    my $i = 0;
    
    foreach $d ( @$tmp_arts ) {
      $i++;
      $art = $d->{'title'};
      next unless ( $d->{'ns'} == $talkNS );
      $seen->{$art} = 1;
      
      # New entry
      if ( ! defined %$oldrating->{$art} ) { 
	update_review_data($global_timestamp, $art, $qual, 
			   $d->{'timestamp'}, 'None');
	next;
      }
      
      # Old entry, although it could have been updated, so we need to check
      if ( %$oldrating->{$art} eq $qual ) {
	# No change
      } else {
	update_review_data($global_timestamp, $art, $qual, 
			   $d->{'timestamp'}, %$oldrating->{$art});
      } 
    }
  } 
  
  # Check if every article from the old listing is available
  foreach $art ( keys %$oldrating ) { 
    next if ( exists $seen->{$art} );   
#   print "NOT SEEN ($oldrating->{$art}) '$art' \n";
    remove_review_data($art, 'None', $oldrating->{$art});
  }
  return 0;
}

#######################################################################

=item B<download_release_data>()

Download release data from wiki, which is about release
versions such as WP 0.5. Update database.

=cut

sub download_release_data { 
  eval {
    download_release_data_internal();
    db_cleanup_releases();
    db_commit();
  };

  if ($@) {
    print "Transaction aborted: $@";
    db_rollback();
  }
}

#######################################################################

=item B<download_release_data_internal>()

Download release data from the database. This function does not
commit the database.

=cut

sub download_release_data_internal {
  my $cat = "Version 0.5 articles by category";
  my $suffix = " Version 0.5 articles";

  my $oldArts = db_get_release_data();
#  print Dumper($oldArts);

  my $res = pages_in_category($cat, $categoryNS);

  my ($type, $r, $page);
  my $seen = {};

  foreach $cat ( @$res ) {
    print "$cat\n";
    $type = $cat;
    $type =~ s/\Q$suffix\E$//;
    $type =~ s/^\Q$Category\E://;
    my $res = pages_in_category_detailed($cat);

    foreach $r ( @$res ) {
      next unless ( $r->{'ns'} == $talkNS);
      $page = $r->{'title'};

      if ( defined $oldArts->{$page}
	   && $oldArts->{$page}->{'0.5:category'} eq $type ) {
      } else { 
	print "New: $page // $type\n";
	db_set_release_data($page, '0.5', $type, $r->{'timestamp'});
      }
      $seen->{$page} = 1;
    }
  }

  foreach $page ( keys %$oldArts ) { 
    if ( ( ! defined $seen->{$page} )
	 && $oldArts->{$page}->{'0.5:category'} ne 'None' ) { 
#      print "NOT SEEN: $page\n";
      db_set_release_data($page, '0.5', 'None', $global_timestamp_wiki);
    }
  }

}
#######################################################################

=item B<update_timestamps>( )

Update the internal timestamp variables to the current time.

=cut

sub update_timestamps {
  my $t = time();
  $global_timestamp = strftime("%Y%m%d%H%M%S", gmtime($t));
  $global_timestamp_wiki = strftime("%Y-%m-%dT%H:%M:%SZ", gmtime($t));
}

#######################################################################

# Load successfully
1;

__END__
