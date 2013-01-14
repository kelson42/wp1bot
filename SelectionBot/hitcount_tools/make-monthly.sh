month=12
delay=300
year=2012

for x in 05 06 07 08 09 10 11 12 13 14 15 \
         16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 ; do
  echo "$year$month$x";
  sh dl.sh $month $x
   nice -n 19  `pwd`/make-hourly.sh "$year$month$x";
#   newtask -p batch `pwd`/make-hourly.sh "$year$month$x";
  rm source/*.gz
   echo "done, sleeping"
  sleep $delay
done
