use Encode;
use lib '/home/cbm/veblen/VeblenBot';
use strict;
use Data::Dumper;
require Mediawiki::API;

my $page;
my $file = $_;


my $client = Mediawiki::API->new();
$client->debug_level(5);
$client->maxlag(400);

$client->base_url('http://en.wikipedia.org/w/api.php');
#$client->login_from_file('/home/cbm/veblen/api.credentials');

print "Pass: ";
my $pw = <STDIN>;
chomp $pw;
$client->login('CBM',$pw);

my $res = $client->makeXMLrequest(['action'=>'query',
                         'list'=>'allpages',
                         'apprefix'=>'SelectionBot/0.7index',
                         'apnamespace'=>'2',
                         'format'=>'xml',
                         'aplimit'=>'200']);



my $r = $res->{'query'}->{'allpages'}->{'p'};

$res = $client->makeXMLrequest(['action'=>'query',
                                'prop'=>'info',
                                'intoken'=>'delete',
                                'titles'=>'Foo','format'=>'xml']);

my $token = $res->{'query'}->{'pages'}->{'page'}->{'deletetoken'};
print "Token: $token\n";	


my @l;
my $p;
foreach $p ( @$r) { 
  print Dumper($p);
  print "Delete [ynq]? ";
  my $a = <STDIN>;

  die if ( $a =~ /q/);
  next unless ( $a =~ /y/);
  print "\twill delete\n";
  push @l, $p->{'title'};
}

foreach $p ( @l) { 
  my $res = $client->makeXMLrequest(['action'=>'delete',
                                     'title'=> encode("utf8", $p),
                                     'token'=>$token,
                                     'reason'=>'clean up (semi-automated)',
                                     'format'=>'xml' ] );

  print Dumper($res);
}


