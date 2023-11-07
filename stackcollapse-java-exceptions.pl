#!/usr/bin/perl -w
#
# stackcolllapse-java-exceptions.pl	collapse java exceptions (found in logs) into single lines.
#
# Parses Java error stacks found in a log file and outputs them as
# single lines, with methods separated by semicolons, and then a space and an
# occurrence count. Inspired by stackcollapse-jstack.pl except that it does
# not act as a performance profiler.
#
# It can be useful if a Java process dumps a lot of different stacks in its logs
# and you want to quickly identify the biggest culprits.
#
# USAGE: ./stackcollapse-java-exceptions.pl infile > outfile
#
# Copyright 2018 Paul de Verdiere. All rights reserved.

use strict;
use Getopt::Long;

# tunables
my $shorten_pkgs = 0;		# shorten package names
my $no_pkgs = 0;		    # really shorten package names!!
my $help = 0;

sub usage {
	die <<USAGE_END;
USAGE: $0 [options] infile > outfile\n
	--shorten-pkgs : shorten package names
  --no-pkgs      : suppress package names (makes SVG much more readable)

USAGE_END
}

GetOptions(
	'shorten-pkgs!'   => \$shorten_pkgs,
	'no-pkgs!'        => \$no_pkgs,
	'help'            => \$help,
) or usage();
$help && usage();

my %collapsed;

sub remember_stack {
	my ($stack, $count) = @_;
	$collapsed{$stack} += $count;
}

my @stack;

foreach (<>) {
	chomp;

  if (/^\s*at ([^\(]*)/) {
		my $func = $1;
		if ($shorten_pkgs || $no_pkgs) {
			my ($pkgs, $clsFunc) = ( $func =~ m/(.*\.)([^.]+\.[^.]+)$/ );
			$pkgs =~ s/(\w)\w*/$1/g;
      $func = $no_pkgs ? $clsFunc: $pkgs . $clsFunc;
		}
		unshift @stack, $func;
	} elsif (@stack ) {
		next if m/.*waiting on .*/;
		remember_stack(join(";", @stack), 1) if @stack;
		undef @stack;
  }
}

remember_stack(join(";", @stack), 1) if @stack;

foreach my $k (sort { $a cmp $b } keys %collapsed) {
	print "$k $collapsed{$k}\n";
}
