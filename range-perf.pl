#!/usr/bin/perl -w
#
# range-perf	Extract a time range from Linux "perf script" output.
#
# USAGE EXAMPLE:
#
# perf record -F 100 -a -- sleep 60
# perf script | ./perf2range.pl 10 20	# range 10 to 20 seconds only
# perf script | ./perf2range.pl 0 0.5	# first half second only
#
# MAKING A SERIES OF FLAME GRAPHS:
#
# Let's say you had the output of "perf script" in a file, out.stacks01, which
# was for a 180 second profile. The following command creates a series of
# flame graphs for each 10 second interval:
# 
# for i in `seq 0 10 170`; do cat out.stacks01 | \
#    ./perf2range.pl $i $((i + 10)) | ./stackcollapse-perf.pl | \
#    grep -v cpu_idle | ./flamegraph.pl --hash --color=java \
#    --title="range $i $((i + 10))" > out.range_$i.svg; echo $i done; done
#
# In that example, I used "--color=java" for the Java palette, and excluded
# the idle CPU task. Customize as needed.
#
# Copyright 2017 Netflix, Inc.
# Licensed under the Apache License, Version 2.0 (the "License")
#
# 21-Feb-2017	Brendan Gregg	Created this.

use strict;

sub usage {
	die <<USAGE_END;
USAGE: $0 min_seconds max_seconds
	eg,
	$0 10 20	# only include samples between 10 and 20 seconds
USAGE_END
}

if (@ARGV < 2 || $ARGV[0] eq "-h" || $ARGV[0] eq "--help") {
	usage();
	exit;
}
my $start = $ARGV[0];
my $end = $ARGV[1];

my $line;
my $begin = 0;
my $ok = 0;
my ($cpu, $ts, $event);

while (1) {
	# skip comments

	$line = <STDIN>;
	last unless defined $line;
	next if $line =~ /^#/;

	#
	# Parsing
	#
	# ip only examples:
	# 
	# java 52025 [026] 99161.926202: cycles: 
	# java 14341 [016] 252732.474759: cycles:      7f36571947c0 nmethod::is_nmethod() const (/...
	# java 14514 [022] 28191.353083: cpu-clock:      7f92b4fdb7d4 Ljava_util_List$size$0;::call (/tmp/perf-11936.map)
	#
	# stack examples (-g):
	#
	# swapper     0 [021] 28648.467059: cpu-clock: 
	#	ffffffff810013aa xen_hypercall_sched_op ([kernel.kallsyms])
	#	ffffffff8101cb2f default_idle ([kernel.kallsyms])
	#	ffffffff8101d406 arch_cpu_idle ([kernel.kallsyms])
	#	ffffffff810bf475 cpu_startup_entry ([kernel.kallsyms])
	#	ffffffff81010228 cpu_bringup_and_idle ([kernel.kallsyms])
	#
	# java 14375 [022] 28648.467079: cpu-clock: 
	#	    7f92bdd98965 Ljava/io/OutputStream;::write (/tmp/perf-11936.map)
	#	    7f8808cae7a8 [unknown] ([unknown])
	#
	# swapper     0 [005]  5076.836336: cpu-clock: 
	#	ffffffff81051586 native_safe_halt ([kernel.kallsyms])
	#	ffffffff8101db4f default_idle ([kernel.kallsyms])
	#	ffffffff8101e466 arch_cpu_idle ([kernel.kallsyms])
	#	ffffffff810c2b31 cpu_startup_entry ([kernel.kallsyms])
	#	ffffffff810427cd start_secondary ([kernel.kallsyms])
	#
	if ($line =~ / \d+ \[(\d+)\] +(\S+): (\S+):/) {
		($cpu, $ts, $event) = ($1, $2, $3);
		$begin = $ts if $begin == 0;

		my $time = $ts - $begin;
		$ok = 1 if $time >= $start;
		exit if $time > $end;
	}

	print $line if $ok;
}
