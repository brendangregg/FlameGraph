#!/usr/bin/perl -w
#
# hcstackcolllapse.pl	collapse hot/cold multiline stacks into single lines.
#
# EXPERIMENTAL: This is a work in progress, and may not work properly.
#
# Parses a multiline stack followed by oncpu status and ms on a separate line
# (see example below) and outputs a comma separated stack followed by a space
# and the number. If memory addresses (+0xd) are present, they are stripped,
# and resulting identical stacks are colased with their counts summed.
#
# USAGE: ./hcstackcollapse.pl infile > outfile
#
# Example input:
#
# mysqld`_Z10do_commandP3THD+0xd4
# mysqld`handle_one_connection+0x1a6
# libc.so.1`_thrp_setup+0x8d
# libc.so.1`_lwp_start
# oncpu:1 ms:2664
#
# Example output:
#
# libc.so.1`_lwp_start,libc.so.1`_thrp_setup,mysqld`handle_one_connection,mysqld`_Z10do_commandP3THD oncpu:1 ms:2664
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
# 14-Aug-2011	Brendan Gregg	Created this.

use strict;

my %collapsed;
my $headerlines = 2;

sub remember_stack {
	my ($stack, $oncpu, $count) = @_;
	$collapsed{"$stack $oncpu"} += $count;
}

my $nr = 0;
my @stack;

foreach (<>) {
	next if $nr++ < $headerlines;
	chomp;

	if (m/^oncpu:(\d+) ms:(\d+)$/) {
		remember_stack(join(",", @stack), $1, $2) unless $2 == 0;
		@stack = ();
		next;
	}

	next if (m/^\s*$/);

	my $frame = $_;
	$frame =~ s/^\s*//;
	$frame =~ s/\+.*$//;
	$frame = "-" if $frame eq "";
	unshift @stack, $frame;
}

foreach my $k (sort { $a cmp $b } keys %collapsed) {
	print "$k $collapsed{$k}\n";
}
