#!/usr/bin/perl -w
#
# stackcollapse-pageowner.pl	collapse multiline stacks into single lines.
#
# This is one of several stackcollapse versions available for FlameGraph.
#   (ref https://github.com/brendangregg/FlameGraph )
#
# This particular version parses frameowner-style pages, which are produced by:
#    https://www.kernel.org/doc/html/latest/vm/page_owner.html
#       TL;DR:  add  “page_owner=on” to boot cmdline,
#               run the operation to profile,
#               use the contents of /sys/kernel/debug/page_owner
#                    as input to this script
#
# The script Parses a multiline stack followed by a number on a separate line,
# and outputs a semicolon separated stack followed by a space and the number.
# If memory addresses (+0xd) are present, they are stripped, and resulting
# identical stacks are colased with their counts summed.
#
# USAGE: ./stackcollapse-pageowner.pl infile > outfile
#
# Example input:
#####
#    Page allocated via order 0, mask 0x0(), pid 1, ts 460209702 ns, free_ts 0 ns
#    PFN 16 type Unmovable Block 0 type Unmovable Flags 0x0()
#     register_early_stack+0x2d/0x5e
#     init_page_owner+0x2a/0x2a7
#     kernel_init_freeable+0xed/0x14d
#     kernel_init+0x5/0x100
#
# Example output:
#####
#    kernel_init;kernel_init_freeable;init_page_owner;register_early_stack 1
#
# Input may contain many stacks.
#
#
# Based on the original stackcollapse.pl, whose license is below
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
# Created by Alex Gimenez Oct/21/2021 ,
# In connection with The Chromium OS Authors

use strict;

my $includeoffset = 0;		# include function offset (except leafs)
my %collapsed;

use constant {
    NEEDHEADER1   => 0,
    NEEDHEADER2   => 1,
    FRAMES => 2,
};

#
my $parsestate = NEEDHEADER1;

sub remember_stack {
  my ($stack, $count) = @_;
  $collapsed{$stack} += $count;
}

my @stack;
my $count=0;


foreach my $line(<STDIN>) {
  chomp( $line );

  if ($parsestate == NEEDHEADER1) {
    if ($line =~ m/^Page allocated via order ([0-9]+),/) {
      my $order = $1;
      $count = 1 << $order;
      $parsestate = NEEDHEADER2;
    } else {
      die "ERROR: expected Page header [$line]\n";
    }
  } elsif ($parsestate == NEEDHEADER2) {
    if ($line =~ m/^PFN .* type.*$/) {
      $parsestate = FRAMES;
    } else {
      die "ERROR: expected PFN header [$line]\n";
    }
  } elsif($parsestate == FRAMES) {
    if($line =~ m/^\s*$/) {
      # empty line, frames are finished, file stack
      my $joined = join(";", @stack);

      # trim leaf offset if these were retained:
      $joined =~ s/\+[^+]*$// if $includeoffset;

      remember_stack($joined, $count);
      @stack = ();
      $parsestate = NEEDHEADER1;
    } elsif ($line =~ m/^Page has been*/) {
      # ignore status line
    } else {
      # process one frame
      my $frame = $line;
      $frame =~ s/^\s*//;
      $frame =~ s/\+[^+]*$// unless $includeoffset;

      # Remove arguments from C++ function names:
      $frame =~ s/(::.*)[(<].*/$1/;

      $frame = "-" if $frame eq "";

      my @inline;
      for (split /\->/, $frame) {
        my $func = $_;
        # Strip out L and ; included in java stacks
        $func =~ tr/\;/:/;
        $func =~ s/^L//;
        $func .= "_[i]" if scalar(@inline) > 0; #inlined

        push @inline, $func;
      }

      unshift @stack, @inline;
    }
  } else {
    # this is a bug -  better never happen
    die "ERROR: unexpected state [$parsestate]\n";
  }

} # end of foreach

foreach my $k (sort { $a cmp $b } keys %collapsed) {
  print "$k $collapsed{$k}\n";
}
