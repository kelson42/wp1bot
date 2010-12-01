#!/bin/sh

X="^$1";
echo "'$X'";
#exit;

grep -h $X ~/public_html/release-data/2008-9-23/HTML/CSV/* >> Manual.arts.new

