#!/usr/bin/perl -w
#
# stackcollapse-vtune.pl
#
# Parses the CSV file containing a call tree from Intel VTune hotspots profiler and produces an output suitable for flamegraph.pl.
#
# USAGE: perl stackcollapse-vtune.pl infile > outfile
#
# WORKFLOW:
#
# This assumes you have Intel VTune installed and on path (using Command Line)
# 
# 1. Profile C++ application tachyon_find_hotspots (example shipped with Intel VTune 2013):
#
#    amplxe-cl -collect hotspots -r result_vtune_tachyon -- ./tachyon_find_hotspots
#
# 2. Export raw VTune data to csv file:
#    ###for Intel VTune 2013
#    amplxe-cl -R top-down -call-stack-mode all -report-out result_vtune_tachyon.csv -filter "Function Stack" -format csv -csv-delimiter comma -r result_vtune_tachyon
#    
#    ###for Intel VTune 2015 & 2016
#    amplxe-cl -R top-down -call-stack-mode all -column="CPU Time:Self","Module" -report-out result_vtune_tachyon.csv -filter "Function Stack" -format csv -csv-delimiter comma -r result_vtune_tachyon
#
# 3. Generate a flamegraph:
#
#    perl stackcollapse-vtune result_vtune_tachyon.csv | perl flamegraph.pl > result_vtune_tachyon.svg
#
# AUTHOR: Rohith Bakkannagari

use strict;

# data initialization
my @stack = ();
my $rowCounter = 0; #flag for row number

my $numArgs = $#ARGV + 1;
if ($numArgs != 1)
{
print "$ARGV[0]\n";
print "Usage : stackcollapse-vtune.pl <out.cvs> > out.txt\n";
exit;
}

my $inputCSVFile = $ARGV[0];

open(my $fh, '<', $inputCSVFile) or die "Can't read file '$inputCSVFile' [$!]\n";

while (my $currLine = <$fh>){
	$rowCounter = $rowCounter + 1;
	# to discard first row which typically contains headers
	next if $rowCounter == 1;
	chomp $currLine;
	#VTune - sometimes the call stack information is enclosed in double quotes (?).  To remove double quotes. 
	$currLine =~ s/\"//g;
	
	### for Intel VTune 2013
	#$currLine =~ /(\s*)(.*),(.*),[0-9]*\.?[0-9]+[%],([0-9]*\.?[0-9]+)/ or die "Error in regular expression on the current line\n";
	#my $func = $3.'!'.$2; 
	#my $depth = length ($1);
	#my $selfTime = $4*1000; # selfTime in msec
	
	### for Intel VTune 2015 & 2016
	$currLine =~ /(\s*)(.*?),([0-9]*\.?[0-9]+?),(.*)/ or die "Error in regular expression on the current line $currLine\n";
	my $func = $4.'!'.$2; 
	my $depth = length ($1);
	my $selfTime = $3*1000; # selfTime in msec
	
	my $tempString = '';
	$stack [$depth] = $func;
	foreach my $i (0 .. $depth - 1) {
		$tempString = $tempString.$stack[$i].";";
	}
	$tempString = $tempString.$func." $selfTime\n";
	
	if ($selfTime != 0){
		print "$tempString";
	}
}
