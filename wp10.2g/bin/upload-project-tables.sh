#!/opt/ts/bin/bash

PDIR=/home/project/e/n/w/enwp10

FILE=$PDIR/Logs/upload.`date +%Y-%m-%d.%H:%M.txt`

cd $PDIR/backend

pwd

time ./copy_tables.pl --project
time ./copy_tables.pl --global
time ./copy_count.pl --global
