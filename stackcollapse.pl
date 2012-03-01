#!/usr/bin/perl -w
#
# stackcolllapse.pl	collapse multiline stacks into single lines.
#
# Parses a multiline stack followed by a number on a separate line, and
# outputs a comma separated stack followed by a space and the number.
# If memory addresses (+0xd) are present, they are stripped, and resulting
# identical stacks are colased with their counts summed.
#
# USAGE: ./stackcollapse.pl infile > outfile
#
# Example input:
#
#  unix`i86_mwait+0xd
#  unix`cpu_idle_mwait+0xf1
#  unix`idle+0x114
#  unix`thread_start+0x8
#  1641
#
# Example output:
#
#  unix`thread_start,unix`idle,unix`cpu_idle_mwait,unix`i86_mwait 1641
#
# Input may contain many stacks, and can be generated using DTrace.  The
# first few lines of input are skipped (see $headerlines).
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
my $headerlines = 3;

sub remember_stack {
	my ($stack, $count) = @_;
	$collapsed{$stack} += $count;
}

my $nr = 0;
my @stack;

foreach (<>) {
	next if $nr++ < $headerlines;
	chomp;

	if (m/^\s*(\d+)+$/) {
		remember_stack(join(",", @stack), $1);
		@stack = ();
		next;
	}

	next if (m/^\s*$/);

	my $frame = $_;
	$frame =~ s/^\s*//;
	$frame =~ s/\+.*$//;
	# Remove arguments from C++ function names.
	$frame =~ s/(..)[(<].*/$1/;
	$frame = "-" if $frame eq "";
	unshift @stack, $frame;
}

foreach my $k (sort { $a cmp $b } keys %collapsed) {
	printf "$k $collapsed{$k}\n";
}
