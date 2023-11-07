#!/usr/bin/perl -w
#
# stackcollapse-instruments.pl
#
# Parses a file containing a call tree as produced by XCode Instruments
# (Edit > Deep Copy) and produces output suitable for flamegraph.pl.
#
# USAGE: ./stackcollapse-instruments.pl infile > outfile

use strict;

my @stack = ();

<>;
foreach (<>) {
	chomp;
	/\d+\.\d+ (?:min|s|ms)\s+\d+\.\d+%\s+(\d+(?:\.\d+)?) (min|s|ms)\t \t(\s*)(.+)/ or die;
	my $func = $4;
	my $depth = length ($3);
	$stack [$depth] = $4;
	foreach my $i (0 .. $depth - 1) {
		print $stack [$i];
		print ";";
	}

	my $time = 0 + $1;
	if ($2 eq "min") {
		$time *= 60*1000;
	} elsif ($2 eq "s") {
		$time *= 1000;
	}

	printf("%s %.0f\n", $func, $time);
}
