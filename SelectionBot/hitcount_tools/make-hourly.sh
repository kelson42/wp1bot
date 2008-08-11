#!/bin/sh

LANG=C
export LANG

TMP=`pwd`/target

perl bin/phase1h.pl source/pagecounts-$1-* \
  | sort -T$TMP  -k 3 -t " " \
  | perl bin/tally.pl > target/$1.out
