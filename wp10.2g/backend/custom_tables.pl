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

1;

