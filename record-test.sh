#!/bin/bash
#
# record-test.sh - Overwrite flame graph test result files.
#
# See test.sh, which checks these resulting files.
#
# Currently only tests stackcollapse-perf.pl.

set -v -x

# ToDo: add some form of --inline, and --inline --context tests. These are
# tricky since they use addr2line, whose output will vary based on the test
# system's binaries and symbol tables.
for opt in pid tid kernel jit all addrs; do
  for testfile in test/*.txt ; do
    echo testing $testfile : $opt
    outfile=${testfile#*/}
    outfile=test/results/${outfile%.txt}"-collapsed-${opt}.txt"
    ./stackcollapse-perf.pl --"${opt}" "${testfile}" 2> /dev/null > $outfile
  done
done
