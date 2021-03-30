#!/usr/bin/perl -w

use strict;
use Getopt::Long;

my %collapsed;
my @stack;

my $command;
my $cpu;
my $func_addr;
my $func_name;
my $include_pname;
my $no_cpu = 0;
my $no_taskaddr = 0;
my $pid;
my $pname;
my $stack_addr;
my $taskaddr;


GetOptions('no_taskaddr' => \$no_taskaddr,
	   'no_cpu' => \$no_cpu)
or die <<USAGE_END;
USAGE: $0 [options] infile > outfile\n
	--no_taskaddr		# Don't generate taskaddr to eliminate the stacksize
	--no_cpu		# Don't generate the stack based on the CPU number to eliminate the stacksize\n
USAGE_END

sub remember_stack {
	my ($stack, $count) = @_;
	$collapsed{$stack} += $count;
}


sub summarize_stack_and_cleanup {

	if (!$no_taskaddr) {
		unshift @stack, "$pname($pid) task_struct:0x$taskaddr";
	} else {
		unshift @stack, "$pname";
	}

	if (!$no_cpu) {
		unshift @stack, "CPU_$cpu";
	}

	remember_stack(join(";", @stack), 1);

	undef @stack;
	undef $command;
	undef $cpu;
	undef $func_addr;
	undef $func_name;
	undef $pid;
	undef $pname;
	undef $stack_addr;
	undef $taskaddr;
}


#
# Main loop
#
while (defined($_ = <>)) {

	# find the name of the process in the first line of callstack of ftrace.
	# "bt -a" output ex: 'PID: 2045758  TASK: ffff9b70103e0000  CPU: 0   COMMAND: "ms_pipe_read"'
	if (/^\s*PID\:\s+(\d+)\s+TASK\:\s+([a-f\d]+)\s+CPU\:\s+(\d+)\s+COMMAND\:\s+\"(.+)\"/) {
		if (defined $pname) {
			# The sample count flamegraph needs to summarize stack here
			summarize_stack_and_cleanup();
		}
		$pid = $1;
		$taskaddr = $2;
		$cpu = $3;
		$pname = $4;
		# print "pid: $pid, taskaddr: $taskaddr, cpu: $cpu, command: $pname\n";

		next;
	}

	# "bt -a" output:
	# PID: 0      TASK: ffff9b769861da00  CPU: 1   COMMAND: "swapper/1"
	#  #0 [fffffe0000034e40] crash_nmi_callback at ffffffff85059c07
	#  #1 [fffffe0000034e50] nmi_handle at ffffffff850322d0
	#  #2 [fffffe0000034ea8] default_do_nmi at ffffffff85032784
	#  #3 [fffffe0000034ec8] do_nmi at ffffffff85032992
	#  #4 [fffffe0000034ef0] end_repeat_nmi at ffffffff85a01a62
	#     [exception RIP: mwait_idle+0x77]
	#     RIP: ffffffff859c7557  RSP: ffffbf214c90be88  RFLAGS: 00000246
	#     RAX: 0000000000000000  RBX: 0000000000000001  RCX: 0000000000000000
	#     RDX: 0000000000000000  RSI: 0000000000000000  RDI: 0000000000000000
	#     RBP: ffffbf214c90be98   R8: 0000000000000000   R9: 0000000000000002
	#     R10: ffffbf214c90be18  R11: 000000000000406c  R12: 0000000000000001
	#     R13: ffff9b769861da00  R14: 0000000000000000  R15: 0000000000000000
	#     ORIG_RAX: ffffffffffffffff  CS: 0010  SS: 0018
	# --- <NMI exception stack> ---
	#  #5 [ffffbf214c90be88] mwait_idle at ffffffff859c7557
	#  #6 [ffffbf214c90bea0] arch_cpu_idle at ffffffff85039e15
	#  #7 [ffffbf214c90beb0] default_idle_call at ffffffff859c78f3
	#  #8 [ffffbf214c90bec0] do_idle at ffffffff850d9bda
	#  #9 [ffffbf214c90bf00] cpu_startup_entry at ffffffff850d9e43
	# #10 [ffffbf214c90bf28] start_secondary at ffffffff8505b08b
	# #11 [ffffbf214c90bf50] secondary_startup_64 at ffffffff850000d5
	# >8-----------------------8<
	# PID: 253681  TASK: ffff9b8a66a2bc00  CPU: 24  COMMAND: "jujud"
	#  #0 [ffffbf216c013500] __schedule at ffffffff859c21a6
	#  #1 [ffffbf216c0135a0] schedule at ffffffff859c26b6
	#  #2 [ffffbf216c0135b8] schedule_timeout at ffffffff859c67db
	#  #3 [ffffbf216c013638] wait_for_completion at ffffffff859c3284
	#  #4 [ffffbf216c013698] xfs_buf_submit_wait at ffffffffc0d197bf [xfs]
	#  #5 [ffffbf216c0136c0] xfs_bwrite at ffffffffc0d19cb4 [xfs]
	#  #6 [ffffbf216c0136e0] xfs_reclaim_inode at ffffffffc0d23f43 [xfs]
	#  #7 [ffffbf216c013730] xfs_reclaim_inodes_ag at ffffffffc0d2419c [xfs]
	#  #8 [ffffbf216c0138c0] xfs_reclaim_inodes_nr at ffffffffc0d25383 [xfs]
	#  #9 [ffffbf216c0138e0] xfs_fs_free_cached_objects at ffffffffc0d38699 [xfs]
	# #10 [ffffbf216c0138f0] super_cache_scan at ffffffff8528818a
	# #11 [ffffbf216c013948] shrink_slab at ffffffff851f21bb
	# #12 [ffffbf216c013a18] shrink_slab at ffffffff851f2459
	# #13 [ffffbf216c013a28] shrink_node at ffffffff851f7458
	# #14 [ffffbf216c013ab0] do_try_to_free_pages at ffffffff851f774e
	# #15 [ffffbf216c013b18] try_to_free_pages at ffffffff851f7ab1
	# #16 [ffffbf216c013ba0] __alloc_pages_slowpath at ffffffff851e5099
	# #17 [ffffbf216c013cb8] __alloc_pages_nodemask at ffffffff851e5e19
	# #18 [ffffbf216c013d20] alloc_pages_vma at ffffffff85248152
	# #19 [ffffbf216c013d68] do_huge_pmd_anonymous_page at ffffffff8525fcc7
	# #20 [ffffbf216c013dc0] __handle_mm_fault at ffffffff8521c0a7
	# #21 [ffffbf216c013e78] handle_mm_fault at ffffffff8521c88c
	# #22 [ffffbf216c013ea8] __do_page_fault at ffffffff850783b1
	# #23 [ffffbf216c013f20] do_page_fault at ffffffff8507861e
	# #24 [ffffbf216c013f50] page_fault at ffffffff85a01635
	if (defined $pname) {
		if (/\s*\#\d+\s+\[([a-f\d]+)\]\s+(\w+)\s+at\s+([a-f\d]+)\s*(\[\w+\])*$/) {
			$stack_addr = $1;
			$func_name = $2;
			$func_addr = $3;
			if (defined $4) {
				unshift @stack, "$func_name $4 <0x$func_addr>";
			} else {
				unshift @stack, "$func_name <0x$func_addr>";
			}
			# print "stack_addr: $stack_addr, func_name: $func_name, func_addr: $func_addr\n";
		} elsif (/\s*\-\-\-\s+\<NMI\s+exception\s+stack\>\s+\-\-\-/) {

			# print $_;
			$func_name = "<NMI stack ↑>";
			unshift @stack, $func_name;
			# print "func_name: $func_name\n";
		# Parse to any other weird lines which is not the stack trace
		# or the kernel_stack line.
		} else {
			next;
		}
	}
}

foreach my $k (sort { $a cmp $b } keys %collapsed) {
	print "$k $collapsed{$k}\n";
}
