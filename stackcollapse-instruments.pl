#!/usr/bin/perl -w
#
# stackcollapse-instruments.pl
#
# Parses a CSV file containing a call tree as produced by XCode
# Instruments and produces output suitable for flamegraph.pl.
#
# USAGE: ./stackcollapse-instruments.pl infile > outfile

use strict;

my @stack = ();

<>;
foreach (<>) {
	chomp;
	/\d+\.\d+ms[^,]+,(\d+(?:\.\d*)?),\s+,(\s*)(.+)/ or die;
	my $func = $3;
	my $depth = length ($2);
	$stack [$depth] = $3;
	foreach my $i (0 .. $depth - 1) {
		print $stack [$i];
		print ";";
	}
	print "$func $1\n";
}
