#!/usr/bin/perl -w

use strict;
use Getopt::Long;

my %collapsed;
my @stack;

my $addr;
my $cpu;
my $func_name;
my $gfp_flags;
my $include_page_order;
my $include_page_type;
my $include_pname;
my $migrate_type;
my $mtype;
my $m_pid;
my $page_alloc_event_cpu;
my $pname;
my $order;
my $trace_func_name;
my $tsp;


GetOptions('page_order' => \$include_page_order,
	   'page_type' => \$include_page_type,
	   'process_name' => \$include_pname,
	   'trace_func_name=s' => \$trace_func_name)
or die <<USAGE_END;
USAGE: $0 [options] infile > outfile\n
	--page_order		# generate the flamegraph based on the page order
	--page_type		# include the migrate_type and gfp_flgs in the stack
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

	if($include_page_type) {

		if(!defined($migrate_type)) {
			return;
		}

		if($migrate_type == 0) {
			$mtype="MIGRATE_UNMOVABLE";
		} elsif($migrate_type == 1) {
			$mtype="MIGRATE_MOVABLE";
		} elsif($migrate_type == 2) {
			$mtype="MIGRATE_RECLAIMABLE";
		} elsif($migrate_type == 3) {
			$mtype="MIGRATE_HIGHATOMIC";
		} elsif($migrate_type == 4) {
			$mtype="MIGRATE_CMA";
		} elsif($migrate_type == 5) {
			$mtype="MIGRATE_ISOLATE";
		}

		unshift @stack, "$mtype, $gfp_flags";
	}

	if($include_page_order) {
		if(!defined($order)) {
			return;
		}
		unshift @stack, "order $order";
		remember_stack(join(";", @stack), 2**$order * 4);
	} else {
		remember_stack(join(";", @stack), 1);
	}
	undef $pname;
	undef @stack;
	undef $cpu;
	undef $tsp;
	undef $page_alloc_event_cpu;
	undef $order;
	undef $migrate_type;
	undef $gfp_flags;
}


#
# Main loop
#
while (defined($_ = <>)) {

	# Ftrace raw output
	# 1287587.105144 |   1)               |  /* mm_page_alloc: page=0000000082b1fe73 pfn=1704824 order=0 migratetype=1 gfp_flags=GFP_HIGHUSER_MOVABLE|__GFP_ZERO */
	if ($include_page_order || $include_page_type) {
		# ftrace raw output
		if (/^\s+(\d+\.\d+)\s+|\s+(\d+)\).+mm_page_alloc.+order=(\d+)\s+migratetype=(\d+)\s+gfp_flags=(.+)\*/) {
			if (defined $pname) {
				summarize_stack_and_cleanup();
			}
			$page_alloc_event_cpu = $2;
			$order = $3;
			$migrate_type = $4;
			$gfp_flags = $5;
			next;
		}
		# trace-cmd output
		# sudo trace-cmd record -l __alloc_pages_nodemask -e kmem:mm_page_alloc  -T sleep 1
		# <...>-187168 [003] 14540.343835: mm_page_alloc:        page=0x3070e0 pfn=3174624 order=1 migratetype=0 gfp_flags=GFP_KERNEL_ACCOUNT|__GFP_ZERO
		if (/^\s+(.+)\[(\d+)\]\s+\d+\.\d+.+mm_page_alloc.+order=(\d+)\s+migratetype=(\d+)\s+gfp_flags=(.+)(\*)*/) {
			if (defined $pname) {
				summarize_stack_and_cleanup();
			}

			$page_alloc_event_cpu = $2;
			$order = $3;
			$migrate_type = $4;
			$gfp_flags = $5;
			next;
		}
	}

	# find the name of the process in the first line of callstack of ftrace.
	# trace-cmd output ex: swift-object-se-18999 [005] 3693413.521874: kernel_stack:         <stack trace>
	# ftrace output    ex:            <...>-503310 [001] .... 800755.732210: <stack trace>
	if (/^\s+(.+)\s+\[(\d+)\]\s+.*?(\d+\.\d+)\:(\skernel_stack\:)*\s+\<stack trace\>/) {
		if (defined $pname && !($include_page_order || $include_page_type)) {
			# The sample count flamegraph needs to summarize stack here
			summarize_stack_and_cleanup();
		}
		$pname = $1;
		$cpu = $2;
		$tsp = $3;

		if (defined $trace_func_name) {
			unshift @stack, $trace_func_name;
		}
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
			unshift @stack, $func_name;

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
