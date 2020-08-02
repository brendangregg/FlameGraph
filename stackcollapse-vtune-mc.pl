#!/usr/bin/perl -w
#
# stackcollapse-vtune-mc.pl
#
# Parses the CSV file containing a call tree from Intel VTune memory-consumption profiler and produces an output suitable for flamegraph.pl.
#
# USAGE: perl stackcollapse-vtune-mc.pl [options] infile > outfile
#
# WORKFLOW:
#
# This assumes you have Intel VTune installed and on path (using Command Line)
#
# 1. Profile C++ application tachyon (example shipped with Intel VTune 2019):
#
#    amplxe-cl -collect memory-consumption -r mc_tachyon -- ./tachyon
#
# 2. Export raw VTune data to csv file:
#    ### for Intel VTune 2019
#    amplxe-cl -R top-down -call-stack-mode all \
#			-column="Allocations:Self","Allocation Size:Self","Module" \
#			-report-out allocations.csv -format csv \
#			-csv-delimiter comma -r mc_tachyon
#
# 3. Generate a flamegraph:
#    ## Generate for allocations amount.
#    perl stackcollapse-vtune-mc.pl allocations.csv > out.folded
#    perl flamegraph.pl --countname=allocations out.folded > vtune_tachyon_mc.svg
#
#    ## Or you can generate for allocation size in bytes.
#    perl stackcollapse-vtune-mc.pl -s allocations.csv > out.folded
#    perl flamegraph.pl --countname=allocations out.folded > vtune_tachyon_mc_size.svg
#
# AUTHOR: Rohith Bakkannagari
# 27-Nov-2019	UnpluggedCoder		Forked from stackcollapse-vtune.pl, for memory-consumption flamegraph

use strict;
use Getopt::Long;

sub usage {
	die <<USAGE_END;
Usage : $0 [options] allocations.csv > out.folded\n
	--size		# Accumulate allocation size in bytes instead of allocation counts.\n
NOTE : The csv file should exported by `amplxe-cl` tool with the exact -column parameter shows below.
	amplxe-cl -R top-down -call-stack-mode all \
		-column="Allocations:Self","Allocation Size:Self","Module" \
		-report-out allocations.csv -format csv \
		-csv-delimiter comma -r mc_tachyon
USAGE_END
}

# data initialization
my @stack = ();
my $rowCounter = 0; # flag for row number

my $accSize = '';
GetOptions ('size' => \$accSize)
or usage();

my $numArgs = $#ARGV + 1;
if ($numArgs != 1){
	usage();
	exit;
}

my $inputCSVFile = $ARGV[0];
open(my $fh, '<', $inputCSVFile) or die "Can't read file '$inputCSVFile' [$!]\n";

while (my $currLine = <$fh>){
	# discard warning line
	next if $rowCounter == 0 && rindex($currLine, "war:", 0) == 0;
	$rowCounter = $rowCounter + 1;
	# to discard first row which typically contains headers
	next if $rowCounter == 1;
	chomp $currLine;
	#VTune - sometimes the call stack information is enclosed in double quotes (?).  To remove double quotes.
	$currLine =~ s/\"//g;

	### for Intel VTune 2019
	### CSV header should be like below
	### Function Stack,Allocation Size:Self,Deallocation Size:Self,Allocations:Self,Module
	$currLine =~ /(\s*)(.*?),([0-9]*?\.?[0-9]*?),([0-9]*?\.?[0-9]*?),([0-9]*?\.?[0-9]*?),(.*)/ or die "Error in regular expression on the current line $currLine\n";
	my $func = $2.'('.$6.')';	# function(module)
	my $depth = length ($1);
	my $allocBytes = $3; 	# allocation size
	my $allocs = $5; 		# allocations

	my $tempString = '';
	$stack [$depth] = $func;
	if ($accSize){
		next if $allocBytes eq '';
		foreach my $i (0 .. $depth - 1) {
			$tempString = $tempString.$stack[$i].";";
		}
		$tempString = $tempString.$func." $allocBytes\n";
	} else {
		next if $allocs == 0;
		foreach my $i (0 .. $depth - 1) {
			$tempString = $tempString.$stack[$i].";";
		}
		$tempString = $tempString.$func." $allocs\n";
	}
	print "$tempString";
}
