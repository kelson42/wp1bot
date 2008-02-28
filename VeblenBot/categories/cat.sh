#!/bin/sh

cd /home/veblen/VeblenBot/categories
touch LastRun
echo >> Log
date >> Log
perl downloadList2.pl >> Log 2>&1
perl updateCache.pl >> Log 2>&1 
perl uploadList.pl -a >> Log 2>&1
#perl downloadCount.pl >> Log 2>&1
#perl uploadCount.pl -a >> Log 2>&1
