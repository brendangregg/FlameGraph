#!/usr/bin/perl -ws
#
# stackcollapse-gdb  Collapse GDB backtraces
#
# Parse a list of GDB backtraces as generated with the poor man's
# profiler [1]:
#
#   for x in $(seq 1 500); do
#      gdb -ex "set pagination 0" -ex "thread apply all bt" -batch -p $pid 2> /dev/null
#      sleep 0.01
#    done
#
# [1] http://poormansprofiler.org/
#
# Copyright 2014 Gabriel Corona. All rights reserved.
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
my $previous_function = "";

my %stacks;

while(<>) {
  chomp;
  if (m/^Thread/) {
    $current=""
  }
  elsif(m/^#[0-9]* *([^ ]*) ([^ ]*) ([^ ]*) ([^ ]*)/) {
    my $function = $3;
    my $alt = $1;
    if(not($1 =~ /0x[a-zA-Z0-9]*/)) {
      $function = $alt;
    }
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
