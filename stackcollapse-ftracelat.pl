#!/usr/bin/perl -w

use strict;
use Getopt::Long;

my %collapsed;
my @stack;
my @time_stack;

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
my $include_debug;
my $include_no_offset;
my $include_no_page_order;
my $include_no_page_type;
my $include_no_pname;
my $kernelversion;
my $latency = 0;
my $lines_skip_before_next_stack = 0;
my $nr_line = 0;
my $pid;
my $pname;
my $oom_score_adj;
my $order;
my $time_accumulator = 0;
my $tsp;


GetOptions('all_calltrace' => \$include_all_calltrace,
	   'block_seconds' => \$include_block_seconds,
	   'debug' => \$include_debug,
	   'no_offset' => \$include_no_offset,
	   'no_page_order' => \$include_no_page_order,
	   'no_page_type' => \$include_no_page_type,
	   'no_process_name' => \$include_no_pname)
or die <<USAGE_END;
USAGE: $0 [options] infile > outfile\n
	--all_calltrace		# Show all the call trace even there is no OOM/hungtask/soft lockup error.
	--debug			# Enable the debug message
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


sub debug_log {
	my ($message) = @_;
	print "$message" if $include_debug;
}

sub remember_stack {
	my ($stack, $count) = @_;
	$collapsed{$stack} += $count*1000;
	debug_log "$stack $collapsed{$stack}\n";
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
	my ($pop_func, $undef_var, $latency) = @_;

out:
	remember_stack(join(";", @stack), $latency);
	pop @stack if $pop_func;
	undefine_variables() if $undef_var;
}


#
# Main loop
#
while (defined($_ = <>)) {

	$nr_line = $.;

	# 1). Function start
	# Processor-31570 [007] 2872459.738331: funcgraph_entry:                   |  SyS_writev() {
	if (/\s*(.+)\s+\[(\d+)\]\s+(\d+\.\d+)\:\s+(funcgraph_entry)\:\s+\|\s+(.+)\(\)\s+\{/) {
		debug_log "##### function_entry #####\n";
		$pname = $1;
		$cpu = $2;
		$tsp = $3;
		$func_name = $5;

		push @time_stack, $time_accumulator;
		push @time_stack, $func_name;
		$time_accumulator = 0; # Reset the time for each function

=pod
		if (!@stack) {
			unshift @stack, $pname if ($pname);
			unshift @stack, "CPU# $cpu" if ($cpu);
		}
=cut

		debug_log "@time_stack\n";
		push @stack, "$func_name";
		next; # ready to parse the dump_stack call trace
	}

	# 2). Single function
	# Processor-31570 [007] 2872459.738333: funcgraph_entry:        0.376 us   |    fget_light();
	# Processor-31570 [006] 2872460.164409: funcgraph_entry:      + 11.008 us  | __x2apic_send_IPI_mask();
	# if (/\s*(.+)\s+\[(\d+)\]\s+(\d+\.\d+)\:\s+(.*)\:\s+(.*\s*\d+\.\d+)\s+.+\s+\|\s+(.+\(\));/) {
	#
	#   Documentation/trace/ftrace.rst
	#   + means that the function exceeded 10 usecs.
	#   ! means that the function exceeded 100 usecs.
	#   # means that the function exceeded 1000 usecs.
	#   * means that the function exceeded 10 msecs.
	#   @ means that the function exceeded 100 msecs.
	#   $ means that the function exceeded 1 sec.

	if (/\s*(.+)\s+\[(\d+)\]\s+(\d+\.\d+)\:\s+(funcgraph_entry)\:\s+[+!#*@$]?\s*(\d+\.\d+)\s+.+\s+\|\s+(.+)\(\);/) {
		debug_log "##### Single function #####\n";
		$pname = $1;
		$cpu = $2;
		$tsp = $3;
		$latency = $5;
		$func_name = $6;
		push @stack, "$func_name";

		$time_accumulator += $latency; # accumulate the time inside the function
		summarize_stack_and_cleanup(1, 0, $latency); # pop:true, undef:false
		next; # ready to parse the dump_stack call trace
	}

	# 3). Function end
	# Processor-31570 [007] 2872459.738421: funcgraph_exit:       + 15.597 us  |          }
	# if (/\s*(.+)\s+\[(\d+)\]\s+(\d+\.\d+)\:\s+(.*)\:\s+(.*\s*\d+\.\d+)\s+.+\s+\|\s+\}/) {
	if (/\s*(.+)\s+\[(\d+)\]\s+(\d+\.\d+)\:\s+(funcgraph_exit)\:\s+[+!#*@$]?\s*(\d+\.\d+)\s+.+\s+\|\s+\}/) {
		$pname = $1;
		$cpu = $2;
		$tsp = $3;
		$latency = $5;
		debug_log "L$nr_line: $tsp $pname $cpu $latency\n";

		my $save_time_accumulator;
		debug_log "##### funcgraph_exit } #####\n";
		my $len_time_stack = scalar @time_stack;
		debug_log "len_time_stack: $len_time_stack\n";
		debug_log "\$time_stack[$len_time_stack - 1]: $time_stack[$len_time_stack - 1]\n";
		$_ = $time_stack[$len_time_stack - 1];

		debug_log "\$_: $_\n";
		debug_log "\@stack: @stack\n";
		debug_log "\@time_stack: @time_stack\n";

		until ($_ =~ /[^\d\.]/) {
			$time_accumulator += $_;
			$_ = pop @time_stack;
			debug_log "pop value: $_\n";
			$len_time_stack = scalar @time_stack;
			$_ = $time_stack[$len_time_stack - 1];
		}

		pop @time_stack;
		debug_log "\@time_stack: @time_stack\n";

		$save_time_accumulator = $latency;
		debug_log "$latency -= $time_accumulator\n";
		$latency -= $time_accumulator;
		debug_log "final latency: $latency\n";

		$time_accumulator = $save_time_accumulator;
		debug_log "new time_accumulator: $time_accumulator\n";

		summarize_stack_and_cleanup(1, 0, $latency);
		next; # ready to parse the dump_stack call trace
		
	}
}

foreach my $k (sort { $a cmp $b } keys %collapsed) {
	print "$k $collapsed{$k}\n";
}
