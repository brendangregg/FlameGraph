#!/bin/bash

if [ $# -ne 2 ]
  then
    echo "Usage: ./fetchAndMake.sh [remote-ip] [flame graph file prefix]"
    echo "Example: ./fetchAndMake.sh 127.0.0.1 50-threads-execution"
    echo "Downloads all .jstk files from 127.0.0.1:/home/ubuntu/ at ther remote host and then creates 50-threads-execution.svg as a flame graph which you can view in a browser or other SVG viewer"
    exit
fi

scp ubuntu@$1:/home/ubuntu/*.jstk ./

cat ./*.jstk | ../stackcollapse-jstack.pl | ../flamegraph.pl --color=green --width=700 > $2.svg

rm ./*.jstk
