#!/bin/bash
set -euo pipefail
set -x
set -v


for opt in pid tid kernel ; do
  for t in test/*.txt ; do
    echo testing $t : $opt
    outfile=test/results/${t#*/}-collapsed-${opt}.txt
    perl ./stackcollapse-perf.pl --"${opt}" "${t}" 2> /dev/null | diff -u - "${outfile}"
    perl ./flamegraph.pl "${outfile}" > /dev/null
  done
done

# ToDo: add some form of --inline, and --inline --context tests. These are
# tricky since they use addr2line, whose output will vary based on the test
# system's binaries and symbol tables.
