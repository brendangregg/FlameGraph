#!/usr/bin/perl -w
#
# stackcollapse-vtune-mc-size.pl
#
# Parses the CSV file containing a call tree from Intel VTune memory-consumption profiler and produces an output suitable for flamegraph.pl.
# The width of the function shows the total bytes allocated.
#
# USAGE: perl stackcollapse-vtune-mc-size.pl infile > outfile
#
# WORKFLOW:
#
# This assumes you have Intel VTune installed and on path (using Command Line)
#
# 1. Profile C++ application tachyon (example shipped with Intel VTune 2019):
#
#    amplxe-cl -collect memory-consumption -r result_vtune_tachyon -- ./tachyon
#
# 2. Export raw VTune data to csv file:
#    ### for Intel VTune 2019
#    amplxe-cl -R top-down -call-stack-mode all -column="Allocation Size:Self","Module" -report-out allocation_size.csv -format csv -csv-delimiter comma -r result_vtune_tachyon
#
# 3. Generate a flamegraph:
#
#    perl stackcollapse-vtune-mc-size allocation_size.csv > out.folded
#    perl flamegraph.pl --countname=bytes out.folded > vtune_tachyon_mc_size.svg
#
# AUTHOR: Rohith Bakkannagari
# 27-Nov-2019	UnpluggedCoder		Forked from stackcollapse-vtune.pl, for memory-consumption flamegraph

use strict;

# data initialization
my @stack = ();
my $rowCounter = 0; # flag for row number

my $numArgs = $#ARGV + 1;
if ($numArgs != 1)
{
print "$ARGV[0]\n";
print "Usage : stackcollapse-vtune-mc-size.pl <out.cvs> > out.txt\n";
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
	###	Function Stack,Allocation Size:Self,Deallocation Size:Self,Module
	$currLine =~ /(\s*)(.*?),([0-9]*?\.?[0-9]*?),([0-9]*?\.?[0-9]*),(.*)/ or die "Error in regular expression on the current line $currLine\n";
	my $func = $2.'('.$5.')';
	my $depth = length ($1);
	my $allocs = $3; 	# allocation size in bytes
	my $deallocs = $4; 	# deallocation size in bytes

	my $tempString = '';
	$stack [$depth] = $func;

	next if $allocs eq '';
	if ($allocs != 0){
		foreach my $i (0 .. $depth - 1) {
			$tempString = $tempString.$stack[$i].";";
		}
		$tempString = $tempString.$func." $allocs\n";
		print "$tempString";
	}
}
