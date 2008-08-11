#!/bin/sh

ARG=$1

if [ "$ARG" = "clean" ]; then 
  rm -r CSV/
  rm -r DB/
  rm -r DBm/
  rm -r HTML/ 
  rm -r Logs/
else
  mkdir CSV
  mkdir DB
  mkdir DBm
  mkdir HTML
  mkdir Logs
fi
