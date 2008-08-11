#!/usr/bin/perl

use lib '/home/veblen/perl/lib';
use PerlIO::gzip;
use Encode;
use BerkeleyDB;

binmode STDOUT, ":utf8";

open IN, "<:gzip", $ARGV[0] or die;
binmode IN, ":utf8";

unlink 'DBm/RD.db';

$now = time();

tie %RD, 'BerkeleyDB::Hash', -Flags => DB_CREATE, 
       -Filename => 'DBm/RD.db', -Nelem => 2000000
  or die "Couldn't tie NDBM file hc: $!; aborting";

while ( <IN> ) { 
  $i ++;
  if (( $i % 50000 ) == 0) { 
    print "$i elapsed: ". (time() - $now) . "\n";
  }
  chomp;
  ($a, $b) = split / /,$_, 2;
  my $safename = encode('utf8', $a);
  my $safeb = encode('utf8', $b)  ;

  $RD{$safename} = $safeb;
}
close IN;

untie %RD;

print "Total time: " . (time() - $now) . "\n";

