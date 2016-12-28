#!/usr/bin/perl -ws
#
# stackcollapse-aix  Collapse AIX /usr/bin/procstack backtraces
#
# Parse a list of backtraces as generated with the poor man's aix-perf.pl
# profiler 
#

use strict;

my $process = "";
my $current = "";
my $previous_function = "";

my %stacks;

while(<>) {
  chomp;
  if (m/^\d+:/) {
    if(!($current eq "")) {
      $current = $process . ";" . $current;
      $stacks{$current} += 1;
      $current = "";
    }
    m/^\d+: ([^ ]*)/;
    $process = $1;
    $current = "";
  }
  elsif(m/^---------- tid# \d+/){
    if(!($current eq "")) {
      $current = $process . ";" . $current;
      $stacks{$current} += 1;
    }
    $current = "";
  }
  elsif(m/^(0x[0-9abcdef]*) *([^ ]*) ([^ ]*) ([^ ]*)/) {
    my $function = $2;
    my $alt = $1;
    $function=~s/\(.*\)?//;
    if($function =~ /^\[.*\]$/) {
      $function = $alt;
    }
    if ($current) {
      $current = $function . ";" . $current;
    }
    else {
      $current = $function;
    }
  }
}

if(!($current eq "")) {
  $current = $process . ";" . $current;
  $stacks{$current} += 1;
  $current = "";
  $process = "";
}

foreach my $k (sort { $a cmp $b } keys %stacks) {
  print "$k $stacks{$k}\n";
}
