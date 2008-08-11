#!/usr/bin/perl

use lib '/home/veblen/perl/lib';
use PerlIO::gzip;
use Encode;
use BerkeleyDB;

binmode STDOUT, ":utf8";

open IN, "<:gzip", $ARGV[0] or die;
binmode IN, ":utf8";

unlink 'DBm/HC.db';
unlink 'DBm/IW.db';
unlink 'DBm/PL.db';

$now = time();

tie %HC, 'BerkeleyDB::Hash', -Flags => DB_CREATE, 
       -Filename => 'DBm/HC.db', -Nelem => 2000000
  or die "Couldn't tie NDBM file hc: $!; aborting";
tie %IW, 'BerkeleyDB::Hash', -Flags => DB_CREATE, 
       -Filename => 'DBm/IW.db', -Nelem => 2000000
 or die "Couldn't tie NDBM file iw: $!; aborting";
tie %PL, 'BerkeleyDB::Hash', -Flags => DB_CREATE, 
       -Filename => 'DBm/PL.db', -Nelem => 2000000
 or die "Couldn't tie NDBM file pl: $!; aborting";

while ( <IN> ) { 
  $i ++;
  if (( $i % 50000 ) == 0) { 
    print "$i elapsed: ". (time() - $now) . "\n";
  }
  chomp;
  
  ($id, $name, $iwcount, $linkcount, $hitcount) = split / /, $_, 5;

  my $safename = encode('utf8', $name);
  
  $HC{$safename} = $hitcount;
  $IW{$safename} = $iwcount;
  $PL{$safename} = $linkcount;
}
close IN;

untie %HC;
untie %PL;
untie %IW;

print "Total time: " . (time() - $now) . "\n";

