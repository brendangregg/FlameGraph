#!/usr/bin/perl -w
#
# stackcollapse-go.pl  collapse golang samples into single lines.
#
# Parses golang samples generated by "go tool pprof" and outputs stacks as
# single lines, with methods separated by semicolons, and then a space and an
# occurrence count. For use with flamegraph.pl.
#
# USAGE: ./stackcollapse-go.pl [--sample_index=N] infile > outfile
#
# Example Input:
#   ...
#   Samples:
#   alloc_objects/count alloc_space/bytes inuse_objects/count inuse_space/bytes
#        1   10000000 2 20000000: 1 2 
#        2   20000000 3 30000000: 3 2 
#        1   10000000 1 10000000: 4 2 
#        ...
#   Locations
#        1: 0x58b265 scanblock :0 s=0
#        2: 0x599530 GC :0 s=0
#        3: 0x58a999 flushptrbuf :0 s=0
#        4: 0x58d6a8 runtime.MSpan_Sweep :0 s=0
#        ...
#   Mappings
#        ...
#
# Example Output:
# 
#   GC;flushptrbuf 2
#   GC;runtime.MSpan_Sweep 1
#   GC;scanblock 1
#
# Input may contain many stacks as generated from go tool pprof:
#
#   go tool pprof -seconds=60 -raw -output=a.pprof http://$ADDR/debug/pprof/profile
#
# For format of text profile, See golang/src/internal/pprof/profile/profile.go
#
# Copyright 2017 Sijie Yang (yangsijie@baidu.com).  All rights reserved.
#
#  This program is free software; you can redistribute it and/or
#  modify it under the terms of the GNU General Public License
#  as published by the Free Software Foundation; either version 2
#  of the License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software Foundation,
#  Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
#  (http://www.gnu.org/copyleft/gpl.html)
#
# 16-Jan-2017   Sijie Yang   Created this.

use strict;

use Getopt::Long;

# tunables
my $help = 0;
my $sample_index;  # Default sample index is not set

sub usage {
	die <<USAGE_END;
USAGE: $0 [options]
Options:
  --help	     Show this help message
  --sample_index=N   Use the Nth sample type (required if multiple sample types are present)
USAGE_END
}

GetOptions(
	'help'           => \$help,
	'sample_index=i' => \$sample_index,
) or usage();
$help && usage();

# internals
my $state = "ignore";
my %stacks;
my %frames;
my %collapsed;
my @sample_types;

sub remember_stack {
	my ($stack, $count) = @_;
	$stacks{$stack} += $count;
}

#
# Output stack string in required format. For example, for the following samples,
# format_statck() would return GC;runtime.MSpan_Sweep for stack "4 2"
#
#   Locations
#        1: 0x58b265 scanblock :0 s=0
#        2: 0x599530 GC :0 s=0
#        3: 0x58a999 flushptrbuf :0 s=0
#        4: 0x58d6a8 runtime.MSpan_Sweep :0 s=0
#
sub format_stack {
	my ($stack) = @_;
	my @loc_list = split(/ /, $stack);

	for (my $i=0; $i<=$#loc_list; $i++) {
		my $loc_name = $frames{$loc_list[$i]};
		$loc_list[$i] = $loc_name if ($loc_name);
	}
	return join(";", reverse(@loc_list));
}

while (<>) {
	next if m/^#/;
	chomp;

	if ($state eq "ignore") {
		if (/^Samples:/) {
			# Read the next line to get sample types
			my $sample_line = <>;
			if (defined $sample_line) {
				chomp($sample_line);
				@sample_types = split(/\s+/, $sample_line);

				if (scalar(@sample_types) > 1) {
					# Multiple sample types detected
					if (!defined $sample_index) {
						print STDERR "ERROR: Multiple sample types detected in the profile data.\n\n";
						print STDERR "\tAvailable sample types:\n";
						for (my $i = 0; $i <= $#sample_types; $i++) {
							print STDERR "\t	$i: $sample_types[$i]\n";
						}
						print STDERR "\n";
						print STDERR "\tPlease specify --sample_index=N to select a sample type.\n";
						exit 1;
					} elsif ($sample_index > $#sample_types) {
						print STDERR "ERROR: Invalid sample index $sample_index. Available indices: 0 to $#sample_types\n";
						exit 1;
					}
				} elsif (!defined $sample_index) {
					$sample_index = 0;  # Default to first sample type if only one is present
				}

				$state = "sample";
				next;
			} else {
				print STDERR "Error: No sample data found after 'Samples:' line.\n";
				exit 1;
			}
		}
	} elsif ($state eq "sample") {
		if (/^\s*(.+):\s+(.+)/) {
			my $samples_line = $1;
			my $stack = $2;

			# Split the sample counts
			my @samples = split(/\s+/, $samples_line);

			# Use the specified sample index
			my $samples = $samples[$sample_index];

			# Only consider samples with a positive count
			if ($samples > 0) {
				remember_stack($stack, $samples);
			}

		} elsif (/^Locations/) {
			$state = "location";
			next;
		}
	} elsif ($state eq "location") {
		if (/^\s*([0-9]+): 0x[0-9a-f]+ (M=[0-9]+ )?([^ ]+) .*/) {
			my $loc_id = $1;
			my $loc_name = $3;
			$frames{$loc_id} = $loc_name;
		} elsif (/^Mappings/) {
			$state = "mapping";
			last;
		}
	}
}

foreach my $k (keys %stacks) {
	my $stack = format_stack($k);
	my $count = $stacks{$k};
	$collapsed{$stack} += $count;
}

foreach my $k (sort { $a cmp $b } keys %collapsed) {
	print "$k $collapsed{$k}\n";
}
