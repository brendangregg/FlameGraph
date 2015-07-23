#!/usr/bin/perl -ws
#
# stackcollapse-recursive  Collapse direct recursive backtraces
#
# Post-process a stack list and merge direct recursive calls:
#
# Example input:
#
#     main;recursive;recursive;recursive;helper 1
#
# Output:
#
#     main;recursive;helper 1
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

my %stacks;

while(<>) {
  chomp;
  my ($stack_, $value) = (/^(.*)\s+?(\d+(?:\.\d*)?)$/);
  if ($stack_) {
    my @stack  = split(/;/, $stack_);

    my @result = ();
    my $i;
    my $last="";
    for($i=0; $i!=@stack; ++$i) {
      if(!($stack[$i] eq $last)) {
        $result[@result] = $stack[$i];
        $last = $stack[$i];
      }
    }

    $stacks{join(";", @result)} += $value;
  }
}

foreach my $k (sort { $a cmp $b } keys %stacks) {
  print "$k $stacks{$k}\n";
}
