#!/usr/bin/perl -w
#
# stackcollapse-elfutils  Collapse elfutils stack (eu-stack) backtraces
#
# Parse a list of elfutils backtraces as generated with the poor man's
# profiler [1]:
#
#   for x in $(seq 1 "$nsamples"); do
#      eu-stack -p "$pid" "$@"
#      sleep "$sleeptime"
#   done
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
use Getopt::Long;

my $with_pid = 0;
my $with_tid = 0;

GetOptions('pid' => \$with_pid,
           'tid' => \$with_tid)
or die <<USAGE_END;
USAGE: $0 [options] infile > outfile\n
        --pid           # include PID
        --tid           # include TID
USAGE_END

my $pid = "";
my $tid = "";
my $current = "";
my $previous_function = "";

my %stacks;

sub add_current {
  if(!($current eq "")) {
    my $entry;
    if ($with_tid) {
      $current = "TID=$tid;$current";
    }
    if ($with_pid) {
      $current = "PID=$pid;$current";
    }
    $stacks{$current} += 1;
    $current = "";
  }
}

while(<>) {
  chomp;
  if (m/^PID ([0-9]*)/) {
    add_current();
    $pid = $1;
  }
  elsif(m/^TID ([0-9]*)/) {
    add_current();
    $tid = $1;
  } elsif(m/^#[0-9]* *0x[0-9a-f]* (.*)/) {
    if ($current eq "") {
      $current = $1;
    } else {
      $current = "$1;$current";
    }
  } elsif(m/^#[0-9]* *0x[0-9a-f]*/) {
    if ($current eq "") {
      $current = "[unknown]";
    } else {
      $current = "[unknown];$current";
    }
  }
}
add_current();

foreach my $k (sort { $a cmp $b } keys %stacks) {
  print "$k $stacks{$k}\n";
}
