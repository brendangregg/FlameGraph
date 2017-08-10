#!/bin/bash

if [ -z "$1" ]
  then
    echo "Usage: ./fetchStack.sh [source-ip]"
    exit
fi

scp ubuntu@$1:/home/ubuntu/*.jstk ./
