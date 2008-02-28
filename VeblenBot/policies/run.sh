#!/bin/sh
cd /home/veblen/VeblenBot/policies
perl policyCache.pl
echo done.
touch last.run
