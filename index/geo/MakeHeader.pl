open IN, "<", "Header.raw";

%Keys = ( 'AF' => 'Africa',
          'EA' => 'Asia and Europe',
          'OA' => 'Oceania',
          'AN' => 'Antarctica',
          'NSA' => 'North and South America' );

while ( <IN> ) { 
  $line++;
  chomp;
  ($country, $region) = split /\t/, $_, 2;
   print "$region $Keys{$region}\n";
  die "$line '$region'\n" unless ( defined $Keys{$region} );
  if ( ! defined $Areas->{$region} ) { 
    $Areas->{$region} = {};
  }
  $Areas->{$region}->{$country} = 1;
}
close IN;




open OUT, ">", "output/Header";

print OUT << "HERE";
{{Navbox with collapsible groups
| name  = User:SelectionBot/0.7geo/Header
| title = [[User:SelectionBot/0.7index|Wikipedia 0.7 index by country]]
HERE

$group = 0;

foreach $region ( sort {$Keys{$a} cmp $Keys{$b}} keys %$Areas ) { 
  $group++;
  print OUT << "HERE";
| group$group = $Keys{$region}
| list$group  = 
HERE

  @pages = ();
  foreach $page ( sort {$a cmp $b} keys %{$Areas->{$region}} ) { 
    $link = $page;
    $page =~ s/_/ /g;
    $link =~ s/ /_/g;
    $link = "User:SelectionBot/0.7geo/$link";
    push @pages, "[[$link|$page]]";
  }
  print OUT join "{{·}} ", @pages;
  print OUT "\n";

}

print OUT "}}\n";
close OUT;
