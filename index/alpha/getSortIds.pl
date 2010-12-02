#!/usr/bin/perl

# utility.pl
# Part of WP 1.0 bot
# See the files README, LICENSE, and AUTHORS for additional information

=head1 SYNOPSIS

Make a list of selected articles and their sort keys
=cut

binmode STDOUT, ":utf8";

use strict;
use Encode;
use Data::Dumper;
use POSIX;
use Getopt::Long;


#############################################################
# Define global variables and then load subroutines

require 'read_conf.pl';
our $Opts = read_conf(); # Also initializes library paths

require 'database_routines.pl';

my $dbh = database_handle();

my $sth = $dbh->prepare("select ws_article from workingselection");

$sth->execute();;

my $arts = $sth->fetchall_arrayref();
my $i = 0;
my ($art, $cart);
my @skeyarr;
my $skey;

$sth=$dbh->prepare("select cl_sortkey from enwiki_p.page 
                      join  enwiki_p.categorylinks
                        on cl_from = page_id
                      where page_namespace = 0 and page_title = ?
                              and (not isnull(cl_sortkey))
                                 and (not (cl_sortkey = '*'))
                                 and (not (cl_sortkey = ' '))
                        and length(cl_sortkey > 1)
                       limit 1");

my $count;

open OUT, ">", "SortKeys.txt";
#binmode OUT, ":utf8";
select OUT;
$| = 1;
select STDOUT;

foreach $art ( @$arts) { 
  $i++;
  $art = $art->[0];
  $cart = $art;
  $cart =~ s/ /_/g;
  $count = $sth->execute($cart);
  if ( $count == 0) { 
    print "$i '$art' NONE\n";
    print OUT "$art\t\n";
  } else { 
    @skeyarr = $sth->fetchrow_array();
    $skey = $skeyarr[0];
    print "$i '$art' '$skey' $count\n";
    print OUT "$art\t$skey\n";
  }
  if ( 0 == $i % 4000) { sleep 10; }
}
