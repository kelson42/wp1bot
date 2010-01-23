#!/opt/ts/bin/bash

PDIR=/home/project/e/n/w/enwp10

FILE=$PDIR/Logs/upload.`date +%Y-%m-%d_%H:%M.txt`

UPDATE=$PDIR/bin/upload-project-tables.sh

$UPDATE &> $FILE

cd $PDIR
gzip -9 $FILE
