$initial = "";
$count = 0;

while ( $file = <STDIN> ) { 
  chomp $file;
  open IN, "<", "Output/$file" or die "$!";
  $a = "";
  while ( $l = <IN> ) { 
    $a .= $l;
  }
  close IN;

  $a =~ /\[\[(.*?)]]/s;
  $first = $1;
  $a =~ /.*\[\[(.*?)]]/s;
  $last = $1;

  $newinitial = $file;
  $newinitial =~ s/\d*$//;
  unless ( $newinitial eq $initial ) { 
    $count++;
    print "| group$count = $newinitial\n";
    print "| list$count  = \n";
    $initial = $newinitial;
  }

  print "[[Wikipedia:0.8/Index/$file|$first &ndash; $last]]{{dot}} \n";
}

