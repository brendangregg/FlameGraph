#!/usr/bin/awk -f

#
# This program generates collapsed off-cpu stacks fit for use by flamegraph.pl
# from scheduler data collected via perf_events.
#
# Outputs the cumulative time off cpu in us for each distinct stack observed.
#
# Some awk variables further control behavior:
#
#   record_tid          If truthy, causes all stack traces to include the
#                       command and LWP id.
#
#   record_wake_stack   If truthy, stacks include the frames from the wakeup
#                       event in addition to the sleep event.
#                       See http://www.brendangregg.com/FlameGraphs/offcpuflamegraphs.html#Wakeup
#
#   recurse             If truthy, attempt to recursively identify and
#                       visualize the full wakeup stack chain.
#                       See http://www.brendangregg.com/FlameGraphs/offcpuflamegraphs.html#ChainGraph
#
#                       Note that this is only an approximation, as only the
#                       last sleep event is recorded (e.g. if a thread slept
#                       multiple times before waking another thread, only the
#                       last sleep event is used). Implies record_wake_stack=1
#
# To set any of these variables from the command line, run via:
#
#    stackcollapse-perf-sched.awk -v recurse=1
#
# == Important warning ==
#
# WARNING: tracing all scheduler events is very high overhead in perf. Even
# more alarmingly, there appear to be bugs in perf that prevent it from reliably
# getting consistent traces (even with large trace buffers), causing it to
# produce empty perf.data files with error messages of the form:
#
#   0x952790 [0x736d]: failed to process type: 3410
#
# This failure is not determinisitic, so re-executing perf record will
# eventually succeed.
#
# == Usage ==
#
# First, record data via perf_events:
#
# sudo perf record -g -e 'sched:sched_switch' \
#       -e 'sched:sched_stat_sleep' -e 'sched:sched_stat_blocked' \
#       -p <pid> -o perf.data  -- sleep 1
#
# Then post process with this script:
#
# sudo perf script -f time,comm,pid,tid,event,ip,sym,dso,trace -i perf.data | \
#       stackcollapse-perf-sched.awk -v recurse=1 | \
#       flamegraph.pl --color=io --countname=us >out.svg
#

#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at docs/cddl1.txt or
# http://opensource.org/licenses/CDDL-1.0.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at docs/cddl1.txt.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END
#

#
# Copyright (c) 2015 by MemSQL. All rights reserved.
#

#
# Match a perf captured variable, returning just the contents. For example, for
# the following line, get_perf_captured_variable("pid") would return "27235":
#
#     swapper     0 [006] 708189.626415: sched:sched_stat_sleep: comm=memsqld pid=27235 delay=100078421 [ns
#
function get_perf_captured_variable(variable)
{
	match($0, variable "=[^[:space:]]+")
	return substr($0, RSTART + length(variable) + 1,
                      RLENGTH - length(variable) - 1)
}

#
# The timestamp is the first field that ends in a colon, e.g.:
#
#     swapper     0 [006] 708189.626415: sched:sched_stat_sleep: comm=memsqld pid=27235 delay=100078421 [ns
#
# or
#
#     swapper     0/0     708189.626415: sched:sched_stat_sleep: comm=memsqld pid=27235 delay=100078421 [ns]
#
function get_perf_timestamp()
{
	match($0, " [^ :]+:")
	return substr($0, RSTART + 1, RLENGTH - 2)
}

!/^#/ && /sched:sched_switch/ {
	switchcommand = get_perf_captured_variable("comm")

	switchpid = get_perf_captured_variable("prev_pid")

	switchtime=get_perf_timestamp()

	switchstack=""
}

#
# Strip the function name from a stack entry
#
# Stack entry is expected to be formatted like:
#           c60849 MyClass::Foo(unsigned long) (/home/areece/a.out)
#
function get_function_name()
{
	# We start from 2 since we don't need the hex offset.
	# We stop at NF - 1 since we don't need the library path.
	funcname = $2
	for (i = 3; i <= NF - 1; i++) {
		funcname = funcname " " $i
	}
	return funcname
}

(switchpid != 0 && /^\s/) {
	if (switchstack == "")  {
		switchstack = get_function_name()
	} else {
		switchstack = get_function_name() ";" switchstack
	}
}

(switchpid != 0 && /^$/) {
	switch_stacks[switchpid] = switchstack
	delete last_switch_stacks[switchpid]
	switch_time[switchpid] = switchtime

	switchpid=0
	switchcommand=""
	switchstack=""
}

!/^#/ && (/sched:sched_stat_sleep/ || /sched:sched_stat_blocked/) {
	wakecommand=$1
	wakepid=$2

	waketime=get_perf_timestamp()

	stat_next_command = get_perf_captured_variable("comm")

	stat_next_pid = get_perf_captured_variable("pid")

	stat_delay_ns = int(get_perf_captured_variable("delay"))

	wakestack=""
}

(stat_next_pid != 0 && /^\s/) {
	if (wakestack == "") {
		wakestack = get_function_name()
	} else {
		# We build the wakestack in reverse order.
		wakestack = wakestack ";" get_function_name()
	}
}

(stat_next_pid != 0 && /^$/) {
	#
	# For some reason, perf appears to output duplicate
	# sched:sched_stat_sleep and sched:sched_stat_blocked events. We only
	# handle the first event.
	#
	if (stat_next_pid in switch_stacks) {
		last_wake_time[stat_next_pid] = waketime

		stack = switch_stacks[stat_next_pid]
		if (recurse || record_wake_stack) {
			stack = stack ";" wakestack
			if (record_tid) {
				stack = stack ";" wakecommand "-" wakepid
			} else {
				stack = stack ";" wakecommand
			}
		}

		if (recurse) {
			if (last_wake_time[wakepid] > last_switch_time[stat_next_pid]) {
				stack = stack ";-;" last_switch_stacks[wakepid]
			}
			last_switch_stacks[stat_next_pid] = stack
		}

		delete switch_stacks[stat_next_pid]

		if (record_tid) {
			stack_times[stat_next_command "-" stat_next_pid ";" stack] += stat_delay_ns
		} else {
			stack_times[stat_next_command ";" stack] += stat_delay_ns
		}
	}

	wakecommand=""
	wakepid=0
	stat_next_pid=0
	stat_next_command=""
	stat_delay_ms=0
}

END {
	for (stack in stack_times) {
		if (int(stack_times[stack] / 1000) > 0) {
			print stack, int(stack_times[stack] / 1000)
		}
	}
}
