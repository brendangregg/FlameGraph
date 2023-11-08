#!/usr/bin/perl -w
#
# stackcollapse-instruments.pl
#
# Parses a file containing a call tree as produced by Xcode Instruments
# (Edit > Deep Copy) and produces output suitable for flamegraph.pl.
#
# USAGE: ./stackcollapse-instruments.pl [--inverted] infile > outfile
#
# --inverted option:
#  In inverted mode, stackcollapse-instruments will parse infile in a
#  suitable way for Instruments output obtained with the "Invert Call
#  Tree" checkbox set (where "Self Weight" is not as reliable).
#
# Example input; note the amount of spaces before the symbol:
#
# 2.79 s  100.0%	0 s	 	execname (1090)
# 2.66 s   95.4%	0 s	 	 completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*)
# 2.54 s   91.0%	595.00 ms	 	  thunk for @escaping @callee_guaranteed @Sendable @async () -> (@out A)specialized partial apply
# 639.00 ms   22.9%	20.00 ms	 	   _swift_release_dealloc
# 191.00 ms    6.8%	0 s	 	    nanov2_free_to_block
# 191.00 ms    6.8%	191.00 ms	 	     nanov2_free_to_block
# 158.00 ms    5.6%	0 s	 	    nanov2_pointer_size
# 158.00 ms    5.6%	158.00 ms	 	     nanov2_pointer_size
# 124.00 ms    4.4%	0 s	 	    swift_release
# 119.00 ms    4.2%	119.00 ms	 	     swift_release
#
# Example output:
# 
# execname (1090) 0
# execname (1090);completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*) 0
# execname (1090);completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*);thunk for @escaping @callee_guaranteed @Sendable @async () -> (@out A)specialized partial apply 595
# execname (1090);completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*);thunk for @escaping @callee_guaranteed @Sendable @async () -> (@out A)specialized partial apply;_swift_release_dealloc 20
# execname (1090);completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*);thunk for @escaping @callee_guaranteed @Sendable @async () -> (@out A)specialized partial apply;_swift_release_dealloc;nanov2_free_to_block 0
# execname (1090);completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*);thunk for @escaping @callee_guaranteed @Sendable @async () -> (@out A)specialized partial apply;_swift_release_dealloc;nanov2_free_to_block;nanov2_free_to_block 191
# execname (1090);completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*);thunk for @escaping @callee_guaranteed @Sendable @async () -> (@out A)specialized partial apply;_swift_release_dealloc;nanov2_pointer_size 0
# execname (1090);completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*);thunk for @escaping @callee_guaranteed @Sendable @async () -> (@out A)specialized partial apply;_swift_release_dealloc;nanov2_pointer_size;nanov2_pointer_size 158
# execname (1090);completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*);thunk for @escaping @callee_guaranteed @Sendable @async () -> (@out A)specialized partial apply;_swift_release_dealloc;swift_release 0
# execname (1090);completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*);thunk for @escaping @callee_guaranteed @Sendable @async () -> (@out A)specialized partial apply;_swift_release_dealloc;swift_release;swift_release 119
#
#
# Example input (inverted option set):
#
# 2.79 s  100.0%	0 s	 	execname (1090)
# 290.00 ms   10.4%	290.00 ms	 	 swift_retain
# 282.00 ms   10.1%	0 s	 	  swift_retain
# 251.00 ms    9.0%	0 s	 	   commonPseudoReasync #1 (_:_:isReverse:_:) in iteratePossibleLeftNodesPseudoReasync(_:_:_:_:_:_:_:_:)
# 251.00 ms    9.0%	0 s	 	    completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*)
# 15.00 ms    0.5%	0 s	 	   iteratePossibleLeftNodesPseudoReasync(_:_:_:_:_:_:_:_:)
# 15.00 ms    0.5%	0 s	 	    completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*)
# 11.00 ms    0.3%	0 s	 	   specialized _ArrayBuffer.beginCOWMutation()
# 11.00 ms    0.3%	0 s	 	    completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*)
#
# Example output (inverted option set):
#
# execname (1090);swift_retain;swift_retain;commonPseudoReasync #1 (_:_:isReverse:_:) in iteratePossibleLeftNodesPseudoReasync(_:_:_:_:_:_:_:_:);completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*) 251
# execname (1090);swift_retain;swift_retain;commonPseudoReasync #1 (_:_:isReverse:_:) in iteratePossibleLeftNodesPseudoReasync(_:_:_:_:_:_:_:_:) 0
# execname (1090);swift_retain;swift_retain;iteratePossibleLeftNodesPseudoReasync(_:_:_:_:_:_:_:_:);completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*) 15
# execname (1090);swift_retain;swift_retain;iteratePossibleLeftNodesPseudoReasync(_:_:_:_:_:_:_:_:) 0
# execname (1090);swift_retain;swift_retain;specialized _ArrayBuffer.beginCOWMutation();completeTaskWithClosure(swift::AsyncContext*, swift::SwiftError*) 11
# execname (1090);swift_retain;swift_retain;specialized _ArrayBuffer.beginCOWMutation() 0
# execname (1090);swift_retain;swift_retain 0
# execname (1090);swift_retain 0
# execname (1090) 0
#

use strict;
use Getopt::Long;

# tunables
my $inverted = 0; # assume input is inverted call trees (self weights are 0 beyond depth 1)
my $help = 0;

sub usage {
	die <<USAGE_END;
USAGE: $0 [options] infile > outfile\n
	--inverted : assume inverted call trees infile

USAGE_END
}

GetOptions(
	'inverted!'   => \$inverted,
	'help'        => \$help,
) or usage();
$help && usage();


sub regular {
	my @stack = ();

	foreach (<>) {
		chomp;
		/\d+\.\d+ (?:min|s|ms)\s+\d+\.\d+%\s+(\d+(?:\.\d+)?) (min|s|ms)\t \t(\s*)(.+)/ or die;
		my $func = $4;
		my $depth = length ($3);
		$stack [$depth] = $4;
		foreach my $i (0 .. $depth - 1) {
			print $stack [$i];
			print ";";
		}
		
		my $time = 0 + $1;
		if ($2 eq "min") {
			$time *= 60*1000;
		} elsif ($2 eq "s") {
			$time *= 1000;
		}
		
		printf("%s %.0f\n", $func, $time);
	}
}

sub inverted {
	my @symbolstack = ();
	my @timestack = ();
	my $prevdepth = -1;

	LINE: foreach (<>) {
		chomp;
		# Use first two columns ("Weight"), as "Self Weight" columns are always "0 s" beyond depth 1...
		/(\d+\.\d+) (min|s|ms)\s+\d+\.\d+%\s+(?:\d+(?:\.\d+)?) (?:min|s|ms)\t \t(\s*)(.+)/ or last LINE;
		my $func = $4;
		my $depth = length ($3);

		my $time = 0 + $1;
		if ($2 eq "min") {
			$time *= 60*1000;
		} elsif ($2 eq "s") {
			$time *= 1000;
		}

		if ($depth <= $prevdepth) { # previous entry was *not* our parent
			# So print the stack entries above us, which are now definitive
			foreach my $prei ($depth .. $prevdepth) {
				# Do so from the deepest to decreasing levels of depth
				my $i = $depth + ( $prevdepth - $prei );
				foreach my $j (0 .. $i - 1) {
					print $symbolstack [$j];
					print ";";
				}
				# Avoid negative amounts potentially resulting from roundoff
				my $actualtime = ($timestack [$i] > 0 ? $timestack [$i] : 0);
				printf("%s %.0f\n", $symbolstack [$i], $actualtime);
			}
		}

		# Record our own weight, subject to correction by our children, if any
		$symbolstack [$depth] = $4;
		$timestack [$depth] = $time;
		if ($depth != 0) {
			# And correct our own parent, if any
			$timestack [$depth - 1] -= $time;
		}

		$prevdepth = $depth;
	}

	if ($prevdepth != -1) {
		# last entry was *not* anyone's parent
		# So print all remaining entries in the stack, which are now definitive
		foreach my $prei (0 .. $prevdepth) {
			# Do so from the deepest to decreasing levels of depth
			my $i = $prevdepth - $prei;
			foreach my $j (0 .. $i - 1) {
				print $symbolstack [$j];
				print ";";
			}
			# Avoid negative amounts potentially resulting from roundoff
			my $actualtime = ($timestack [$i] > 0 ? $timestack [$i] : 0);
			printf("%s %.0f\n", $symbolstack [$i], $actualtime);
		}
	}
}

<>;

if ($inverted == 0) {
	regular();
} else {
	inverted();
}
