#!/bin/sh
# MakeArticleTable.sh
# part of VeblenBot
# Carl Beckhorn, 2008
# Copyright: GPL 2.0

cd /home/veblen/VeblenBot/math

echo "Making article"
TZ=UTC0 perl table_routine5.pl

echo "Uploading field tables"
perl UploadFieldTables2.pl -a
