#!/usr/bin/python
#
# stackcollapse.py	Fold "perf script" stacks for flamegraph.py.
#
# USAGE: ./flamegraph.py [options] input.txt > flamegraph.svg
#
# See --help for the full stackcollapse.py USAGE message.
#
# A more developed (and faster) Perl version of this script can be found in
# https://github.com/brendangregg/FlameGraph as stackcollapse-perf.pl. Also see
# http://www.brendangregg.com/flamegraphs.html for more on flame graphs.
#
# Consider this script temporary: this stackcollapse functionality should be
# provided directly from perf.
#
# COPYRIGHT: Copyright (c) 2015 Brendan Gregg.
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation; either version 2
#  of the License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software Foundation,
#  Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#  (http://www.gnu.org/copyleft/gpl.html)
#
# 06-Aug-2015	Brendan Gregg	Created this.

import string
import sys
import re
import argparse

### options
parser = argparse.ArgumentParser(
	description="Process \"perf script\" output for flamegraph.py")
parser.add_argument("infile", nargs="?", type=argparse.FileType('r'),
	default=sys.stdin,
	help="input file (output of perf script)")
parser.add_argument("-p", "--pid", action="store_true",
	help="include PID with process names")
parser.add_argument("-t", "--tid", action="store_true",
	help="include TID and PID with process names")
args = vars(parser.parse_args())

### other globals
debug = 0
tidy_java = 1

### option logic
include_pid = args["pid"]
include_tid = args["tid"]
infile = args["infile"]

### read data
Collapsed = {}
stack = []
comm = ""
for line in infile:
	line = line.rstrip()

	# skip comments
	if re.search("^#", line):
		continue

	# record stack
	if line == "":
		stack.insert(0, comm)
		stackline = string.join(stack, ";")
		count = Collapsed.get(stackline, 0)
		count += 1
		Collapsed[stackline] = count
		stack = []
		comm = ""
		continue

	# stack line
	# eg, "        ffffffff8117794a sys_write ([kernel.kallsyms])"
	m = re.search("^\s*(\w+)\s*(.+) \((\S*)\)", line)
	if (m):
		pc = m.group(1)
		func = m.group(2)
		mod = m.group(3)
		if re.search("^\(", func):
			continue

		# generic tidy
		func = re.sub(";", ":", func)
		func = re.sub("[<>\"']", "", func)
		func = re.sub("\(.*", "", func)
		func = re.sub(" ", "_", func)

		if (tidy_java and comm == "java" and
			re.search("/", func)):
			func = re.sub("^L", "", func)

		stack.insert(0, func)
	else:
		# default event line
		# default "perf script" output has TID but not PID
		# eg, "java 27660 [000] 1735849.460311: cpu-clock:"
		m = re.search("^(\S+)\s+(\d+)\s", line)
		if (m):
			name = m.group(1)
			tid = m.group(2)
			if include_tid:
				comm = name + "-?/" + tid
			elif include_pid:
				comm = name + "-?"
			else:
				comm = name
		else:
			# custom event line
			# eg, "java 27660/21478 [000] 1735849.460311: cpu-clock:"
			m = re.search("^(\S+)\s+(\d+)\/(\d+)", line)
			if (m):
				name = m.group(1)
				pid = m.group(2)
				tid = m.group(3)
				if include_tid:
					comm = name + "-" + pid + "/" + tid
				elif include_pid:
					comm = name + "-" + pid
				else:
					comm = name

for stack in Collapsed:
	print stack + " " + str(Collapsed[stack])
