use lib '/home/cbm/veblen/VeblenBot';
use strict;
use Data::Dumper;
require Mediawiki::API;

my $page;
my $file = $_;


my $debug = $ARGV[0] || 3;

my $client = Mediawiki::API->new();
$client->debug_level($debug);
$client->maxlag(15);
$client->max_retries(50);

$client->base_url('http://en.wikipedia.org/w/api.php');
$client->login_from_file('/home/cbm/veblen/api.credentials');

open FILE, "/usr/bin/find output/|" or die "$!";
$_ = <FILE>; # skip first  which is the directory itself

my $c = 0;

while ( <FILE> ) { 
  $c++;
  chomp;
  print "$c: '$_'\n";

#  next unless ( $_ =~ /United_States/ );

  $page = $_;
  $file = $_;
  $page =~ s!^output/!!;
  $page = "User:SelectionBot/0.7geo/$page";
  print "'$page'\n";

  my $text;
  open IN, "<$file";
  while ( <IN> ) { 
    $text .= $_;
  }

  $client->edit_page($page, $text, 'Upload file');


}

