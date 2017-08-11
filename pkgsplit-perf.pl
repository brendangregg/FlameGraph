#!/usr/bin/perl -w
#
# pkgsplit-perf.pl	Split IP samples on package names "/", eg, Java.
#
# This is for the creation of Java package flame graphs. Example steps:
#
# perf record -F 199 -a -- sleep 30; ./jmaps
# perf script | ./pkgsplit-perf.pl | ./flamegraph.pl > out.svg
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
# Copyright 2017 Netflix, Inc.
# Licensed under the Apache License, Version 2.0 (the "License")
#
# 20-Sep-2016	Brendan Gregg	Created this.

use strict;

my $include_pname = 1;	# include process names in stacks
my $include_pid = 0;	# include process ID with process name
my $include_tid = 0;	# include process & thread ID with process name

while (<>) {
	# filter comments
	next if /^#/;

	# filter idle events
	next if /xen_hypercall_sched_op|cpu_idle|native_safe_halt/;

	my ($pid, $tid, $pname);

	# Linux 3.13:
	#     java 13905 [000]  8048.096572: cpu-clock:      7fd781ac3053 Ljava/util/Arrays$ArrayList;::toArray (/tmp/perf-12149.map)
	#     java  8301 [050] 13527.392454: cycles:      7fa8a80d9bff Dictionary::find(int, unsigned int, Symbol*, ClassLoaderData*, Handle, Thread*) (/usr/lib/jvm/java-8-oracle-1.8.0.121/jre/lib/amd64/server/libjvm.so)
	#     java  4567/8603  [023] 13527.389886: cycles:      7fa863349895 Lcom/google/gson/JsonObject;::add (/tmp/perf-4567.map)
	#
	# Linux 4.8:
	#     java 30894 [007] 452884.077440:   10101010 cpu-clock:      7f0acc8eff67 Lsun/nio/ch/SocketChannelImpl;::read+0x27 (/tmp/perf-30849.map)
	#     bash 26858/26858 [006] 5440237.995639: cpu-clock:            433573 [unknown] (/bin/bash)
	#
	if (/^\s+(\S.+?)\s+(\d+)\/*(\d+)*\s.*?:.*:/) {
		# parse process name and pid/tid
		if ($3) {
			($pid, $tid) = ($2, $3);
		} else {
			($pid, $tid) = ("?", $2);
		}

		if ($include_tid) {
			$pname = "$1-$pid/$tid";
		} elsif ($include_pid) {
			$pname = "$1-$pid";
		} else {
			$pname = $1;
		}
		$pname =~ tr/ /_/;
	} else {
		# not a match
		next;
	}

	# parse rest of line
	s/^.*?:.*?:\s+//;
	s/ \(.*?\)$//;
	chomp;
	my ($addr, $func) = split(' ', $_, 2);

	# strip Java's leading "L"
	$func =~ s/^L//;

	# replace numbers with X
	$func =~ s/[0-9]/X/g;

	# colon delimitered
	$func =~ s:/:;:g;
	print "$pname;$func 1\n";
}
