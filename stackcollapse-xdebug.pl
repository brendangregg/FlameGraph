#!/usr/bin/env perl -W
#
# stackcollapse-xdebug.pl collapse multiline stacks into single lines.
#
# Parses the xdebug trace output file and prints out a collapsed output.
#
# USAGE: ./stackcollapse-xdebug.pl infile > outfile
#
# Example input:
#
# Version: 3.0.3
# File format: 4
# TRACE START [2021-03-08 19:19:30.099826]
# 1	0	0	0.000673	395256	{main}	1		/Users/ikaraszi/_vc/github/FlameGraph/test/test.php	0	0
# 2	1	0	0.000910	395256	func	1		/Users/ikaraszi/_vc/github/FlameGraph/test/test.php	8	0
# 2	1	1	0.000939	395256
#
# Example output:
#
# {main} 381007.000000007
# {main};func 440711.999999802
#
# Copyright 2021 István Karaszi under MIT license
# 

use strict;
use constant SCALE_FACTOR => 1000000;

my %collapsed;
my @stack;

my $trace_started = 0;
my $prev_start_time = 0;

sub remember_stack {
	my ($stack, $delta) = @_;
	$collapsed{$stack} += $delta;
}

foreach (<>) {
    chomp;

    if (/^TRACE START/) {
        $trace_started = 1;
        next;
    }

    next unless $trace_started;

    if (/^(\t|TRACE END)/) {
        last;
    }

    my ($level, $fn_no, $is_exit, $time, $memory, $func_name) = split(/\t+/, $_, 7);

    if ($is_exit eq '1' && !@stack) {
        print STDERR "[WARNING] Found function exit without corresponding entrance. Discarding line. Check your input.\n";
        next;
    }

    if (@stack) {
        my $joined = join(";", @stack);
        my $delta = $time - $prev_start_time;

        remember_stack($joined, $delta * SCALE_FACTOR) 
    }

    if ($is_exit eq '1') {
        pop(@stack);
    } else {
        push(@stack, $func_name);
    }

    $prev_start_time = $time;
}

foreach my $k (sort { $a cmp $b } keys %collapsed) {
	print "$k $collapsed{$k}\n";
}
