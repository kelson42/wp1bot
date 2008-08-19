#!/usr/bin/perl

# link(2) based locking functions

use URI::Escape;

############################################################

sub my_clean_locks { 
  my $dir = shift;
  my $lock = shift;
  open IN, "find $dir -printf '%f %n\n'|";
  while ( <IN> ) { 
    next unless ( $_ =~ /\Q$lock\E\.(\d*) (\d*)/ );
    $p = $1; $c = $2;
    if ( ! -e "/proc/$p" ) { 
      print "Cleaning abandoned $dir/$lock.$p\n";
      unlink "$dir/$lock.$p";
    } else { 
      print "$dir/$lock.$p seems ok\n";
    }
  }
}

############################################################

sub my_lock { 
  my $dir = shift;
  my $lock = shift;

  $lock = escape_lock($lock);

  my_clean_locks($dir, $lock);

  if ( -e "$dir/$lock" ) { 
    my $c = (stat "$dir/$lock")[3];
    if ( $c > 1 ) { 
      return "Already locked: $dir/$lock\n"; 
    } else { 
      print "Cleaning orphaned lock file: $dir/$lock\n"; 
      unlink "$dir/$lock";
    }
  }

  open OUT, ">", "$dir/$lock.$$";
  print OUT $$ . "\n";

  if ( link("$dir/$lock.$$", "$dir/$lock") ) { 
    return "";
  } else { 
    return "Failed to acquire lock; simultaneous attempts";
  }
}

############################################################

sub my_unlock { 
  my $dir = shift;
  my $lock = shift;

  $lock = escape_lock($lock);

  unlink "$dir/$lock";
  unlink "$dir/$lock.$$";
}

############################################################

sub escape_lock { 
  my $lock = shift;
  return uri_escape($lock);
}

############################################################


#Load successfully
1;
