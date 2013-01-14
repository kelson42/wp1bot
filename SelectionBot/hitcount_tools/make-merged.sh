#!/opt/ts/bin/bash

cd /home/cbm/hitcount-tools/hitcount_tools

LANG=C
export LANG

TMP=`pwd`/target
export TMP

gzcat -v target/*.out.gz  \
  | sort -T$TMP -k 3 -t " " \
  | ./bin/average-trim.pl \
  | gzip > target/hitcounts.raw.gz
