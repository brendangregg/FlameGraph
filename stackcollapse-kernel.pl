#!/usr/bin/perl -w

use strict;
use Getopt::Long;

my %collapsed;
my @stack;

my $addr_offset;
my $blockseconds;
my $comm;
my $cpu;
my $date;
my $dtype; # dumpstack type
my $func_name;
my $gfp_flags;
my $hostname;
my $include_all_calltrace;
my $include_block_seconds;
my $include_no_offset;
my $include_no_page_order;
my $include_no_page_type;
my $include_no_pname;
my $kernelversion;
my $lines_skip_before_next_stack = 0;
my $nr_line = 0;
my $pid;
my $pname;
my $oom_score_adj;
my $order;
my $tsp;


GetOptions('all_calltrace' => \$include_all_calltrace,
	   'block_seconds' => \$include_block_seconds,
	   'no_offset' => \$include_no_offset,
	   'no_page_order' => \$include_no_page_order,
	   'no_page_type' => \$include_no_page_type,
	   'no_process_name' => \$include_no_pname)
or die <<USAGE_END;
USAGE: $0 [options] infile > outfile\n
	--all_calltrace		# Show all the call trace even there is no OOM/hungtask/soft lockup error.
	--no_offset		# Exclude the address offset from the symbol name.
				# The stack merge will be better and simplied.
				# However, by looking at the Flamegraph, it's
				# not useful when addr2line is needed to
				# identify the exact code piece.

OOM Call Trace Options:
	--no_page_order		# Don't generate the flamegraph based on the page order
	--no_page_type		# Don't include the gfp_flgs in the stack
	--process_name		# include process names to isolate callstack

HungTask/Soft Lockup options:
	--block_seconds		# Shows the blocked seconds with the process
				# name. By default, the block seconds is not
				# showed in the dump stack to facilitate the
				# stack merge.\n
USAGE_END


sub remember_stack {
	my ($stack, $count) = @_;
	$collapsed{$stack} += $count;
}

sub undefine_variables {
	undef $addr_offset;
	undef $comm;
	undef $cpu;
	undef $date;
	undef $dtype;
	undef $func_name;
	undef $gfp_flags;
	undef $hostname;
	undef $kernelversion;
	undef $oom_score_adj;
	undef $order;
	undef $pid;
	undef $pname;
	undef @stack;
	undef $tsp;
}

sub summarize_stack_and_cleanup {

	if (!$dtype) {
		if ($pname && $pid) {
			if ($include_block_seconds) {
				unshift @stack, "$pname($pid) stuck for ${blockseconds}s ";
			} else {
				unshift @stack, "$pname($pid)";
			}
		}
		unshift @stack, "CPU#$cpu" if $cpu;
		goto out;
	}

	# For OOM, the CPU# is not added to the stack. It's not useful in the
	# OOM debugging.
	if ($dtype eq "oom") {
		if (!$include_no_pname && defined($pname)) {
			unshift @stack, $pname;
		}

		if (!$include_no_page_type) {
			if (defined($gfp_flags)) {
				unshift @stack, "$gfp_flags";
			}

		}

		if (!$include_no_page_order) {
			if (defined($order)) {
				unshift @stack, "order $order";
			}
		}
		unshift @stack, "OOM Call Trace";

		goto out;
	}

	if ($dtype eq "hungtask") {
		if (!$include_no_pname && defined($pname)) {
			if ($include_block_seconds) {
				unshift @stack, "$pname($pid) blocks for $blockseconds seconds";
			} else {
				unshift @stack, "$pname($pid)";
			}
		}

		unshift @stack, "Hung Task Call Trace";
		goto out;
	}

	if ($dtype eq "softlockup") {
		if (!$include_no_pname && defined($pname)) {
			if ($include_block_seconds) {
				unshift @stack, "$pname($pid) stuck for ${blockseconds}s ";
			} else {
				unshift @stack, "$pname($pid)";
			}
		}
		unshift @stack, "CPU#$cpu";
		unshift @stack, "Softlockup Call Trace";
		goto out;
	}

out:
	if ($kernelversion) {
		unshift @stack, $kernelversion;
	}
	# unshift @stack, $nr_line;
	remember_stack(join(";", @stack), 1);
	undefine_variables();
}


#
# Main loop
#
while (defined($_ = <>)) {

	$nr_line = $.;
	# 1). oom-killer message parsing. (mm/oom_kill.c:dump_header())
	# Mar 22 12:05:46 coolmarket-node4 kernel: [ 6230.958810] cloudflared invoked oom-killer: gfp_mask=0x100cca(GFP_HIGHUSER_MOVABLE), order=0, oom_score_adj=0
	# Mar 22 12:48:29 coolmarket-node4 kernel: [ 8794.500480] php-fpm7.4 invoked oom-killer: gfp_mask=0x100cca(GFP_HIGHUSER_MOVABLE), order=0, oom_score_adj=0
	# Mar 22 13:10:25 coolmarket-node4 kernel: [10103.572487] php-fpm7.4 invoked oom-killer: gfp_mask=0x100dca(GFP_HIGHUSER_MOVABLE|__GFP_ZERO), order=0, oom_score_adj=0
	if (/(\w+\s+\d+\s+\d+\:\d+\:\d+)\s+(.+)\s+kernel\:\s+\[\s*(\d+\.\d+)\]\s+(.+)\s+invoked\s+oom\-killer\:\s+gfp_mask=(0x[a-f0-9]+\(.+\)),\s+order=(\d+),\s+oom_score_adj=(\d+)/) {
			$date = $1;
			$hostname = $2;
			$tsp = $3;
			$pname = $4;
			$gfp_flags = $5;
			$order = $6;
			$oom_score_adj = $4;
			$dtype = "oom";
			# print "$date $hostname $tsp $pname $gfp_flags $order $oom_score_adj\n";
			next; # ready to parse the dump_stack call trace
	}

	# 2). Hung task message parsing
	#
	# Mar 22 13:21:10 coolmarket-node4 kernel: [10755.701996] INFO: task php-fpm7.4:2823 blocked for more than 241 seconds.
	# Mar 22 13:21:10 coolmarket-node4 kernel: [10755.703063]       Not tainted 5.4.0-67-generic #75-Ubuntu
	# Mar 22 13:21:10 coolmarket-node4 kernel: [10755.703891] "echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.
	# Mar 22 13:21:10 coolmarket-node4 kernel: [10755.704700] php-fpm7.4      D    0  2823   1375 0x00000000
	# Mar 22 13:21:10 coolmarket-node4 kernel: [10755.704703] Call Trace:
	# Mar 22 13:21:10 coolmarket-node4 kernel: [10755.704712]  __schedule+0x2e3/0x740
	#
	# Tainted example:
	# <3>Aug 12 19:38:23 whp1r27c015 kernel: [ 1443.094547] INFO: task macompatsvc:8498 blocked for more than 120 seconds.
	# <3>Aug 12 19:38:23 whp1r27c015 kernel: [ 1443.094548]       Tainted: G        W  OX 3.13.0-156-generic #206-Ubuntu
	if (/task\s+(.+)\:(\d+)\s+blocked\s+for\s+more\s+than\s+(\d+)\s+seconds/) {
		$pname = $1;
		$pid = $2;
		$blockseconds = $3;
		$dtype = "hungtask";
		# print "$pname($pid) block $blockseconds seconds!\n";
	}

	# Parse the kernel veresion for the hungtask
	# Hungtask doesn't report the CPU number line as the task isn't running
	# in any core.
	if ($dtype && $dtype eq "hungtask") {
		if (/ainted\:*\s+.*(\d+\.\d+\.\d+\-\d+.+)$/) {
			$kernelversion = $1;
		}
	}

	# 3). soft lockup message parsing
	#
	# Mar 24 08:14:03 coolmarket-node4 kernel: [152325.589066] watchdog: BUG: soft lockup - CPU#6 stuck for 25s! [kworker/6:2:322623]
	# Mar 24 08:14:03 coolmarket-node4 kernel: [152325.600966] rcu: 	6-....: (1491 ticks this GP) idle=5ea/1/0x4000000000000002 softirq=3740800/3740800 fqs=830
	# Mar 24 08:14:03 coolmarket-node4 kernel: [152325.601776] Modules linked in: binfmt_misc rpcsec_gss_krb5 auth_rpcgss nfsv4 nfs lockd grace fscache vmw_vsock_vmci_transport vsock dm_multipath scsi_dh_rdac scsi_dh_emc scsi_dh_alua intel_rapl_msr intel_rapl_common sb_edac rapl vmw_balloon joydev input_leds vmw_vmci serio_raw mac_hid sch_fq_codel tcp_htcp sunrpc ip_tables x_tables autofs4 btrfs zstd_compress raid10 raid456 async_raid6_recov async_memcpy async_pq async_xor async_tx xor raid6_pq libcrc32c raid1 raid0 multipath linear crct10dif_pclmul crc32_pclmul vmwgfx ghash_clmulni_intel ttm aesni_intel drm_kms_helper crypto_simd syscopyarea cryptd sysfillrect glue_helper vmw_pvscsi sysimgblt ahci fb_sys_fops psmouse libahci drm vmxnet3 i2c_piix4 pata_acpi
	# Mar 24 08:14:03 coolmarket-node4 kernel: [152325.602781] CPU: 6 PID: 322623 Comm: kworker/6:2 Tainted: G             L    5.4.0-67-generic #75-Ubuntu
	# Mar 24 08:14:03 coolmarket-node4 kernel: [152325.602782] 	(detected by 12, t=65134 jiffies, g=24048537, q=75344)
	# Mar 24 08:14:03 coolmarket-node4 kernel: [152325.602783] Hardware name: VMware, Inc. VMware Virtual Platform/440BX Desktop Reference Platform, BIOS 6.00 04/05/2016
	# Mar 24 08:14:03 coolmarket-node4 kernel: [152325.602786] Sending NMI from CPU 12 to CPUs 6:
	# Mar 24 08:14:03 coolmarket-node4 kernel: [152325.602894] Workqueue: events_freezable vmballoon_work [vmw_balloon]
	if (/watchdog\:\s+BUG\:\s+soft\s+lockup.*CPU\#(\d+)\s+stuck\s+for\s+(\d+)s\!\s+\[(.+)\:(\d+)/) {
		$dtype = "softlockup";
		$cpu = $1;
		$blockseconds = $2;
		$pname = $3;
		$pid = $4;
		# print "line: $nr_line\n";
	}

	# dump_stack(): message example(detail example is put in front of the
	# script.
	#
	# v5.4
	# Mar 22 12:05:46 coolmarket-node4 kernel: [ 6230.958817] CPU: 11 PID: 1505 Comm: cloudflared Not tainted 5.4.0-67-generic #75-Ubuntu
	# Mar 22 12:05:46 coolmarket-node4 kernel: [ 6230.958817] Hardware name: VMware, Inc. VMware Virtual Platform/440BX Desktop Reference Platform, BIOS 6.00 04/05/2016
	# Mar 22 12:05:46 coolmarket-node4 kernel: [ 6230.958822] Call Trace:
	#
	# v4.4
	# 2021-03-08T14:23:50.849804+09:00 compute-5-20122205.domain.tld kernel: [7161107.888485] CPU: 27 PID: 147224 Comm: qemu-system-x86 Tainted: P      D    OE   4.4.0-133-generic #159~14.04.1-Ubuntu
	#
	# v3.13
	# <4>Aug 13 14:59:29 whp1r27c015 kernel: [53058.155599] CPU: 12 PID: 690 Comm: kswapd0 Tainted: G        W  OX 3.13.0-156-generic #206-Ubuntu
	# <4>Aug 13 14:59:29 whp1r27c015 kernel: [53058.155600] Hardware name: Dell Inc. PowerEdge R730xd/072T6D, BIOS 2.7.1 001/22/2018
	# <4>Aug 13 14:59:29 whp1r27c015 kernel: [53058.155602] task: ffff881fcd3046b0 ti: ffff881fcd3c4000 task.ti: ffff881fcd3c4000
	# <4>Aug 13 14:59:29 whp1r27c015 kernel: [53058.155604] RIP: 0010:[<ffffffff810e1c3e>]  [<ffffffff810e1c3e>] smp_call_function_many+0x28e/0x2f0
	if (/CPU\:\s+(\d+)\s+PID\:\s+(\d+)\s+Comm\:(.+)\s+(Not tainted|Tainted).*(\d+\.\d+\.\d+\-\d+.+)$/) {
		$cpu = $1;
		$pid = $2;
		$pname = $3; # overwrite the pname
		$kernelversion = $5;

		# print "$cpu $pid $pname $kernelversion\n";
		next;
	}

	# dump_stack(): Call Trace output:
	# v5.4
	# Mar 22 12:05:46 coolmarket-node4 kernel: [ 6230.958822] Call Trace:
	# Mar 22 12:05:46 coolmarket-node4 kernel: [ 6230.958846]  dump_stack+0x6d/0x8b
	# Mar 22 12:05:46 coolmarket-node4 kernel: [ 6230.958852]  dump_header+0x4f/0x1eb
	#
	# v3.13
	# <4>Aug 13 14:59:29 whp1r27c015 kernel: [53058.155640] Call Trace:
	# <4>Aug 13 14:59:29 whp1r27c015 kernel: [53058.155645]  [<ffffffff81060ad0>] ? do_kernel_range_flush+0x40/0x40
	# <4>Aug 13 14:59:29 whp1r27c015 kernel: [53058.155648]  [<ffffffff81060cfe>] native_flush_tlb_others+0x2e/0x30
	if (defined($dtype) || $include_all_calltrace) {

		if (/\]\s+([^\>]+)\+(0x[a-f\d]+)\//) {

			$lines_skip_before_next_stack-- if $lines_skip_before_next_stack > 0;
			# Filter out the function name starting with "?" mark
			if (/\]\s+(\?\s+.+)\+(0x[a-f\d]+)\//) {
				next;
			}

			# In the following example, the "RIP:..." is the next callstack.
			# Somehow, the kernel messes up the callstack and print the RIP
			# next to the "page_fault+0x34/0x40". If there exist
			# stack captured, just skip the RIP line starting with
			# "RIP: 0010:copy_f..."
			#
			# Mar 22 13:25:12 coolmarket-node4 kernel: [10997.363857]  page_fault+0x34/0x40
			# Mar 22 13:25:12 coolmarket-node4 kernel: [10997.363863] RIP: 0010:copy_fpstate_to_sigframe+0x126/0x370
			if (@stack) {
				# Filter out the RIP line
				if (/\]\s+RIP\:\s+(.+)\+(0x[a-f\d]+)\//) {
					$lines_skip_before_next_stack = 0;
					next;
				}
			} else {
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747160] RIP: 0010:0xffffffffc08172d2
				# -----8<----- start of the 12 lines
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747162] Code: cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc cc <55> 48 89 e5 48 81 ec 00 00 00 00 53 41 55 41 56 41 57 31 c0 45 31
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747163] RSP: 0018:ffffabd7c07709b8 EFLAGS: 00010246 ORIG_RAX: ffffffffffffff13
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747165] RAX: ffffffffc08172d2 RBX: ffff9cf947900000 RCX: 0000000000000036
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747166] RDX: 0000000000000036 RSI: ffffabd7c0b05038 RDI: ffff9cf94ed26600
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747167] RBP: ffffabd7c0770a08 R08: ffff9cf94ed26600 R09: 0000000000000000
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747168] R10: ffffabd7c0b05000 R11: 0000000000000090 R12: ffff9cf94ed26600
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747169] R13: ffff9cf947900000 R14: 0000000000000036 R15: ffff9cf94d07a000
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747170] FS:  0000000000000000(0000) GS:ffff9cf95ff80000(0000) knlGS:0000000000000000
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747171] CS:  0010 DS: 0000 ES: 0000 CR0: 0000000080050033
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747172] CR2: 000056031c610fe8 CR3: 00000007917ae003 CR4: 00000000001606e0
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747234] Call Trace:
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747236]  <IRQ>
				# ----->8----- end of the 12 lines
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747241]  ? packet_rcv+0xca/0x4c0
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747338]  dev_queue_xmit_nit+0x267/0x280
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747340]  dev_hard_start_xmit+0x67/0x1f0
				# Mar 22 13:36:01 coolmarket-node4 kernel: [11646.747341]  ? validate_xmit_skb+0x2f0/0x340
				if (/\]\s+RIP\:\s+(.+)\+(0x[a-f\d]+)\//) {
					$lines_skip_before_next_stack = 17;
					# print "$nr_line: lines_skip_before... $_\n";
				}

			}

			$func_name = $1;
			$addr_offset = $2;

			if ($include_no_offset) {
				unshift @stack, "$func_name";
			} else {
				# unshift @stack, "$nr_line $func_name+$addr_offset";
				unshift @stack, "$func_name+$addr_offset";
			}

		# If the @stack already has some call traces and the current
		# parsed line is not a stack, the logic identifies it's the end
		# of the call stack.
		} else {
			# The sample count flamegraph needs to summarize stack here
			if (@stack) {
				if ($lines_skip_before_next_stack > 0) {
					# print "@stack\n";
					# print "lines_skip_before_next_stack:$lines_skip_before_next_stack\n";
					# print "$nr_line: $_\n";
					$lines_skip_before_next_stack--;
					next;
				}
				# print "line: $nr_line, before summarize, $dtype/$cpu/$pid/$pname, stack: @stack\n";
				summarize_stack_and_cleanup();
				next;
			}
		}
	}
}

foreach my $k (sort { $a cmp $b } keys %collapsed) {
	print "$k $collapsed{$k}\n";
}
