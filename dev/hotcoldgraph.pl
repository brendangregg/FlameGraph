#!/usr/bin/perl -w
#
# hotcoldgraph.pl	flame/cold stack grapher.
#
# EXPERIMENTAL: This is a work in progress, and may not work properly.
#
# This takes on and off-cpu stack timings (see hcstackcollapse.pl) and
# renders a call graph, allowing latency in codepaths to be quickly identified.
#
# USAGE: ./hotcoldgraph.pl input.txt > graph.svg
#
#        grep funcA input.txt | ./hotcoldgraph.pl > graph.svg
#
# The input is stack frames and sample counts formatted as single lines.  Each
# frame in the stack is comma separated, with a space and count at the end of
# the line.  These can be generated using DTrace with stackcollapse.pl.
#
# The output graph shows relative presense of functions in stack samples.  The
# ordering on the x-axis has no meaning; since the data is samples, time order
# of events is not known.  The order used sorts function names alphabeticly.
#
# HISTORY
#
# This was inspired by Neelakanth Nadgir's excellent function_call_graph.rb
# program, which visualized function entry and return trace events.  As Neel
# wrote: "The output displayed is inspired by Roch's CallStackAnalyzer which
# was in turn inspired by the work on vftrace by Jan Boerhout".  See:
# http://blogs.sun.com/realneel/entry/visualizing_callstacks_via_dtrace_and
#
# For the on-CPU graph only, see flamegraph.pl.
#
# Copyright 2013 Joyent, Inc.  All rights reserved.
# Copyright 2013 Brendan Gregg.  All rights reserved.
#
# CDDL HEADER START
#
# The contents of this file are subject to the terms of the
# Common Development and Distribution License (the "License").
# You may not use this file except in compliance with the License.
#
# You can obtain a copy of the license at usr/src/OPENSOLARIS.LICENSE
# or http://opensource.org/licenses/CDDL-1.0.
# See the License for the specific language governing permissions
# and limitations under the License.
#
# When distributing Covered Code, include this CDDL HEADER in each
# file and include the License file at usr/src/OPENSOLARIS.LICENSE.
# If applicable, add the following below this CDDL HEADER, with the
# fields enclosed by brackets "[]" replaced with your own identifying
# information: Portions Copyright [yyyy] [name of copyright owner]
#
# CDDL HEADER END  
#
# 10-Sep-2011	Brendan Gregg	Created this.

use strict;

# tunables
my $fonttype = "Verdana";
my $imagewidth = 1200;		# max width, pixels
my $frameheight = 16;		# max height is dynamic
my $fontsize = 12;		# base text size
my $minwidth = 0.1;		# min function width, pixels

# internals
my $ypad1 = $fontsize * 4;	# pad top, include title
my $ypad2 = $fontsize * 2 + 10;	# pad bottom, include labels
my $xpad = 10;			# pad lefm and right
my $timemax = 0;
my $depthmax = 0;
my %Events;

# SVG functions
{ package SVG;
	sub new {
		my $class = shift;
		my $self = {};
		bless ($self, $class);
		return $self;
	}

	sub header {
		my ($self, $w, $h) = @_;
		$self->{svg} .= <<SVG;
<?xml version="1.0" standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" width="$w" height="$h" onload="init(evt)" viewBox="0 0 $w $h" xmlns="http://www.w3.org/2000/svg" >
SVG
	}

	sub include {
		my ($self, $content) = @_;
		$self->{svg} .= $content;
	}

	sub colorAllocate {
		my ($self, $r, $g, $b) = @_;
		return "rgb($r,$g,$b)";
	}

	sub filledRectangle {
		my ($self, $x1, $y1, $x2, $y2, $fill, $extra) = @_;
		$x1 = sprintf "%0.1f", $x1;
		$x2 = sprintf "%0.1f", $x2;
		my $w = sprintf "%0.1f", $x2 - $x1;
		my $h = sprintf "%0.1f", $y2 - $y1;
		$extra = defined $extra ? $extra : "";
		$self->{svg} .= qq/<rect x="$x1" y="$y1" width="$w" height="$h" fill="$fill" $extra \/>\n/;
	}

	sub stringTTF {
		my ($self, $color, $font, $size, $angle, $x, $y, $str, $loc, $extra) = @_;
		$loc = defined $loc ? $loc : "left";
		$extra = defined $extra ? $extra : "";
		$self->{svg} .= qq/<text text-anchor="$loc" x="$x" y="$y" font-size="$size" font-family="$font" fill="$color" $extra >$str<\/text>\n/;
	}

	sub svg {
		my $self = shift;
		return "$self->{svg}</svg>\n";
	}
	1;
}

sub color {
	my $type = shift;
	if (defined $type and $type eq "hot") {
		my $r = 205 + int(rand(50));
		my $g = 0 + int(rand(230));
		my $b = 0 + int(rand(55));
		return "rgb($r,$g,$b)";
	}
	if (defined $type and $type eq "cold") {
		my $r = 0 + int(rand(40));
		my $b = 205 + int(rand(50));
		my $g = 0 + int(rand(150));
		return "rgb($r,$g,$b)";
	}
	return "rgb(0,0,0)";
}

my %Node;
my %Tmp;

sub flow {
	my ($a, $b, $ca, $cb, $v) = @_;
	my @A = split ",", $a;
	my @B = split ",", $b;

	my $len_a = $#A;
	my $len_b = $#B;
	$depthmax = $len_b if $len_b > $depthmax;

	my $i = 0;
	my $len_same = 0;
	for (; $i <= $len_a; $i++) {
		last if $i > $len_b;
		last if $A[$i] ne $B[$i];
	}
	$len_same = $i;
	$len_same = 0 if $ca != $cb;

	for ($i = $len_a; $i >= $len_same; $i--) {
		my $k = "$A[$i]-$i";
		# a unique ID is constructed from func-depth-etime;
		# func-depth isn't unique, it may be repeated later.
		$Node{"$k-$v-$ca"}->{stime} = $Tmp{$k}->{stime};
		delete $Tmp{$k}->{stime};
		delete $Tmp{$k};
	}

	for ($i = $len_same; $i <= $len_b; $i++) {
		my $k = "$B[$i]-$i";
		$Tmp{$k}->{stime} = $v;
	}
}

# Parse input
my @Data = <>;
my $laststack = "";
my $lastcpu = 0;
my $time = 0;
foreach (sort @Data) {
	chomp;
	my ($stack, $cpu, $samples) = split ' ';
	$stack = ",$stack";
	next unless defined $samples;
	flow($laststack, $stack, $lastcpu, $cpu, $time);
	$time += $samples;
	$laststack = $stack;
	$lastcpu = $cpu;
}
flow($laststack, "", $lastcpu, 0, $time);
$timemax = $time or die "ERROR: No stack counts found\n";

# Draw canvas
my $widthpertime = ($imagewidth - 2 * $xpad) / $timemax;
my $imageheight = ($depthmax * $frameheight) + $ypad1 + $ypad2;
my $im = SVG->new();
$im->header($imagewidth, $imageheight);
my $inc = <<INC;
<defs >
	<linearGradient id="background" y1="0" y2="1" x1="0" x2="0" >
		<stop stop-color="#eeeeee" offset="5%" />
		<stop stop-color="#eeeeb0" offset="95%" />
	</linearGradient>
</defs>
<style type="text/css">
	rect[rx]:hover { stroke:black; stroke-width:1; }
	text:hover { stroke:black; stroke-width:1; stroke-opacity:0.35; }
</style>
<script type="text/ecmascript">
<![CDATA[
	var details;
	function init(evt) { details = document.getElementById("details").firstChild; }
	function s(info) { details.nodeValue = info; }
	function c() { details.nodeValue = ' '; }
]]>
</script>
INC
$im->include($inc);
$im->filledRectangle(0, 0, $imagewidth, $imageheight, 'url(#background)');
my ($white, $black, $vvdgrey, $vdgrey) = (
	$im->colorAllocate(255, 255, 255),
	$im->colorAllocate(0, 0, 0),
	$im->colorAllocate(40, 40, 40),
	$im->colorAllocate(160, 160, 160),
    );
$im->stringTTF($black, $fonttype, $fontsize + 5, 0.0, int($imagewidth / 2), $fontsize * 2, "Flame Graph", "middle");
$im->stringTTF($black, $fonttype, $fontsize, 0.0, $xpad, $imageheight - ($ypad2 / 2), 'Function:');
$im->stringTTF($black, $fonttype, $fontsize, 0.0, $xpad + 60, $imageheight - ($ypad2 / 2), " ", "", 'id="details"');

# Draw frames
foreach my $id (keys %Node) {
	my ($func, $depth, $etime, $cpu) = split "-", $id;
	die "missing start for $id" if !defined $Node{$id}->{stime};
	my $stime = $Node{$id}->{stime};
	my $samples = $etime - $stime;

	my $x1 = $xpad + $stime * $widthpertime;
	my $x2 = $xpad + $etime * $widthpertime;
	my $width = $x2 - $x1;
	next if $width < $minwidth;

	my $y1 = $imageheight - $ypad2 - ($depth + 1) * $frameheight + 1;
	my $y2 = $imageheight - $ypad2 - $depth * $frameheight;

	my $info;
	if ($func eq "" and $depth == 0) {
		$info = "all ($samples ms, 100%)";
	} else {
		my $pct = sprintf "%.2f", ((100 * $samples) / $timemax);
		$info = "$func ($samples ms, $pct%)";
	}
	my $color = $cpu ? "hot" : "cold";
	$im->filledRectangle($x1, $y1, $x2, $y2, color($color), 'rx="2" ry="2" onmouseover="s(' . "'$info'" . ')" onmouseout="c()"');

	if ($width > 50) {
		my $chars = int($width / (0.7 * $fontsize));
		my $text = substr $func, 0, $chars;
		$text .= ".." if $chars < length $func;
		$im->stringTTF($black, $fonttype, $fontsize, 0.0, $x1 + 3, 3 + ($y1 + $y2) / 2, $text, "",
		    'onmouseover="s(' . "'$info'" . ')" onmouseout="c()"');
	}
}

print $im->svg;
