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
use Getopt::Long;
use POSIX 'floor';

sub usage {
	die <<USAGE_END;
USAGE: $0 [options] min_seconds max_seconds
	--timeraw	# use raw timestamps from perf
	--timezerosecs	# time starts at 0 secs, but keep offset from perf
	eg,
	$0 10 20	# only include samples between 10 and 20 seconds
USAGE_END
}

my $timeraw = 0;
my $timezerosecs = 0;
GetOptions(
	'timeraw'       => \$timeraw,
	'timezerosecs'  => \$timezerosecs,
) or usage();

if (@ARGV < 2 || $ARGV[0] eq "-h" || $ARGV[0] eq "--help") {
	usage();
	exit;
}
my $begin = $ARGV[0];
my $end = $ARGV[1];

#
# Parsing
#
# IP only examples:
# 
# java 52025 [026] 99161.926202: cycles: 
# java 14341 [016] 252732.474759: cycles:      7f36571947c0 nmethod::is_nmethod() const (/...
# java 14514 [022] 28191.353083: cpu-clock:      7f92b4fdb7d4 Ljava_util_List$size$0;::call (/tmp/perf-11936.map)
#      swapper     0 [002] 6035557.056977:   10101010 cpu-clock:  ffffffff810013aa xen_hypercall_sched_op+0xa (/lib/modules/4.9-virtual/build/vmlinux)
#         bash 25370 603are 6036.991603:   10101010 cpu-clock:            4b931e [unknown] (/bin/bash)
#         bash 25370/25370 6036036.799684: cpu-clock:            4b913b [unknown] (/bin/bash)
# other combinations are possible.
#
# Stack examples (-g):
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
# swapper     0 [002] 6034779.719110:   10101010 cpu-clock: 
#       2013aa xen_hypercall_sched_op+0xfe20000a (/lib/modules/4.9-virtual/build/vmlinux)
#       a72f0e default_idle+0xfe20001e (/lib/modules/4.9-virtual/build/vmlinux)
#       2392bf arch_cpu_idle+0xfe20000f (/lib/modules/4.9-virtual/build/vmlinux)
#       a73333 default_idle_call+0xfe200023 (/lib/modules/4.9-virtual/build/vmlinux)
#       2c91a4 cpu_startup_entry+0xfe2001c4 (/lib/modules/4.9-virtual/build/vmlinux)
#       22b64a cpu_bringup_and_idle+0xfe20002a (/lib/modules/4.9-virtual/build/vmlinux)
#
# bash 25370/25370 6035935.188539: cpu-clock: 
#                   b9218 [unknown] (/bin/bash)
#                 2037fe8 [unknown] ([unknown])
# other combinations are possible.
#
# This regexp matches the event line, and puts time in $1, and the event name
# in $2:
#
my $event_regexp = qr/ +([0-9\.]+): *\S* *(\S+):/;

my $line;
my $start = 0;
my $ok = 0;
my $time;

while (1) {
	$line = <STDIN>;
	last unless defined $line;
	next if $line =~ /^#/;		# skip comments

	if ($line =~ $event_regexp) {
		my ($ts, $event) = ($1, $2, $3);
		$start = $ts if $start == 0;

		if ($timezerosecs) {
			$time = $ts - floor($start);
		} elsif (!$timeraw) {
			$time = $ts - $start;
		} else {
			$time = $ts;	# raw times
		}

		$ok = 1 if $time >= $begin;
		# assume samples are in time order:
		exit if $time > $end;
	}

	print $line if $ok;
}
