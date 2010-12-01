open IN, "<", "Header";

while ( <IN> ) { 
  chomp;
  if ( $_ =~ /^\*/ ) { 
    $_ =~ s/^\*\s*//;
    $_ =~ s/\s*$//;
    $area = $_;
    print "Area: '$area'\n";
  } elsif ( $_ =~ /^==/ ) { 
    $_ =~ s/^[= ]*//;
    $_ =~ s/[ =]*$//;
    $page = $_;
    print "\tpage: '$page'\n";

    if ( ! defined $Areas->{$area} ) { 
      $Areas->{$area} = {};    
    }
    $Areas->{$area}->{$page} = 1;

  }
}


open OUT, ">", "output/Header";

print OUT << "HERE";
{{Navbox with collapsible groups
| name  = User:SelectionBot/0.7index/Header
| title = [[User:SelectionBot/0.7index|Wikipedia 0.7 topical index]]
HERE

$group = 0;

foreach $area ( sort {$a cmp $b} keys %$Areas ) { 
  $group++;
  print OUT << "HERE";
| group$group = $area
| list$group  = 
HERE
  @pages = ();
  foreach $page ( sort {$a cmp $b} keys %{$Areas->{$area}} ) { 
    $link = $page;
    $link =~ s/ /_/;
    $link = "User:SelectionBot/0.7index/$link";
    push @pages, "[[$link|$page]]";
  }
  print OUT join "{{·}} ", @pages;
  print OUT "\n";
}

print OUT "}}\n";
close OUT;


