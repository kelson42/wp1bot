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
  my $sort = $tdata->{'SortImp'};

  my $code = << "HERE";
{| class="ratingstable wikitable plainlinks"  style="text-align: right;"
|- 
! colspan="7" class="ratingstabletitle" | $title
|-
HERE

  my $imp;
  foreach $imp ( sort { $sort->{$b} <=> $sort->{$a} } keys %$ratings ) { 
    $code .= "! " . $tdata->{'ImportanceLabels'}->{$imp} . "\n";
  }

  $code .= "! | '''Total'''\n";
  $code .= "|-\n";

  my $total = 0;
  foreach $imp ( sort { $sort->{$b} <=> $sort->{$a} } keys %$ratings ) { 
    $code .= "|| " . format_cell_pqi($proj, 'NA-Class', 
                                     $imp, $ratings->{$imp} )
             . "\n";
    $total += $ratings->{$imp};
  }
  $code .= "|| " . format_cell_pqi($proj, undef, undef, $total) . "\n";
  $code .= "|}";

  return $code;

}

sub custom_roads_table_1 {

  my $RoadProjectData = [
    'IH' => 'Interstate Highway System',
    'USH' => 'U.S. Highway system',
    'Auto trail' => 'U.S. auto trail',
    'Alabama' => 'Alabama road transport',
    'Alaska' => 'Alaska road transport',
    'Arizona' => 'Arizona road transport',
    'Arkansas' => 'Arkansas road transport',
    'California' => 'California road transport',
    'Colorado' => 'Colorado road transport',
    'Connecticut' => 'Connecticut road transport',
    'Delaware' => 'Delaware road transport',
    'D.C.' => 'District of Columbia road transport',
    'Florida'=> 'Florida road transport',
    'Georgia' => 'Georgia (U.S. state) road transport',
    'Guam' => 'Guam road transport',
    'Hawaii' => 'Hawaii road transport',
    'Idaho' => 'Idaho road transport',
    'Illinois' => 'Illinois road transport',
    'Indiana' => 'Indiana road transport',
    'Iowa' => 'Iowa road transport',
    'Kansas' => 'Kansas road transport',
    'Kentucky' => 'Kentucky road transport',
    'Louisiana' => 'Louisiana road transport',
    'Maine' => 'Maine road transport',
    'Maryland' => 'Maryland road transport',
    'Massachusetts' => 'Massachusetts road transport',
    'Michigan' => 'Michigan road transport',
    'Minnesota' => 'Minnesota road transport',
    'Mississippi' => 'Mississippi road transport',
    'Missouri' => 'Missouri road transport',
    'Montana' => 'Montana road transport',
    'Nebraska' => 'Nebraska road transport',
    'Nevada' => 'Nevada road transport',
    'New Hampshire' => 'New Hampshire road transport',
    'New Jersey' => 'New Jersey road transport',
    'New Mexico' => 'New Mexico road transport',
    'New York' => 'New York road transport',
    'North Carolina' => 'North Carolina road transport',
    'North Dakota' => 'North Dakota road transport',
    'Ohio' => 'Ohio road transport',
    'Oklahoma' => 'Oklahoma road transport',
    'Oregon' => 'Oregon road transport',
    'Pennsylvania' => 'Pennsylvania road transport',
    'Puerto Rico' => 'Puerto Rico road transport',
    'Rhode Island' => 'Rhode Island road transport',
    'South Carolina' => 'South Carolina road transport',
    'South Dakota' => 'South Dakota road transport',
    'Tennessee' => 'Tennessee road transport',
    'Texas' => 'Texas road transport',
    'U.S. Virgin Islands' => 'U.S. Virgin Islands road transport',
    'Utah' => 'Utah road transport',
    'Vermont' => 'Vermont road transport',
    'Virginia' => 'Virginia road transport',
    'Washington' => 'Washington road transport',
    'West Virginia' => 'West Virginia road transport',
    'Wisconsin' => 'Wisconsin road transport',
    'Wyoming' => 'Wyoming road transport',
    'USRD' => 'U.S. road transport'
  ];

  my $RoadProjectsGrey = {
    'IH' => 1
  };
   
  my $i;
  my $RoadProjects = [];
  my $RoadProjectCats = {};
  for ( $i = 0; $i < scalar @$RoadProjectData; $i+= 2) { 
    push @$RoadProjects, $RoadProjectData->[$i];
    $RoadProjectCats->{$RoadProjectData->[$i]} 
                         = $RoadProjectData->[$i+1];
  }

  my $Classes = {
    'FA-Class' =>    {'sort'=>1, 'weight'=>0, 'name'=>'FA'},
    'A-Class' =>     {'sort'=>2, 'weight'=>1, 'name'=>'A'},
    'GA-Class' =>    {'sort'=>3, 'weight'=>2, 'name'=>'GA'},
    'B-Class' =>     {'sort'=>4, 'weight'=>3, 'name'=>'B'},
    'C-Class' =>     {'sort'=>5, 'weight'=>4, 'name'=>'C'},
    'Start-Class' => {'sort'=>6, 'weight'=>5, 'name'=>'Start'},
    'Stub-Class' =>  {'sort'=>7, 'weight'=>6, 'name'=>'Stub'},
  };

  my $dbh = database_handle();

  my $sth = $dbh->prepare('select r_quality, count(r_article) as num 
                             from ratings 
                              where r_project  = ? 
                              and r_namespace = 0 
                              group by r_quality');

  my ( $proj, $cat, $data, $class, $weight, $omega, $total, $num);

  my $text = << "HERE";
{|class="wikitable sortable"
|-
!State
!{{FA-Class|category=Category:FA-Class U.S. road transport articles}}
!{{A-Class|category=Category:A-Class U.S. road transport articles}}
!{{GA-Class|category=Category:GA-Class U.S. road transport articles}}
!{{B-Class|category=Category:B-Class U.S. road transport articles}}
!{{C-Class|category=Category:C-Class U.S. road transport articles}}
!{{Start-Class|category=Category:Start-Class U.S. road transport articles}}
!{{Stub-Class|category=Category:Stub-Class U.S. road transport articles}}
!&#969;
!&#937;
HERE

$i = 0;

  foreach $proj ( @$RoadProjects ) { 
    $omega = 0;
    $total = 0;

    $text .= "|-\n";

    if ( defined $RoadProjectsGrey->{$proj} ) { 
      $text .= "!bgcolor=silver|";
    } else { 
      $text .= "!";
    }

    $text .= "[[Wikipedia:Version 1.0 Editorial Team/" 
                 . $RoadProjectCats->{$proj}
              . " articles by quality statistics|" . $proj . "]]\n";

    $cat = $RoadProjectCats->{$proj};

    $sth->execute($cat);
    $data = $sth->fetchall_hashref('r_quality');

    foreach $class ( sort { $Classes->{$a}->{'sort'} 
                            <=> $Classes->{$b}->{'sort'} } 
                     keys %$Classes ) { 
      $weight = $Classes->{$class}->{'weight'};
      if ( ! defined $data->{$class} ) { 
        $num = 0;
      } else { 
        $num = $data->{$class}->{'num'};
      }

      if ( defined $RoadProjectsGrey->{$proj} ) { 
        $text .= "|bgcolor=silver";
      }  
      $text .= "|$num\n";

      $total += $num;
      $omega += $num * $weight;
   }

   if ( defined $RoadProjectsGrey->{$proj} ) { 
     $text .= "|bgcolor=silver";
   }  
   $text .= "|$omega\n";

   if ( defined $RoadProjectsGrey->{$proj} ) { 
     $text .= "|bgcolor=silver";
   }  

   if ( $total > 0 ) { 
     $text .= "|" . (sprintf("%2.4f", $omega/ $total)) . "\n";
   } else { 
      $text .= "|&ndash;\n";   
   }

   $i++;
 }

  $text .= "|}";
  return $text;

}

1;

