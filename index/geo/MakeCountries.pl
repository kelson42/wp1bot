#!/usr/bin/perl

use Data::Dumper;

use strict;
my $cat;
my $country;
my $CatToCountry;
my @countries;
my @cats;


my $IsACountry;
open IN, "<", "Countries";
while ( <IN> ) { 
  chomp;
  $IsACountry->{$_} = 1;
}
close IN;

open IN, "<", "Matched.cats";
while ( <IN> ) { 
  chomp;
  ($cat, $country) = split /\t/, $_, 2;
  @countries = split /; /, $country;
  if ( ! defined $CatToCountry->{$cat} ) { 
    $CatToCountry->{$cat} = [];
  }
  foreach $country ( @countries) { 
    push @{$CatToCountry->{$cat}}, $country;
  }
}
close IN;

my $art;
my $CountryToArt;

open IN, "<", "Categories";
while ( <IN> ) { 
  chomp;
  ($art, $cat) = split / /, $_, 2;
  if ( defined $CatToCountry->{$cat} ) { 
    foreach $country ( @{$CatToCountry->{$cat}} ) { 
      if ( ! defined $CountryToArt->{$country} ) { 
        $CountryToArt->{$country} = {};
      }
      $CountryToArt->{$country}->{$art} = 1;
    }
  }
}

close IN;

my @parts;
my $ProjectToCat;

my $project;

open IN, "<", "ProjectToCat";
while ( <IN> ) { 
 chomp;
 ($project, $cat)   = split /\t/, $_, 2;
  @cats =  split /,/, $cat;  

  foreach $cat ( @cats ) { 
    next unless ( $cat =~ /./ ) ;
    $cat =~ s/\s*//g;
    $ProjectToCat->{$project} = $cat;
  }
} 
close IN;

my @parts;
my $ArtToProj;
open IN, "<", "Selected.txt";
while ( <IN> ) {
  chomp;
  @parts = split /\|/;
  if ( ! defined $ArtToProj->{$parts[0]} ) { 
    $ArtToProj->{$parts[0]} = [];
  }
  push @{$ArtToProj->{$parts[0]}}, $parts[1];
}
close IN;

open IN, "<", "Manual.arts.txt";
while ( <IN> ) {
  chomp;
  @parts = split /\|/;
  if ( ! defined $ArtToProj->{$parts[0]} ) { 
    $ArtToProj->{$parts[0]} = [];
  }
  push @{$ArtToProj->{$parts[0]}}, $parts[1];
}
close IN;



my $ArtToCat;
my $proj;

### Now join $ArtToProj and $ProjectToCat
foreach $art ( keys %$ArtToProj ) { 
  $ArtToCat->{$art} = {};
  foreach $proj ( @{$ArtToProj->{$art}} ) {   
    if ( defined $ProjectToCat->{$proj} ) { 
      $ArtToCat->{$art}->{$ProjectToCat->{$proj}} = 1;
    }
  }
}


open IN, "<", "Manual.ArtsToCat.txt";
while ( <IN> ) { 
  chomp;
  ($art, $cat) = split /\t/, $_, 2;
  @cats = split /,\s*/, $cat;
  if ( ! defined $ArtToCat->{$art}) {  
    $ArtToCat->{$art} = {};  
  }
  foreach $cat ( @cats ) { 
     $ArtToCat->{$art}->{$cat} = 1;
  }
}
close IN;


# Many many articles are marked as "geographical". If they
# fall into any other category, don't also display them
# in the geography category.

foreach $art ( keys %$ArtToCat ) { 
  if ( 1 < scalar keys %{$ArtToCat->{$art}} ) {
    delete $ArtToCat->{$art}->{'G'};
  }
}


#######################################################################



my %Keys = ( 
  'Arts' => 'Arts, language, and literature',
  'LL' => 'Arts, language, and literature',
  'PR' => 'Philosophy and religion',
  'EL' => 'Everyday life',
  'SSS' => 'Society and social sciences',
  'G' => 'Geography',
  'H' => 'History',
  'AST' => 'Applied sciences and technology',
  'M' => 'Mathematics',
  'NS' => 'Natural sciences',
  'Bio' => 'Biography',

  'O' => 'Other'
);


my $key;
my $table;
my @arts;
my @tarts;
my $filename;

#open OTHER, ">", "output/Other";

foreach $country ( keys %{$CountryToArt} ) { 

#  next unless ( $country =~ /United States/);

  print "Country '$country'\n";

  my $dcountry = $country; # Displayed title
  if ( $dcountry eq 'Bosnia' ) { 
    $dcountry = 'Bosnia and Herzegovina';
  }

  $dcountry =~ s/_/ /g;

  $filename = $dcountry;
  $filename =~ s/ /_/g;
  close OUT;
  open OUT, ">", "output/$filename";

  print OUT << "HERE";

{{User:SelectionBot/0.7geo/Header}}

This is an index of pages related to '''$dcountry'''.

__TOC__

HERE

  $table = {};

  ##  Create table
  foreach $art ( keys %{$CountryToArt->{$country}} ) { 
    next if ( defined $IsACountry->{$art} ) ;

    if ( defined $ArtToCat->{$art} ) { 
      @cats = keys %{$ArtToCat->{$art}};
    } else { 
      @cats = ('O');
    }

    foreach $cat ( @cats ) { 
      if ( ! defined $table->{$cat} ) { 
        $table->{$cat} = {};
      }
      $table->{$cat}->{$art} = 1;
    }
  }

  ## Display table

  foreach $cat ( sort {$Keys{$a} cmp $Keys{$b}} keys %$table ) { 
    die "Bad cat '$cat' \n" unless (defined $Keys{$cat});

    $key = $Keys{$cat};
    print OUT "== $key  ==\n";
    @arts = sort {$a cmp $b} keys %{$table->{$cat}};

    print "Cat $cat " . (scalar @arts) . "\n";

    ## The files were too large to upload to the wiki,
    ## so I have to break them into pieces

    if ( 75 > scalar @arts) { 
      @arts = map { $_ =~ s/_/ /g; $_ = "[[$_]]"; } @arts;
      print OUT join "{{·}} ", @arts;
    } else { 
      my $catfile = $cat;
      $catfile =~ s/ /_/g;

      print OUT "{{User:SelectionBot/0.7geo/$filename-$catfile}}";
      open OUTB, ">", "output/$filename-$catfile";

      my $first;
      my $last;

      while  ( 75 < scalar @arts ) { 
        @tarts = @arts[0..49];
        @arts = @arts[50..$#arts];

        $first = $tarts[0];
        $last = $tarts[$#tarts];
        $first =~ s/_/ /g;
        $last =~ s/_/ /g;

        print OUTB "=== $first to $last ===\n";
        @tarts = map { $_ =~ s/_/ /g; $_ = "[[$_]]"; } @tarts;
        print OUTB join "{{·}} ", @tarts;
        print OUTB "\n\n"; 
      }
      $first = $arts[0];
      $last = $arts[$#arts];
      $first =~ s/_/ /g;
      $last =~ s/_/ /g;

      print OUTB "=== $first to $last ===\n";
      @arts = map { $_ =~ s/_/ /g; $_ = "[[$_]]"; } @arts;
      print OUTB join "{{·}} ", @arts;

      close OUTB;
    } 

    print OUT "\n\n";

# I needed to make sure that everything was accounted for. 
#    if ( $cat eq 'O') { 
#      print OTHER join "\n", @arts;
#      print OTHER "\n";
#    }
  }
}
