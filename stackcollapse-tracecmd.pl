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
	# trace-cmd output ex: swift-object-se-18999 [005] 3693413.521874: kernel_stack:         <stack trace>
	# ftrace output    ex:            <...>-503310 [001] .... 800755.732210: <stack trace>
	if (/^\s+(.+)\s\[(\d+)\]\s+.*?(\d+\.\d+)\:(\skernel_stack\:)*\s+\<stack trace\>/) {
		if (defined $pname) {
			summarize_stack_and_cleanup();
		}

		$pname = $1;
		$cpu = $2;
		$tsp = $3;

		if (defined $trace_func_name) {
			unshift @stack, $trace_func_name;
		}
		# print "process name: $pname\n";
		# print "cpu $cpu\n";
		# print "tsp $tsp\n";
		next;
	}

	# trace-cmd output:
	# => xfs_buf_get_map (ffffffffc065ed5c)
	# => xfs_buf_read_map (ffffffffc065f98d)
	# ftrace output:
	# => __alloc_pages_nodemask+0x233/0x320 <ffffffff812871c3>
	# => alloc_pages_current+0x87/0xe0 <ffffffff8129e7a7>
	# => __get_free_pages+0x11/0x40 <ffffffff81281a41>
	# => __tlb_remove_page_size+0x5b/0x90 <ffffffff8127359b>
	# => zap_pte_range.isra.0+0x2a5/0x7d0 <ffffffff81265155>
	# => unmap_page_range+0x2dc/0x4a0 <ffffffff81265d9c>
	# => unmap_single_vma+0x7f/0xf0 <ffffffff81265fdf>
	# => unmap_vmas+0x70/0xe0 <ffffffff812663d0>
	# => exit_mmap+0xb4/0x1b0 <ffffffff81270914>
	# => mmput+0x50/0x120 <ffffffff8109e3c0>
	# => do_exit+0x2f8/0xae0 <ffffffff810a7de8>
	# => do_group_exit+0x43/0xa0 <ffffffff810a8673>
	# => __x64_sys_exit_group+0x18/0x20 <ffffffff810a86e8>
	# => do_syscall_64+0x57/0x190 <ffffffff810045c7>
	# => entry_SYSCALL_64_after_hwframe+0x44/0xa9 <ffffffff81c0008c>
	if (defined $pname) {
		if (/\s*\=\>\s+(.+)\s*([\(\<]([a-f\d]+)[\)\>])*/) {
			$func_name = $1;
			$addr = $2;
			# print "function name: $func_name;\n";
			# print "address: $addr;\n";
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
