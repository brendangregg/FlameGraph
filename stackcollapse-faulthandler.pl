#!/usr/bin/perl -ws
#
# stackcollapse-faulthandler  Collapse Python faulthandler backtraces
#
# Parse a list of Python faulthandler backtraces as generated with
# faulthandler.dump_traceback_later.
#
# Copyright 2014 Gabriel Corona. All rights reserved.
# Copyright 2017 Jonathan Kolb. All rights reserved.
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

use strict;

my $current = "";

my %stacks;

while(<>) {
  chomp;
  if (m/^Thread/) {
    $current=""
  }
  elsif(m/^  File "([^"]*)", line ([0-9]*) in (.*)/) {
    my $function = $1 . ":" . $2 . ":" . $3;
    if ($current eq "") {
      $current = $function;
    } else {
      $current = $function . ";" . $current;
    }
  } elsif(!($current eq "")) {
    $stacks{$current} += 1;
    $current = "";
  }
}

if(!($current eq "")) {
  $stacks{$current} += 1;
  $current = "";
}

foreach my $k (sort { $a cmp $b } keys %stacks) {
  print "$k $stacks{$k}\n";
}
