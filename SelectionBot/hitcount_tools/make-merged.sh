#!/bin/sh

LANG=C
export LANG

TMP=`pwd`/target

cat target/*.out  \
  | sort -T$TMP -k 3 -t " " \
  | ./bin/average-trim.pl \
  | gzip > target/hitcounts.raw.gz
