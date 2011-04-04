#!/opt/ts/bin/bash

LANG="en_US.UTF-8"
export LANG

PDIR=/home/project/e/n/w/enwp10

FILE=$PDIR/Logs/upload.`date +%Y-%m-%d_%H:%M.txt`

UPDATE=$PDIR/bin/upload-project-tables.sh

/bin/date >> $FILE

$UPDATE &>> $FILE

/bin/date >> $FILE

cd $PDIR
gzip -9 $FILE
