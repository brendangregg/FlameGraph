#!/usr/bin/perl -w

use strict;
use Getopt::Long;

my %collapsed;
my @stack;

my $addr;
my $cpu;
my $func_name;
my $include_pname;
my $m_pid;
my $pname;
my $trace_func_name;
my $tsp;


GetOptions('process_name' => \$include_pname,
	   'trace_func_name=s' => \$trace_func_name)
or die <<USAGE_END;
USAGE: $0 [options] infile > outfile\n
	--process_name		# include process names to isolate callstack
	--trace_func_name=FUNT	# Traced function name\n
USAGE_END


sub remember_stack {
	my ($stack, $count) = @_;
	$collapsed{$stack} += $count;
}


sub summarize_stack_and_cleanup {
	if ($include_pname) {
		unshift @stack, $pname;
	}
	remember_stack(join(";", @stack), 1);
	undef $pname;
	undef @stack;
}


#
# Main loop
#
while (defined($_ = <>)) {

	# find the name of the process in the first line of callstack of ftrace.
	# ex: swift-object-se-18999 [005] 3693413.521874: kernel_stack:         <stack trace>
	if (/^\s+(.+)\s\[(\d+)\]\s+(\d+\.\d+)\:\skernel_stack\:\s+\<stack trace\>/) {
		if (defined $pname) {
			summarize_stack_and_cleanup();
		}

		$pname = $1;
		$cpu = $2;
		$tsp = $3;

		if (defined $trace_func_name) {
			unshift @stack, $trace_func_name;
		}
		#print "process name: $pname\n";
		#print "pid $m_pid\n";
		#print "tsp $tsp\n";
		next;
	}

	# => xfs_buf_get_map (ffffffffc065ed5c)
	# => xfs_buf_read_map (ffffffffc065f98d)
	# if (0) {
	if (defined $pname) {
		if (/\s*\=\>\s+(.+)\s+\(([a-f\d]+)\)/) {
			$func_name = $1;
			$addr = $2;
			#print "function name: $func_name; ";
			#print "address: $addr; ";
			unshift @stack, $func_name;

		# Parse to any other weird lines which is not the stack trace
		# or the kernel_stack line.
		} else {
			summarize_stack_and_cleanup();
		}
	}
}

foreach my $k (sort { $a cmp $b } keys %collapsed) {
	print "$k $collapsed{$k}\n";
}
