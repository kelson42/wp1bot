use strict;

# Table for the Ships project, supposed to only have a few
# of the quality classes in it. 

sub custom_ships_table_1 {
  my $proj = 'Ships';
  my $title = 'WikiProject Ships articles by quality and importance';
  my $tdata = fetch_project_table_data($proj, undef, undef, $title);

  my $GoodClasses = { 'FA-Class' => 1,
                      'A-Class' => 1,
                      'GA-Class' => 1,
                      'B-Class' => 1,
                      'C-Class' => 1,
                      'Start-Class' => 1,
                      'Stub-Class' => 1,
                      'List-Class' => 1,
                      'Book-Class' => 1,
                      };

  my $data = $tdata->{'data'};
  my $key;
  foreach $key ( keys %$data ) { 
    if ( ! defined $GoodClasses->{$key} ) { 
      delete $data->{$key};
    }
  }

  my $format = \&format_cell_pqi;

  my $code = make_project_table_wikicode($tdata, $title, 
                              $format, 
                              { 'noassessed' => 'true'} );

  return $code;
}

sub custom_essays_table_1 { 
  my $proj = 'Wikipedia essays';
  my $title = 'Wikipedia essays by importance';
  my $tdata = fetch_project_table_data($proj, undef, undef, $title);

  my $ratings = $tdata->{'data'}->{'NA-Class'};
  print Dumper($ratings);

  my $sort = $tdata->{'SortImp'};

  my $code = << "HERE";
{| class="ratingstable wikitable plainlinks"  style="text-align: right;"
|- 
! colspan="7" class="ratingstabletitle" | $title
|-
HERE

  my $imp;
  foreach $imp ( sort { $sort->{$b} <=> $sort->{$a} } keys %$ratings ) { 
    print "R $imp \n";
    $code .= "! " . $tdata->{'ImportanceLabels'}->{$imp} . "\n";
  }

  $code .= "! | '''Total'''\n";
   $code .= "|-\n";

  my $total = 0;
  foreach $imp ( sort { $sort->{$b} <=> $sort->{$a} } keys %$ratings ) { 
    print "R $imp \n";
    $code .= "|| " . format_cell_pqi($proj, 'NA-Class', 
                                     $imp, $ratings->{$imp} )
             . "\n";
    $total += $ratings->{$imp};
  }
  $code .= "|| " . format_cell_pqi($proj, undef, undef, $total) . "\n";
  $code .= "|}";

  return $code;

}

1;

