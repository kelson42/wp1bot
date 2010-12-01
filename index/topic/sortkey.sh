#!/bin/sh


echo "select concat(page_title, ' ', cl_sortkey) from page join categorylinks on page_id = cl_from where page_namespace = 0 and page_title = '$1'"  \
  | mysql -h sql-s1 -q enwiki_p

