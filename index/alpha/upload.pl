use lib '/home/project/e/n/w/enwp10/VeblenBot';
use strict;
use Encode;
use Data::Dumper;
require Mediawiki::API;


my $home = '/home/project/e/n/w/enwp10';

my $page;
my $file = $_;

my $debug = $ARGV[0] || 3;

my $client = Mediawiki::API->new();
$client->debug_level($debug);
$client->maxlag(1500);
$client->max_retries(50);
$client->{'decodeprint'} = 0;

$client->base_url('http://en.wikipedia.org/w/api.php');
$client->login_from_file($home . '/api.credentials');

open FILE, "/usr/bin/find Output/|" or die "$!";
$_ = <FILE>; # skip first  which is the directory itself

my $c = 0;

while ( <FILE> ) { 
  $c++;
  chomp;
  print "$c: '$_'\n";

  $page = $_;
  $file = $_;
  $page =~ s!^Output/!!;
  $page = "Wikipedia:0.8/Index/$page";
  print "'$page'\n";

  my $text;
  open IN, "<:utf8", "$file";
  while ( <IN> ) { 
    $text .= $_;
  }

binmode STDOUT, ":utf8";
print $text;

  $client->edit_page($page, $text, 'Upload file');
#  exit;

}

