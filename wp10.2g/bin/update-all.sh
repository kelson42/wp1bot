#!/opt/ts/bin/bash

LANG="en_US.UTF-8"
export LANG

PDIR=/home/project/e/n/w/enwp10

FILE=$PDIR/Logs/`date +%Y-%m-%d.%H:%M.txt`

cd $PDIR/backend

export
hostname
pwd
date

echo "Releases"
time ./download.pl --releases

echo "Reviews"
time ./download.pl --reviews

echo "Update all projects"
time ./download.pl --all

echo "Global"
time ./mktable.pl --purge --mode global

date
