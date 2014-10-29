#!/usr/bin/perl -w
#
# difffolded.pl 	diff two folded stack files. Use this for generating
#			flame graph differentials.
#
# USAGE: ./difffolded.pl folded1 folded2 | ./flamegraph.pl > diff2.svg
#
# The flamegraph will be colored based on higher samples (red) and smaller
# samples (green). The frame widths will be based on the 2nd folded file.
# This might be confusing if stack frames disappear entirely; it will make
# the most sense to ALSO create a differential based on the 1st file widths,
# while switching the hues; eg:
#
#  ./difffolded.pl folded2 folded1 | ./flamegraph.pl --negate > diff1.svg
#
# Here's what they mean when comparing a before and after profile:
#
# diff1.svg: widths show the before profile, colored by what WILL happen
# diff2.svg: widths show the after profile, colored by what DID happen
#
# INPUT: See stackcollapse* programs.
#
# OUTPUT: The full list of stacks, with two columns, one from each file.
# If a stack wasn't present in a file, the column value is zero.
#
# folded_stack_trace count_from_folded1 count_from_folded2
#
# eg:
#
# funca;funcb;funcc 31 33
# ...
#
# COPYRIGHT: Copyright (c) 2014 Brendan Gregg.
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
# 28-Oct-2014	Brendan Gregg	Created this.

use strict;
use Getopt::Long;

my $normalize = 0;	# make sample counts equal

sub usage {
	print STDERR <<USAGE_END;
USAGE: $0 [-n] folded1 folded2 | flamegraph.pl > diff2.svg
	    -n       # normalize sample counts
See stackcollapse scripts for generating folded files.
Also consider flipping the files and hues to highlight reduced paths:
$0 folded2 folded1 | ./flamegraph.pl --negate > diff1.svg
USAGE_END
	exit 2;
}

usage if @ARGV < 2;
GetOptions(
	'normalize|n' => \$normalize
) or usage();


my ($total1, $total2) = (0, 0);
my %Folded;

my $file1 = $ARGV[0];
my $file2 = $ARGV[1];

open FILE, $file1 or die "ERROR: Can't read $file1\n";
while (<FILE>) {
	chomp;
	my ($stack, $count) = (/^(.*)\s+?(\d+(?:\.\d*)?)$/);
	$Folded{$stack}{1} += $count;
	$total1 += $count;
}
close FILE;

open FILE, $file2 or die "ERROR: Can't read $file2\n";
while (<FILE>) {
	chomp;
	my ($stack, $count) = (/^(.*)\s+?(\d+(?:\.\d*)?)$/);
	$Folded{$stack}{2} += $count;
	$total2 += $count;
}
close FILE;

foreach my $stack (keys %Folded) {
	$Folded{$stack}{1} = 0 unless defined $Folded{$stack}{1};
	$Folded{$stack}{2} = 0 unless defined $Folded{$stack}{2};
	if ($normalize && $total1 != $total2) {
		$Folded{$stack}{1} = int($Folded{$stack}{1} * $total2 / $total1);
	}
	print "$stack $Folded{$stack}{1} $Folded{$stack}{2}\n";
}
