#!/usr/bin/perl -w
#
# flamegraph.pl		flame stack grapher.
#
# This takes stack samples and renders a call graph, allowing hot functions
# and codepaths to be quickly identified.  Stack samples can be generated using
# tools such as DTrace, perf, SystemTap, and Instruments.
#
# USAGE: ./flamegraph.pl [options] input.txt > graph.svg
#
#        grep funcA input.txt | ./flamegraph.pl [options] > graph.svg
#
# Options are listed in the usage message (--help).
#
# The input is stack frames and sample counts formatted as single lines.  Each
# frame in the stack is semicolon separated, with a space and count at the end
# of the line.  These can be generated using DTrace with stackcollapse.pl,
# and other tools using the stackcollapse variants.
#
# The output graph shows relative presence of functions in stack samples.  The
# ordering on the x-axis has no meaning; since the data is samples, time order
# of events is not known.  The order used sorts function names alphabetically.
#
# While intended to process stack samples, this can also process stack traces.
# For example, tracing stacks for memory allocation, or resource usage.  You
# can use --title to set the title to reflect the content, and --countname
# to change "samples" to "bytes" etc.
#
# There are a few different palettes, selectable using --color.  Functions
# called "-" will be printed gray, which can be used for stack separators (eg,
# between user and kernel stacks).
#
# HISTORY
#
# This was inspired by Neelakanth Nadgir's excellent function_call_graph.rb
# program, which visualized function entry and return trace events.  As Neel
# wrote: "The output displayed is inspired by Roch's CallStackAnalyzer which
# was in turn inspired by the work on vftrace by Jan Boerhout".  See:
# https://blogs.oracle.com/realneel/entry/visualizing_callstacks_via_dtrace_and
#
# Copyright 2011 Joyent, Inc.  All rights reserved.
# Copyright 2011 Brendan Gregg.  All rights reserved.
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
# 21-Nov-2013   Shawn Sterling  Added consistent palette file option
# 17-Mar-2013   Tim Bunce       Added options and more tunables.
# 15-Dec-2011	Dave Pacheco	Support for frames with whitespace.
# 10-Sep-2011	Brendan Gregg	Created this.

use strict;

use Getopt::Long;

# tunables
my $encoding;
my $fonttype = "Verdana";
my $imagewidth = 1200;          # max width, pixels
my $frameheight = 16;           # max height is dynamic
my $fontsize = 12;              # base text size
my $fontwidth = 0.59;           # avg width relative to fontsize
my $minwidth = 0.1;             # min function width, pixels
my $titletext = "Flame Graph";  # centered heading
my $nametype = "Function:";     # what are the names in the data?
my $countname = "samples";      # what are the counts in the data?
my $colors = "hot";             # color theme
my $bgcolor1 = "#eeeeee";       # background color gradient start
my $bgcolor2 = "#eeeeb0";       # background color gradient stop
my $nameattrfile;               # file holding function attributes
my $timemax;                    # (override the) sum of the counts
my $factor = 1;                 # factor to scale counts by
my $hash = 0;                   # color by function name
my $palette = 0;                # if we use consistent palettes (default off)
my %palette_map;                # palette map hash
my $pal_file = "palette.map";   # palette map file name

GetOptions(
	'fonttype=s'  => \$fonttype,
	'width=i'     => \$imagewidth,
	'height=i'    => \$frameheight,
	'encoding=s'  => \$encoding,
	'fontsize=f'  => \$fontsize,
	'fontwidth=f' => \$fontwidth,
	'minwidth=f'  => \$minwidth,
	'title=s'     => \$titletext,
	'nametype=s'  => \$nametype,
	'countname=s' => \$countname,
	'nameattr=s'  => \$nameattrfile,
	'total=s'     => \$timemax,
	'factor=f'    => \$factor,
	'colors=s'    => \$colors,
	'hash'        => \$hash,
	'cp'          => \$palette,
) or die <<USAGE_END;
USAGE: $0 [options] infile > outfile.svg\n
	--title       # change title text
	--width       # width of image (default 1200)
	--height      # height of each frame (default 16)
	--minwidth    # omit smaller functions (default 0.1 pixels)
	--fonttype    # font type (default "Verdana")
	--fontsize    # font size (default 12)
	--countname   # count type label (default "samples")
	--nametype    # name type label (default "Function:")
	--colors      # "hot", "mem", "io" palette (default "hot")
	--hash        # colors are keyed by function name hash
	--cp          # use consistent palette (palette.map)

	eg,
	$0 --title="Flame Graph: malloc()" trace.txt > graph.svg
USAGE_END

# internals
my $ypad1 = $fontsize * 4;      # pad top, include title
my $ypad2 = $fontsize * 2 + 10; # pad bottom, include labels
my $xpad = 10;                  # pad lefm and right
my $depthmax = 0;
my %Events;
my %nameattr;

if ($nameattrfile) {
	# The name-attribute file format is a function name followed by a tab then
	# a sequence of tab separated name=value pairs.
	open my $attrfh, $nameattrfile or die "Can't read $nameattrfile: $!\n";
	while (<$attrfh>) {
		chomp;
		my ($funcname, $attrstr) = split /\t/, $_, 2;
		die "Invalid format in $nameattrfile" unless defined $attrstr;
		$nameattr{$funcname} = { map { split /=/, $_, 2 } split /\t/, $attrstr };
	}
}

if ($colors eq "mem") { $bgcolor1 = "#eeeeee"; $bgcolor2 = "#e0e0ff"; }
if ($colors eq "io")  { $bgcolor1 = "#f8f8f8"; $bgcolor2 = "#e8e8e8"; }

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
		my $enc_attr = '';
		if (defined $encoding) {
			$enc_attr = qq{ encoding="$encoding"};
		}
		$self->{svg} .= <<SVG;
<?xml version="1.0"$enc_attr standalone="no"?>
<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
<svg version="1.1" width="$w" height="$h" onload="init(evt)" viewBox="0 0 $w $h" xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink">
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

	sub group_start {
		my ($self, $attr) = @_;

		my @g_attr = map {
			exists $attr->{$_} ? sprintf(qq/$_="%s"/, $attr->{$_}) : ()
		} qw(class style onmouseover onmouseout);
		push @g_attr, $attr->{g_extra} if $attr->{g_extra};
		$self->{svg} .= sprintf qq/<g %s>\n/, join(' ', @g_attr);

		$self->{svg} .= sprintf qq/<title>%s<\/title>/, $attr->{title}
			if $attr->{title}; # should be first element within g container

		if ($attr->{href}) {
			my @a_attr;
			push @a_attr, sprintf qq/xlink:href="%s"/, $attr->{href} if $attr->{href};
			# default target=_top else links will open within SVG <object>
			push @a_attr, sprintf qq/target="%s"/, $attr->{target} || "_top";
			push @a_attr, $attr->{a_extra}                           if $attr->{a_extra};
			$self->{svg} .= sprintf qq/<a %s>/, join(' ', @a_attr);
		}
	}

	sub group_end {
		my ($self, $attr) = @_;
		$self->{svg} .= qq/<\/a>\n/ if $attr->{href};
		$self->{svg} .= qq/<\/g>\n/;
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

sub namehash {
	# Generate a vector hash for the name string, weighting early over
	# later characters. We want to pick the same colors for function
	# names across different flame graphs.
	my $name = shift;
	my $vector = 0;
	my $weight = 1;
	my $max = 1;
	my $mod = 10;
	# if module name present, trunc to 1st char
	$name =~ s/.(.*?)`//;
	foreach my $c (split //, $name) {
		my $i = (ord $c) % $mod;
		$vector += ($i / ($mod++ - 1)) * $weight;
		$max += 1 * $weight;
		$weight *= 0.70;
		last if $mod > 12;
	}
	return (1 - $vector / $max)
}

sub color {
	my ($type, $hash, $name) = @_;
	my ($v1, $v2, $v3);
	if ($hash) {
		$v1 = namehash($name);
		$v2 = $v3 = namehash(scalar reverse $name);
	} else {
		$v1 = rand(1);
		$v2 = rand(1);
		$v3 = rand(1);
	}
	if (defined $type and $type eq "hot") {
		my $r = 205 + int(50 * $v3);
		my $g = 0 + int(230 * $v1);
		my $b = 0 + int(55 * $v2);
		return "rgb($r,$g,$b)";
	}
	if (defined $type and $type eq "mem") {
		my $r = 0;
		my $g = 190 + int(50 * $v2);
		my $b = 0 + int(210 * $v1);
		return "rgb($r,$g,$b)";
	}
	if (defined $type and $type eq "io") {
		my $r = 80 + int(60 * $v1);
		my $g = $r;
		my $b = 190 + int(55 * $v2);
		return "rgb($r,$g,$b)";
	}
	return "rgb(0,0,0)";
}

sub color_map {
	my ($colors, $func) = @_;
	if (exists $palette_map{$func}) {
		return $palette_map{$func};
	} else {
		$palette_map{$func} = color($colors);
		return $palette_map{$func};
	}
}

sub write_palette {
	open(FILE, ">$pal_file");
	foreach my $key (sort keys %palette_map) {
		print FILE $key."->".$palette_map{$key}."\n";
	}
	close(FILE);
}

sub read_palette {
	if (-e $pal_file) {
	open(FILE, $pal_file) or die "can't open file $pal_file: $!";
	while ( my $line = <FILE>) {
		chomp($line);
		(my $key, my $value) = split("->",$line);
		$palette_map{$key}=$value;
	}
	close(FILE)
	}
}

my %Node;
my %Tmp;

sub flow {
	my ($last, $this, $v) = @_;

	my $len_a = @$last - 1;
	my $len_b = @$this - 1;

	my $i = 0;
	my $len_same;
	for (; $i <= $len_a; $i++) {
		last if $i > $len_b;
		last if $last->[$i] ne $this->[$i];
	}
	$len_same = $i;

	for ($i = $len_a; $i >= $len_same; $i--) {
		my $k = "$last->[$i];$i";
		# a unique ID is constructed from "func;depth;etime";
		# func-depth isn't unique, it may be repeated later.
		$Node{"$k;$v"}->{stime} = delete $Tmp{$k}->{stime};
		delete $Tmp{$k};
	}

	for ($i = $len_same; $i <= $len_b; $i++) {
		my $k = "$this->[$i];$i";
		$Tmp{$k}->{stime} = $v;
	}

        return $this;
}

# Parse input
my @Data = <>;
my $last = [];
my $time = 0;
my $ignored = 0;
foreach (sort @Data) {
	chomp;
	my ($stack, $samples) = (/^(.*)\s+(\d+(?:\.\d*)?)$/);
	unless (defined $samples) {
		++$ignored;
		next;
	}
	$stack =~ tr/<>/()/;
	$last = flow($last, [ '', split ";", $stack ], $time);
	$time += $samples;
}
flow($last, [], $time);
warn "Ignored $ignored lines with invalid format\n" if $ignored;
die "ERROR: No stack counts found\n" unless $time;

if ($timemax and $timemax < $time) {
	warn "Specified --total $timemax is less than actual total $time, so ignored\n"
	if $timemax/$time > 0.02; # only warn is significant (e.g., not rounding etc)
	undef $timemax;
}
$timemax ||= $time;

my $widthpertime = ($imagewidth - 2 * $xpad) / $timemax;
my $minwidth_time = $minwidth / $widthpertime;

# prune blocks that are too narrow and determine max depth
while (my ($id, $node) = each %Node) {
	my ($func, $depth, $etime) = split ";", $id;
	my $stime = $node->{stime};
	die "missing start for $id" if not defined $stime;

	if (($etime-$stime) < $minwidth_time) {
		delete $Node{$id};
		next;
	}
	$depthmax = $depth if $depth > $depthmax;
}

# Draw canvas
my $imageheight = ($depthmax * $frameheight) + $ypad1 + $ypad2;
my $im = SVG->new();
$im->header($imagewidth, $imageheight);
my $inc = <<INC;
<defs >
	<linearGradient id="background" y1="0" y2="1" x1="0" x2="0" >
		<stop stop-color="$bgcolor1" offset="5%" />
		<stop stop-color="$bgcolor2" offset="95%" />
	</linearGradient>
</defs>
<style type="text/css">
	.func_g:hover { stroke:black; stroke-width:0.5; }
</style>
<script type="text/ecmascript">
<![CDATA[
	var details;
	function init(evt) { details = document.getElementById("details").firstChild; }
	function s(info) { details.nodeValue = "$nametype " + info; }
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
$im->stringTTF($black, $fonttype, $fontsize + 5, 0.0, int($imagewidth / 2), $fontsize * 2, $titletext, "middle");
$im->stringTTF($black, $fonttype, $fontsize, 0.0, $xpad, $imageheight - ($ypad2 / 2), " ", "", 'id="details"');

if ($palette) {
	read_palette();
}
# Draw frames

while (my ($id, $node) = each %Node) {
	my ($func, $depth, $etime) = split ";", $id;
	my $stime = $node->{stime};

	$etime = $timemax if $func eq "" and $depth == 0;

	my $x1 = $xpad + $stime * $widthpertime;
	my $x2 = $xpad + $etime * $widthpertime;
	my $y1 = $imageheight - $ypad2 - ($depth + 1) * $frameheight + 1;
	my $y2 = $imageheight - $ypad2 - $depth * $frameheight;

	my $samples = sprintf "%.0f", ($etime - $stime) * $factor;
	(my $samples_txt = $samples) # add commas per perlfaq5
		=~ s/(^[-+]?\d+?(?=(?>(?:\d{3})+)(?!\d))|\G\d{3}(?=\d))/$1,/g;

	my $info;
	if ($func eq "" and $depth == 0) {
		$info = "all ($samples_txt $countname, 100%)";
	} else {
		my $pct = sprintf "%.2f", ((100 * $samples) / ($timemax * $factor));
		my $escaped_func = $func;
		$escaped_func =~ s/&/&amp;/g;
		$escaped_func =~ s/</&lt;/g;
		$escaped_func =~ s/>/&gt;/g;
		$info = "$escaped_func ($samples_txt $countname, $pct%)";
	}

	my $nameattr = { %{ $nameattr{$func}||{} } }; # shallow clone
	$nameattr->{class}       ||= "func_g";
	$nameattr->{onmouseover} ||= "s('".$info."')";
	$nameattr->{onmouseout}  ||= "c()";
	$nameattr->{title}       ||= $info;
	$im->group_start($nameattr);

	if ($palette) {
		$im->filledRectangle($x1, $y1, $x2, $y2, color_map($colors, $func), 'rx="2" ry="2"');
	} else {
		my $color = $func eq "-" ? $vdgrey : color($colors, $hash, $func);
		$im->filledRectangle($x1, $y1, $x2, $y2, $color, 'rx="2" ry="2"');
	}

	my $chars = int( ($x2 - $x1) / ($fontsize * $fontwidth));
	if ($chars >= 3) { # room for one char plus two dots
		my $text = substr $func, 0, $chars;
		substr($text, -2, 2) = ".." if $chars < length $func;
		$text =~ s/&/&amp;/g;
		$text =~ s/</&lt;/g;
		$text =~ s/>/&gt;/g;
		$im->stringTTF($black, $fonttype, $fontsize, 0.0, $x1 + 3, 3 + ($y1 + $y2) / 2, $text, "");
	}

	$im->group_end($nameattr);
}

print $im->svg;

if ($palette) {
	write_palette();
}

# vim: ts=8 sts=8 sw=8 noexpandtab
