#!/usr/bin/perl -w
#
# stackcollapse-stap.pl	collapse multiline SystemTap stacks
#				into single lines.
#
# Parses a multiline stack followed by a number on a separate line, and
# outputs a semicolon separated stack followed by a space and the number.
# If memory addresses (+0xd) are present, they are stripped, and resulting
# identical stacks are colased with their counts summed.
#
# USAGE: ./stackcollapse.pl infile > outfile
#
# Example input:
#
#  0xffffffff8103ce3b : native_safe_halt+0xb/0x10 [kernel]
#  0xffffffff8101c6a3 : default_idle+0x53/0x1d0 [kernel]
#  0xffffffff81013236 : cpu_idle+0xd6/0x120 [kernel]
#  0xffffffff815bf03e : rest_init+0x72/0x74 [kernel]
#  0xffffffff81aebbfe : start_kernel+0x3ba/0x3c5 [kernel]
#	2404
#
# Example output:
#
#  start_kernel;rest_init;cpu_idle;default_idle;native_safe_halt 2404
#
# Input may contain many stacks as generated from SystemTap.
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
# 16-Feb-2012	Brendan Gregg	Created this.

use strict;

my %collapsed;

sub remember_stack {
	my ($stack, $count) = @_;
	$collapsed{$stack} += $count;
}

my @stack;

foreach (<>) {
	chomp;

	if (m/^\s*(\d+)+$/) {
		remember_stack(join(";", @stack), $1);
		@stack = ();
		next;
	}

	next if (m/^\s*$/);

	my $frame = $_;
	$frame =~ s/^\s*//;
	$frame =~ s/\+[^+]*$//;
	$frame =~ s/.* : //;
	$frame = "-" if $frame eq "";
	unshift @stack, $frame;
}

foreach my $k (sort { $a cmp $b } keys %collapsed) {
	printf "$k $collapsed{$k}\n";
}
