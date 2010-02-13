#!/opt/ts/bin/bash

PDIR=/home/project/e/n/w/enwp10
cd $PDIR/backend

perl download.pl "$1"
echo 
echo "--- Finished downloading assessment data, now uploading table to wiki"
perl copy_tables.pl --project "$1"
