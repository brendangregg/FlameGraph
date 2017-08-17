#!/bin/bash
#
# test.sh - Check flame graph software vs test result files.
#
# This is used to detect regressions in the flame graph software.
# See record-test.sh, which refreshes these files after intended software
# changes.
#
# Currently only tests stackcollapse-perf.pl.

set -euo pipefail
set -x
set -v

# ToDo: add some form of --inline, and --inline --context tests. These are
# tricky since they use addr2line, whose output will vary based on the test
# system's binaries and symbol tables.
for opt in pid tid kernel jit all addrs; do
  for testfile in test/*.txt ; do
    echo testing $testfile : $opt
    outfile=${testfile#*/}
    outfile=test/results/${outfile%.txt}"-collapsed-${opt}.txt"
    perl ./stackcollapse-perf.pl --"${opt}" "${testfile}" 2> /dev/null | diff -u - "${outfile}"
    perl ./flamegraph.pl "${outfile}" > /dev/null
  done
done
