#!/usr/bin/python
#
# flamegraph.py		Flame graph visualization generator.
#
# This generates a SVG visualization of profiled stack traces, commonly used
# to visualize a CPU stack trace profile (eg, using Linux perf_events). The
# visualization is called a "flame graph", which is an inverted icicle plot
# of stack functions.
#
# This is a basic Python version of the more fully featured Perl flamegraph.pl
# on https://github.com/brendangregg/FlameGraph.
#
# Flame graphs can be generated from the output of many profilers, including
# Linux perf_events, SystemTap, FreeBSD pmcstat, DTrace, Instruments, Intel
# vtune, Lightweight Java Profiler, and more.
#
# USAGE: ./flamegraph.py [options] input.txt > flamegraph.svg
#
# See --help for the full USAGE message.
#
# Separate converters exist to process the output from different profilers into
# a generic single line format for each stack, where functions are separated by
# semicolons, and the line ends with a count of the stack's occurance in the
# profile. They are in https://github.com/brendangregg/FlameGraph, and begin
# with "stackcollapse". As some example output:
#
# func_a;func_b;func_c;func_d 31
#
# Here func_a() would be the root, and func_d() the leaf, and 31 is the count
# for this stack trace.
#
# With the resulting flame graph, the y axis is stack depth, and the x axis
# spans the sample population. Each rectangle is a stack frame (a function),
# where the width shows how often it was present in the profile. The ordering
# from left to right is unimportant (the stacks are sorted alphabetically,
# to maximize merging).
#
# If two columns are provided, the flame graph is drawn using the widths of
# the second column, then colored by the difference between them, on a palette
# of blue<-white->red, from negative to positive differences.
#
# func_a;func_b;func_c;func_d 31 33
# 
# This is for differential flame graphs.
#
# Note that the reserved characters in the input are ";", as the stack function
# separator, and " ", as the field separator. If these (somehow) appear in
# function names, substitute them with something else before passing to
# flamegraph.py.
#
# For more about flame graphs, see:
#  http://www.brendangregg.com/FlameGraphs/cpuflamegraphs.html
#  http://www.brendangregg.com/flamegraphs.html#Updates
#
# HISTORY
#
# This was inspired by Neelakanth Nadgir's excellent function_call_graph.rb
# program, which visualized function entry and return trace events.  As Neel
# wrote: "The output displayed is inspired by Roch's CallStackAnalyzer which
# was in turn inspired by the work on vftrace by Jan Boerhout".  See:
# https://blogs.oracle.com/realneel/entry/visualizing_callstacks_via_dtrace_and
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
# 21-Jul-2015	Brendan Gregg	Created this.

import sys
import re
import argparse
import random

### options
parser = argparse.ArgumentParser(
	description="Flame Graph: stack trace visualization")
parser.add_argument("infile", nargs="?", type=argparse.FileType('r'),
	default=sys.stdin,
	help="input file (output of a stackcollapse script)")
parser.add_argument("-t", "--title",
	help="title of flame graph")
parser.add_argument("-w", "--width", default=1200,
	help="width of image, pixels (default 1200)")
parser.add_argument("--color", default="hot",
	help="color palette: hot (default), red, green, blue, yellow, java")
parser.add_argument("--frameheight", default=16,
	help="frame height, pixels (default 16)")
parser.add_argument("--minwidth", default=0.1,
	help="omit frames smaller than this, pixels (default 0.1)")
parser.add_argument("--nametype", default="Function:",
	help="frame type (default \"Function:\")")
parser.add_argument("--countname", default="samples",
	help="x-axis type (default \"samples\")")
parser.add_argument("--reverse", action="store_true",
	help="generate a stack-reversed flame graph")
parser.add_argument("--inverted", action="store_true",
	help="flip y-axis: icicle graph")
args = vars(parser.parse_args())

### other globals
fonttype = "Verdana"
fontsize = 12
fontwidth = 0.59
color_bg = "#eeeeee"			# background color
pad_top = fontsize * 4
pad_bottom = fontsize * 2 + 10
pad_side = 10				# left and right of image
pad_frame = 1				# white space between frames
ignored = 0				# ignored input data line count
depth_max = 0				# deepest retained stack depth
debug = 0

### option logic
if args["title"]:
	title = args["title"]
elif args["inverted"]:
	title = "Icicle Graph"
else:
	title = "Flame Graph"
image_width = args["width"]
minwidth = int(args["minwidth"])
frameheight = int(args["frameheight"])
infile = args["infile"]
palette = args["color"]
nametype = args["nametype"]
countname = args["countname"]

### SVG functions
class SVG:
	def __init__(self, width, height):
		self.width = width
		self.height = height

	def header(self):
		sw = str(self.width)
		sh = str(self.height)
		header = """<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" width="%s" height="%s" onload="init(evt)" viewBox="0 0 %s %s" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
<!-- Flame graph stack visualization. See https://github.com/brendangregg/FlameGraph for latest version, and http://www.brendangregg.com/flamegraphs.html for examples. -->'
"""
		print header % (sw, sh, sw, sh)

	def filled_rectangle(self, x1, y1, x2, y2, fill, extra=""):
		sx1 = "%0.1f" % x1
		sx2 = "%0.1f" % x2
		sy1 = str(y1)
		sy2 = str(y2)
		sw = "%0.1f" % (x2 - x1)
		sh = "%0.1f" % (y2 - y1)
		print ('<rect x="%s" y="%s" width="%s" height="%s" fill="%s"'
			' %s />' % (sx1, sy1, sw, sh, fill, extra))

	def string_ttf(self, color, font, size, x, y, text, location, extra=""):
		sx = str(x)
		sy = str(y)
		if location == "":
			location = "left"
		print ('<text text-anchor="%s" x="%s" y="%s" font-size="%s" '
			'font-family="%s" fill="%s" %s >%s</text>' %
			(location, sx, sy, size, font, color, extra, text))

	def group_header(self, info):
		print ('<g class="f" onmouseover="s(\'%s\')"'
			' onmouseout="c()">' % info)

	def group_footer(self):
		print "</g>"

	def footer(self):
		print '</svg>'

### flame graph functions
# highlight java stacks
def func_to_palette_java(func):
	# C++ == yellow, Java == green, system (other) == red
	if (re.search("::", func)):
		scheme = "yellow"
	elif (re.search("/", func)):
		scheme = "green"
	else:
		scheme = "red"

# return a color for a function
def func_to_color(scheme, func):
	if scheme == "java":
		scheme = func_to_palette_java(func)

	if scheme == "hot":
		r = random.randint(220,255)
		g = random.randint(100,180)
		b = random.randint(50,100)
	elif scheme == "red":
		r = random.randint(200,255)
		g = b = random.randint(50,100)
	elif scheme == "green":
		g = random.randint(200,255)
		r = b = random.randint(60,120)
	elif scheme == "blue":
		b = random.randint(200,255)
		r = g = random.randint(100,150)
	elif scheme == "yellow":
		r = g = random.randint(175,250)
		b = random.randint(50,80)

	return "rgb(%d,%d,%d)" % (r, g, b)

def diff_to_color(max, diff):
	r = g = b = 255
	if diff > 0:
		g = b = int(210 * (max - diff) / max)
	elif diff < 0:
		r = g = int(210 * (max + diff) / max)
	return "rgb(%d,%d,%d)" % (r, g, b)

# css
def include_css():
	print """<style type="text/css">
	.f:hover { stroke:black; stroke-width:0.5; cursor:pointer; }
</style>
"""

# javascript interactivity
def include_javascript():
	script = """<script type="text/ecmascript">
<![CDATA[
	var info, svg;
	function init(evt) {
		info = document.getElementById("info").firstChild;
		svg = document.getElementsByTagName("svg")[0];
	}
	function s(details) { info.nodeValue = "%s " + details }
	function c() { info.nodeValue = ''; }
]]>
</script>
"""
	print script % nametype

# this merges two stacks, this and last, and stores the results in Merged
Merged = {}	# frame data in memory
Diff = {}	# frame diff values (differentials only)
MTmp = {}
DTmp = {}
def merge(stack_last, stack, offset, diff):
	len_a = len(stack_last) - 1
	len_b = len(stack) - 1
	len_same = 0

	# discover number of like-frames, from root to leaf
	for i in range(0, len_a + 1):
		if i > len_b:
			break
		if stack_last[i] != stack[i]:
			break
		len_same += 1

	# extend like-frame lengths, from deepest leaf to root
	for i in range(len_a, len_same - 1, -1):
		if i < 0:
			break
		# the Merged key is the function name (for later retrieval),
		# stack depth, and end_offset, and the Merged value is the
		# start_offset, which we've been carrying along each iteration
		# in MTmp.
		Merged[(stack_last[i], i, offset)] = MTmp[(stack_last[i], i)]
		try:
			if DTmp[(stack_last[i], i)]:
				Diff[(stack_last[i], i, offset)] = \
					DTmp[(stack_last[i], i)]
			del DTmp[(stack_last[i], i)]
		except:
			pass
		del MTmp[(stack_last[i], i)]

	# stash new frames in Tmp for next iteration
	for i in range(len_same, len_b + 1):
		MTmp[(stack[i], i)] = offset
		if diff:
			DTmp[(stack[i], i)] = diff

### read data
data = []
stack_last = []
count_total = 0			# count can be samples, time (ms/...), etc.
diff_max = 0			# differential max delta
for line in infile:
	data.append(line)
data.sort()
for line in data:
	# normal line format: stack count
	# differential line format: stack count_a count_b
	try:
		stack_string, rest = line.split(" ", 1)
	except ValueError:
		ignored += 1
		continue

	diff = differential = 0
	try:
		count_a, count_b = rest.split(" ", 1)
		differential = 1
		diff = int(count_b) - int(count_a)
		if abs(diff) > diff_max:
			# record max difference
			diff_max = abs(diff)
	except ValueError:
		count = rest

	# merge and store frame
	stack = stack_string.split(";")
	stack.insert(0, "")			# blank root frame
	merge(stack_last, stack, count_total, diff)
	stack_last = stack

	# increment x-axis offset
	if differential:
		count_total += int(count_b)	# flame graph is 2nd column
	else:
		count_total += int(count)

# finish and store remaining frames
merge(stack_last, [], count_total, 0)

if debug:
	print >> sys.stderr, "count_total: %d" % count_total
if ignored:
	print >> sys.stderr, "WARNING: ignored %d lines (invalid)" % ignored

### determine max depth, and prune narrow functions
width_per_count = (image_width - 2.0 * pad_side) / count_total
minwidth_count = minwidth / width_per_count
for func, depth, end_offset in Merged:
	start_offset = Merged[(func, depth, end_offset)]
	if ((int(end_offset) - int(start_offset)) < minwidth_count):
		del Merged[(func, depth, end_offset)];
		next;
	if int(depth) > depth_max:
		depth_max = int(depth)
image_height = (depth_max * frameheight) + pad_top + pad_bottom

### draw SVG
svg = SVG(image_width, image_height)
svg.header()

# interactivity, background, title, mouse-over info
include_css()
include_javascript()
svg.filled_rectangle(0, 0, image_width, image_height, color_bg)
svg.string_ttf("black", fonttype, fontsize + 5, int(image_width / 2),
	fontsize * 2, title, "middle")
svg.string_ttf("black", fonttype, fontsize, pad_side,
	image_height - (pad_bottom / 2), " ", "", 'id="info"')	# " " needed

# draw frames
for func, depth, end_offset in Merged:
	# calculate positions
	start_offset = Merged[(func, depth, end_offset)]
	x1 = pad_side + int(start_offset) * width_per_count
	x2 = pad_side + int(end_offset) * width_per_count
	y1 = image_height - pad_bottom - (int(depth) + 1) * frameheight + \
		pad_frame
	y2 = image_height - pad_bottom - int(depth) * frameheight

	# determine color
	if diff_max:
		try:
			diff = Diff[(func, depth, end_offset)]
		except:
			diff = 0
		color = diff_to_color(diff_max, diff)
	else:
		color = func_to_color(palette, func)

	# set popup info
	info = func
	if int(depth) == 0:
		info = "all (%s %s, 100%%)" % (count_total, countname)
	else:
		count = int(end_offset) - int(start_offset)
		escaped = func
		escaped = re.sub("&", "&amp", escaped)
		escaped = re.sub("<", "&lt;", escaped)
		escaped = re.sub(">", "&gt;", escaped)
		info = "%s (%s %s, %.2f%%)" % (escaped, count, countname,
			(100.0 * count / count_total))
	svg.group_header(info)

	# rectangle
	svg.filled_rectangle(x1, y1, x2, y2, color, 'rx="1" ry="2"')

	# text in rectangle
	chars = int((x2 - x1) / (fontsize * fontwidth))
	text = ""
	if chars >= 3:
		text = func[0:chars]
		if chars < len(func):
			text = text[0:-2] + ".."
			text = re.sub("&", "&amp", text)
			text = re.sub("<", "&lt;", text)
			text = re.sub(">", "&gt;", text)
	svg.string_ttf("black", fonttype, fontsize, x1 + 3, 4 + (y1 + y2) / 2,
		text, "")
	svg.group_footer()

svg.footer()
