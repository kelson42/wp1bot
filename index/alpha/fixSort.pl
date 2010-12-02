while ( <STDIN> ) { 
  chomp;
  ($page, $sort) = split / /, $_, 2;
#  next if ( $sort =~ /^\s*/);
  $sort =~ s/ /_/g;
  next if( $page eq $sort);
  next if ( 1 == length $sort );
  next unless ( $sort =~ /,/);

  print "$page $sort\n";
}
