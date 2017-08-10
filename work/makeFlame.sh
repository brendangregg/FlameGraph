#!/bin/bash

if [ $# -ne 1 ]
  then
    echo "Usage: ./makeFlame.sh [flame graph file prefix]"
    echo "Example: ./makeFlame.sh 50-threads-execution"
    echo "Creates 50-threads-execution.svg as a flame graph which you can view in a browser or other SVG viewer"
    exit
fi

cat ./*.jstk | ../stackcollapse-jstack.pl | ../flamegraph.pl --color=green --width=700 > $1.svg

rm ./*.jstk
