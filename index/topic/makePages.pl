#!/usr/bin/perl

open IN, "<", "SortKeys.txt" or die;
while ( <IN> ) { 
  chomp;
  ($n, $s) = split / /, $_, 2;
  next if ( $s =~ /^\s*$/);
  $s =~ s/^\s*//;
  $SortKey->{$n} = $s;
#  print "Set '$n' to '$s'\n";
}
close IN;

# $t = 'Book_of_Mormon';
#print "X: " . $SortKey->{$t} . "\n";
#exit;

open IN, "<", "Selected.txt" or die;
while ( <IN> ) { 
  chomp;
  @parts = split /\|/;
  if ( ! exists $Projs->{$parts[1]} ) { 
    $Projs->{$parts[1]} = {};
  }
  $Projs->{$parts[1]}->{$parts[0]}= 1;
  if ( ! defined $SortKey->{$parts[0]} ) { 
    $SortKey->{$parts[0]} = $parts[0];
  } elsif ( 3 > length $SortKey->{$parts[0]} ) { 
     $SortKey->{$parts[0]} = $parts[0];
  }
} 
close IN;


open IN, "<", "Manual.arts.txt" or die;
while ( <IN> ) { 
  chomp;
  @parts = split /\|/;
  if ( ! exists $Projs->{$parts[1]}) { 
    $Projs->{$parts[1]} = {};
  }
  $Projs->{$parts[1]}->{$parts[0]} = 1;
  if ( ! defined $SortKey->{$parts[0]} ) { 
    $SortKey->{$parts[0]} = $parts[0];
  } elsif ( 3 > length $SortKey->{$parts[0]} ) { 
     $SortKey->{$parts[0]} = $parts[0];
  }
} 
close IN;

open IN, "<", "Pages" or die;

while ( <IN> ) { 
  print;
  chomp;
  if ( $_ =~ /==(.*)==/ ) { 
    $file = $1;
    $file =~ s/\s*$//;
    $file =~ s/^\s*//;
    print "-> File '$file'\n";
    $filename = $file;
    $filename =~ s/ /_/g;
    close OUT;
    open OUT, ">", "output/$filename";
    print OUT "{{User:SelectionBot/0.7index/Header}}\n";
    print OUT "This is the index page for '''$file'''.\n";
    next;
  } elsif ( $_ =~ /^\t/ ) {
    $_ =~ s/^\t//;
    my $source;
    my $title;

    if ( $_ =~ /:/ ) { 
      print "Stage 1a\n";
      ($source, $title) = split /\s*:\s*/, $_, 2;
      $source =~ s/^\s*//;
      $title =~ s/\s$//;
   
    } else { 
      $_ =~ s/^\s*//;
      $_ =~ s/\s$//;
      $source = $_;
      $title = $_;
    }

    if ( $title eq "" ) { 
      $title = $source;
    }

    print "-> Project '$source' with title '$title'\n";
    $c = scalar keys %{$Projs->{$source}};
    print "-> Count $c\n";
    do_proj($source, $title);
  }

}



sub do_proj {
  my $p = shift;
  my $t = shift;
  my @arts = sort { $SortKey->{$a} cmp $SortKey->{$b} } 
                  keys %{$Projs->{$p}};

  @arts = map { $_ =~ s/_/ /g; $_ = "[[$_]]";} @arts;
  
  print OUT "== $t ==\n";

#    print OUT "'$a' '" . $SortKey-> {$a}. "' - \n";

  print OUT join " — \n", @arts;
  print OUT "\n\n";

}
