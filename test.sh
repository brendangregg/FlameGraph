#!/bin/bash
set -euo pipefail
set -x
set -v


for opt in pid tid inline kernel context ; do
  for t in test/*.txt ; do
    echo testing $t : $opt
    outfile=test/results/${t#*/}-collapsed-${opt}.txt
    perl ./stackcollapse-perf.pl --"${opt}" "${t}" 2> /dev/null | diff -u - "${outfile}"
    perl ./flamegraph.pl "${outfile}" > /dev/null
  done
done
