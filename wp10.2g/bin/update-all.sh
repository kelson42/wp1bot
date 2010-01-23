#!/opt/ts/bin/bash

PDIR=/home/project/e/n/w/enwp10

FILE=$PDIR/Logs/`date +%Y-%m-%d.%H:%M.txt`

cd $PDIR/backend

pwd

time ./download.pl --releases
time ./download.pl --reviews
time ./download.pl --all
time ./mktable.pl --purge --mode global
