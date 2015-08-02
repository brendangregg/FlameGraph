#!/usr/bin/perl -w
#
# thcstackcollapse.pl	collapse thread hot/cold multiline stacks into
#			single lines.
#
# EXPERIMENTAL: This is a work in progress, and may not work properly.
#
# Parses a multiline stack followed by thread ID, PID, TID, name, oncpu status,
# and ms on a separate line (see example below) and outputs a comma separated
# stack followed by a space and the numbers. If memory addresses (+0xd) are
# present, they are stripped, and resulting identical stacks are colased with
# their counts summed.
#
# USAGE: ./thcstackcollapse.pl infile > outfile
#
# Example input:
#
# mysqld`_Z10do_commandP3THD+0xd4
# mysqld`handle_one_connection+0x1a6
# libc.so.1`_thrp_setup+0x8d
# libc.so.1`_lwp_start
# thread:0x78372480 pid:826 tid:3 name:mysqld oncpu:1 ms:2664
#
# Example output:
#
# libc.so.1`_lwp_start,libc.so.1`_thrp_setup,mysqld`handle_one_connection,mysqld`_Z10do_commandP3THD 0x78372480 826 3 mysqld 1 2664
#
# Input may contain many stacks, and can be generated using DTrace.  The
# first few lines of input are skipped (see $headerlines).
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
# or http://www.opensolaris.org/os/licensing.
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
# 14-Aug-2011	Brendan Gregg	Created this.

use strict;

my %collapsed;
my $headerlines = 2;

sub remember_stack {
	my ($stack, $thread, $pid, $tid, $name, $oncpu, $count) = @_;
	$collapsed{"$stack $thread $pid $tid $name $oncpu"} += $count;
}

my $nr = 0;
my @stack;

foreach (<>) {
	next if $nr++ < $headerlines;
	chomp;

	next if (m/^\s*$/);

	if (m/^thread:(\d+) pid:(\d+) tid:(\d+) name:(.*?) oncpu:(\d+) ms:(\d+)$/) {
		remember_stack(join(",", @stack), $1, $2, $3, $4, $5, $6) if $6 > 0;
		@stack = ();
		next;
	}

	my $frame = $_;
	$frame =~ s/^\s*//;
	$frame =~ s/\+.*$//;
	$frame = "-" if $frame eq "";
	unshift @stack, $frame;
}

foreach my $k (sort { $a cmp $b } keys %collapsed) {
	print "$k $collapsed{$k}\n";
}
