#!/opt/ts/bin/bash

PDIR=/home/project/e/n/w/enwp10

FILE=$PDIR/Logs/update.`date +%Y-%m-%d_%H:%M.txt`

UPDATE=$PDIR/bin/update-all.sh

cd $PDIR/bin

$UPDATE &> $FILE

cd $PDIR/Logs

gzip -9 $FILE
