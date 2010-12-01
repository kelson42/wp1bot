use lib '/home/cbm/veblen/VeblenBot';
use strict;
use Data::Dumper;
require Mediawiki::API;

my $page;
my $file = $_;


my $client = Mediawiki::API->new();

$client->base_url('http://en.wikipedia.org/w/api.php');
$client->login_from_file('/home/cbm/veblen/api.credentials');

$client->debug_level(3);
$client->maxlag(100);

open FILE, "/usr/bin/find output/|" or die "$!";
$_ = <FILE>; # skip first  which is the directory itself
while ( <FILE> ) { 
  next unless( $_ =~ /Header/);

  chomp;
  print "R '$_'\n";
  $page = $_;
  $file = $_;
  $page =~ s!^output/!!;
  $page = "User:SelectionBot/0.7index/$page";
  print "'$page'\n";

  my $text;
  open IN, "<$file";
  while ( <IN> ) { 
    $text .= $_;
  }

  $client->edit_page($page, $text, 'Upload file');
}

