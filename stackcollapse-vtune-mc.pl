#!/usr/bin/perl -w
#
# stackcollapse-vtune-mc.pl
#
# Parses the CSV file containing a call tree from Intel VTune memory-consumption profiler and produces an output suitable for flamegraph.pl.
#
# USAGE: perl stackcollapse-vtune-mc.pl infile > outfile
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
#    amplxe-cl -R top-down -call-stack-mode all -column="Allocations:Self","Module" -report-out allocations.csv -format csv -csv-delimiter comma -r mc_tachyon
#
# 3. Generate a flamegraph:
#
#    perl stackcollapse-vtune-mc allocations.csv > out.folded
#    perl flamegraph.pl --countname=allocations out.folded > vtune_tachyon_mc.svg
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
print "Usage : stackcollapse-vtune-mc.pl <out.cvs> > out.txt\n";
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
	### Function Stack,Allocations:Self,Module
	$currLine =~ /(\s*)(.*?),([0-9]+?),(.*)/ or die "Error in regular expression on the current line $currLine\n";
	my $func = $2.'('.$4.')';
	my $depth = length ($1);
	my $allocs = $3; # allocations

	my $tempString = '';
	$stack [$depth] = $func;
	next if $allocs == 0;

	foreach my $i (0 .. $depth - 1) {
		$tempString = $tempString.$stack[$i].";";
	}
	$tempString = $tempString.$func." $allocs\n";

	print "$tempString";
}
