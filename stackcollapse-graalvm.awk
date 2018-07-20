#!/usr/bin/awk -f
#
# stackcolllapse-gralvm.awk	collapse the graalvm cpu sampler's call tree output
# into single lines stacks.
#
# Parses the output of the graalvm cpu sampler obtained by adding --cpusampler
# --cpusamper.Output=calltree when launching any Truffle language,
# e.g.
# ./js  --cpusampler --cpusamper.Output=calltree test.js
#
# and outputs a semicolon separated stack followed by a space and a count.
#
# USAGE: ./stackcollapse-ljp.pl infile > outfile
#
# Example input:
#
#-----------------------------------------------------------------------------------------------------------------------------------------
#Sampling CallTree. Recorded 7125 samples with period 1ms.
#  Self Time: Time spent on the top of the stack.
#  Total Time: Time spent somewhere on the stack.
#  Opt %: Percent of time spent in compiled and therfore non-interpreted code.
#-----------------------------------------------------------------------------------------------------------------------------------------
# Name                                              |      Total Time     |  Opt % ||       Self Time     |  Opt % | Location
#-----------------------------------------------------------------------------------------------------------------------------------------
# :program                                          |       7125ms 100.0% |   0.0% ||          0ms   0.0% |   0.0% | test.js
#  main                                             |       7125ms 100.0% |   0.0% ||          0ms   0.0% |   0.0% | test.js
#   foo                                             |       7125ms 100.0% |   0.0% ||          0ms   0.0% |   0.0% | test.js
#    bar                                            |       7125ms 100.0% |   0.0% ||          0ms   0.0% |   0.0% | test.js
#     buzz                                          |       7125ms 100.0% |   0.0% ||       7125ms   0.0% |   0.0% | test.js
#
#
# Example output:
#
#  :program;main;foo;bar;buzz 7125
#

BEGIN {FS="|"}

# Skip header and border
NR < 9 { next }
match($0, /^\-+$/) { next }

{
	spaces = count_spaces($0);
	while (depth_stack_size() > 0 && spaces <= depth_stack_top()) {
		value_stack_pop();
		depth_stack_pop();
	}
	value_stack_push(trim($1));
	depth_stack_push(spaces);
}

$5 != "" && parse_time($5) != "0" {print value_stack_combine() " " parse_time($5)}

function count_spaces(s) {
	match(s, /^ */);
	return RLENGTH;
}

function parse_time(val) {
    return trim(substr(val, 0, length($5) - 10));
}

function value_stack_combine() {
	ret = "";
	for (i = 0; i < value_stack_pos; i++) {
		ret = ret value_stack_array[i];
        if (i < value_stack_pos - 1) {
		    ret = ret ";";
        }
	}
	return ret;
}

function value_stack_push(val) {
        value_stack_array[value_stack_pos++] = val;
}

function value_stack_pop() {
        return (value_stack_size() < 0) ? "ERROR" : value_stack_array[--value_stack_pos];
}

function value_stack_top() {
        return value_stack_array[value_stack_pos - 1];
}
function value_stack_size() {
        return value_stack_pos;
}

function depth_stack_push(val) {
        depth_stack_array[depth_stack_pos++] = val;
}

function depth_stack_pop() {
        return (depth_stack_size() < 0) ? "ERROR" : depth_stack_array[--depth_stack_pos];
}

function depth_stack_top() {
        return depth_stack_array[depth_stack_pos - 1];
}

function depth_stack_size() {
        return depth_stack_pos;
}

function ltrim(s) { sub(/^[ \t\r\n]+/, "", s); return s }

function rtrim(s) { sub(/[ \t\r\n]+$/, "", s); return s }

function trim(s)  { return rtrim(ltrim(s)); }

