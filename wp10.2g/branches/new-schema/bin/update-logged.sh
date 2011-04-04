#!/opt/ts/bin/bash

LANG="en_US.UTF-8"
export LANG

PDIR=/home/project/e/n/w/enwp10

FILE=$PDIR/Logs/update.`date +%Y-%m-%d_%H:%M.txt`

UPDATE=$PDIR/bin/update-all.sh

cd $PDIR/bin

/bin/date >> $FILE

$UPDATE &> $FILE

cd $PDIR/Logs

/bin/date >> $FILE

gzip -9 $FILE
