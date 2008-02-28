#/bin/sh
cd /home/veblen/VeblenBot/per

TZ=UTC0 perl /home/veblen/VeblenBot/per/parsePER.pl
perl /home/veblen/VeblenBot/per/uploadPER.pl -a
