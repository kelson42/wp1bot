#!/opt/ts/bin/bash

PDIR=/home/project/e/n/w/enwp10

FILE=$PDIR/Logs/upload.`date +%Y-%m-%d.%H:%M.txt`

cd $PDIR/backend

pwd

echo "@@ copy_tables --project"
time ./copy_tables.pl --project
echo "@@ copy_tables --global"
time ./copy_tables.pl --global
echo "@@ copy_count"
time ./copy_count.pl --global
echo "@@ copy_logs"
time ./copy_logs.pl --all
