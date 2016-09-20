#!/bin/bash
#
# pkgsplit-perf.sh	Split IP samples on package names "/", eg, Java.
#
# This is for the creation of Java package flame graphs. Example steps:
#
# perf record -F 199 -a -- sleep 30; ./jmaps
# perf script | ./pkgsplit-perf.sh | ./flamegraph.pl > out.svg
#
# Note that stack traces are not sampled (no -g), as we split Java package
# names into frames rather than stack frames.
#
# (jmaps is a helper script for automating perf-map-agent: Java symbol dumps.)
#
# The default output of "perf script" varies between kernel versions, so we'll
# need to deal with that here. I could make people use the perf script option
# to pick fields, so our input is static, but A) I prefer the simplicity of
# just saying: run "perf script", and B) the option to choose fields itself
# changed between kernel versions! -f became -F.
#
# TODO: I've made this a shell script (rather than #!/usr/bin/awk -f) so
# that we can add some options and option processing if need be.
#
# Linux 3.13:
#            java 13905 [000]  8048.096572: cpu-clock:      7fd781ac3053 Ljava/util/Arrays$ArrayList;::toArray (/tmp/perf-12149.map)
# Linux 4.8:
#            java 30894 [007] 452884.077440:   10101010 cpu-clock:      7f0acc8eff67 Lsun/nio/ch/SocketChannelImpl;::read+0x27 (/tmp/perf-30849.map)
#
# I'll use $(NF-1) as the method name, but this won't work if there are spaces
# in the method name. Fix if needed.
#
# 20-Sep-2016	Brendan Gregg	Created this.

# filter idle events
awk '$0 !~ /xen_hypercall_sched_op|cpu_idle|native_safe_halt/ && NF >= 8 {
	gsub(/[0-9]/, "X", $(NF-1))	# replace numbers with X
	gsub(/\//, ";", $(NF-1))
	if ($(NF-1) ~ /^L/) {		# strip leading "L"
		sub(/^L/, "", $(NF-1))
	}
	print $(NF-1), "1"
}'
