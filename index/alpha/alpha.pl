use Data::Dumper;

open IN, "<:utf8", "SortKeys.txt" or die;
while ( <IN> ) { 
  chomp;
  ($page, $sort) = split /\t/;
  next if ( $page =~ /^\s*$/ );

$k++;
if ( 0 == $k % 20 ) { print STDERR ".";}
if ( 0 == $k % 1000 ) { print STDERR  "\n";}

#  print "P: '$page' S: '$sort'\n";
  $pages->{$page} = "";

  next if ( $sort =~ /^\s*$/);

  next if ( $page =~ /^\d+$/);
  next if ( $page =~ /^\d+ BC$/);
  next if ( $page =~ /^List of /);

  next if ( 1 == length $sort );
  next if ( $sort =~ /^[*\-#]*$/);
  next if ( $sort eq "γ");
  next if ( $sort eq "!");
  next if ( $sort eq 'µ');
  next if ( $sort eq 'τ');
  next if ($sort =~ /^-\d+$/);

  $sort =~ s/^'//;
  $sort =~ s/^\*//;
  $sort =~ s/^\+//;
  $sort =~ s/^\(//;
  $sort =~ s/^\s*//;

  $pages->{$page} = ucfirst($sort);
# print "P2: '$page' S: '" . $pages->{$page} . "'\n";
}
close IN;
print STDERR "\n";

open OUT, ">:utf8", "Missing";
foreach $p ( keys %$pages ) { 
  if ( $pages->{$p} =~ /^\s*$/ ) { 
    $no ++;
    print OUT "$p\n";
    $pages->{$p} = $p;
    $pages->{$p} =~ s/^[(']*//;
#     print "P3n: '$p' S: '" . $pages->{$p} . "'\n";
  } else { 
    $yes++;
#   print "P3y: '$p' S: '" . $pages->{$p} . "'\n";
  }
}

print "No: $no\n";

foreach $p ( keys %$pages ) { 
  $initial = substr($pages->{$p},0,1);
  if ( ! ( $initial =~ /[A-Z]/ ) ) { 
    $initial = 'Misc';
  }
  if ( ! defined $lists->{$initial} ) { 
    $lists->{$initial} = [];
  }

  push @{$lists->{$initial}}, $p;
}

foreach $initial ( sort {$a cmp $b} keys %$lists ) { 

  $pagenum = 0;

  $list = [sort {$pages->{$a} cmp $pages->{$b}} 
            @{$lists->{$initial}}];

  print "'$initial': " . (scalar @$list) . "\n";

  $sublist = {};

  for ( $i = 0; $i <= scalar @$list; $i += 50 ) { 
    $max = min($i + 49, -1+scalar @$list);
    $sublist->{$i} = [@$list[$i..$max]];
  }

  $count = 0;
  foreach $sl ( sort {$a <=> $b} keys %$sublist ) { 
    if ( 0 == ($count % 10) ) { 
      print "\tOPEN NEW PAGE $initial.$sl\n";
      close OUTPUT;
      $pagenum++;
      open OUTPUT, ">", "Output/$initial$pagenum";
      binmode OUTPUT, ":utf8";
      print OUTPUT "{{Wikipedia:0.8/IndexHeader}}\n\n";
    }
    $arts = $sublist->{$sl};
    print "  $sl: " . (scalar @$arts) . " : " . ${$arts}[0] . " to " . ${$arts}[-1] . "\n"; 

    if ( defined(${$arts}[0])) { 
      print OUTPUT "== " . ${$arts}[0] . " &ndash; " . ${$arts}[-1] . " ==\n";
    }

    $arts = [map { $_ = "[[" . $_ . "]]" } @$arts];

    print OUTPUT (join "{{Dot}}\n", @$arts);
    print OUTPUT "\n\n";

    $count++;
  }
  
}


sub min { 
  my $left = shift;
  my $right = shift;
  if ( $left < $right ) { return $left; } 
  else { return $right;}
}
