#!/bin/bash
set -v -x

for opt in pid tid inline kernel context ; do
  for t in test/*.txt ; do
    echo testing $t : $opt
    ./stackcollapse-perf.pl --"${opt}" "${t}" 2> /dev/null > test/results/"${t#*/}"-collapsed-"${opt}".txt
  done
done
