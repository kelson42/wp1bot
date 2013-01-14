#!/bin/sh

cd /home/cbm/hitcount-tools/hitcount_tools

LANG=C
export LANG

TMP=`pwd`/target
export TMP


PERLLIB=/home/cbm/perl/lib/perl/5.10.0
export PERLIB

perl bin/phase1hz.pl source/pagecounts-$1-* \
  | sort -T$TMP  -k 3 -t " " \
  | perl bin/tally.pl | gzip -9 > target/$1.out.gz
