while (<STDIN> ) { 
  if ( /\{\{flag\|([^}]*)}}/ ) { 
    print "$1\n";
  }
}
