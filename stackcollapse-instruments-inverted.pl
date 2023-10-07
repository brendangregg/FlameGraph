#!/usr/bin/perl -w
#
# stackcollapse-instruments-inverted.pl
#
# Parses a file containing a call tree as produced by Xcode Instruments
# (Edit > Deep Copy) from an inverted call tree and produces output
# suitable for flamegraph.pl.
#
# USAGE: ./stackcollapse-instruments-inverted.pl infile > outfile

use strict;

my @symbolstack = ();
my @timestack = ();
my $prevdepth = -1;

<>;
foreach (<>) {
	chomp;
	/(\d+\.\d+) (min|s|ms)\s+\d+\.\d+%\s+(?:\d+(?:\.\d+)?) (?:min|s|ms)\t \t(\s*)(.+)/ or die;
	my $func = $4;
	my $depth = length ($3);

	my $time = 0 + $1;
	if ($2 eq "min") {
		$time *= 60*1000;
	} elsif ($2 eq "s") {
		$time *= 1000;
	}

	if ($depth <= $prevdepth) { # previous entry was *not* an intermediate towards us
		foreach my $prei ($depth .. $prevdepth) {
			my $i = $depth + ( $prevdepth - $prei );
			foreach my $j (0 .. $i - 1) {
				print $symbolstack [$j];
				print ";";
			}
			printf("%s %.0f\n", $symbolstack [$i], $timestack [$i]);
		}
	}

	$symbolstack [$depth] = $4;
	$timestack [$depth] = $time;
	if ($depth != 0) {
		$timestack [$depth - 1] -= $time;
	}

	$prevdepth = $depth;
}

if ($prevdepth != -1) {
	# last entry was *not* an intermediate towards ayone
	foreach my $prei (0 .. $prevdepth) {
		my $i = $prevdepth - $prei;
		foreach my $j (0 .. $i - 1) {
			print $symbolstack [$j];
			print ";";
		}
		printf("%s %.0f\n", $symbolstack [$i], $timestack [$i]);
	}
}
