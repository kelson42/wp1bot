use lib '/home/cbm/veblen/VeblenBot';
use strict;
use Data::Dumper;
require Mediawiki::API;

my $page;
my $file = $_;


my $client = Mediawiki::API->new();
$client->debug_level(5);
$client->maxlag(15);

$client->base_url('http://en.wikipedia.org/w/api.php');
$client->login_from_file('/home/cbm/veblen/api.credentials');



