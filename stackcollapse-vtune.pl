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
#
##### VTune 2013 & 2015
#   amplxe-cl -R top-down -report-out result_vtune_tachyon.csv -filter "Function Stack" -format csv -csv-delimiter comma -r result_vtune_tachyon
#### VTune 2016
#		amplxe-cl.exe -R top-down -call-stack-mode all -column="CPU Time:Self","Module" -report-output result_vtune_tachyon.csv -filter "Function Stack" -format csv -csv-delimiter comma -r result_vtune_tachyon
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
my $funcOnly = '';
my $depth = 0;
my $selfTime = 0;
my $dllName = '';

open(my $fh, '<', $inputCSVFile) or die "Can't read file '$inputCSVFile' [$!]\n";

while (my $currLine = <$fh>){
	$rowCounter = $rowCounter + 1;
	# to discard first row which typically contains headers
	next if $rowCounter == 1;
	chomp $currLine;

	### VTune 2013 & 2015
	#VTune - sometimes the call stack information is enclosed in double quotes (?).  To remove double quotes.  Not necessary for XCode instruments (MAC)
	$currLine =~ s/\"//g;
	$currLine =~ /(\s*)(.*),(.*),.*,([0-9]*\.?[0-9]+)/ or die "Error in regular expression on the current line\n";
	$dllName = $3;
	$func = $dllName.'!'.$2; # Eg : m_lxe.dll!MathWorks::lxe::IrEngineDecorator::Apply
	$depth = length ($1);
	$selfTime = $4*1000; # selfTime in msec
	### VTune 2013 & 2015

	### VTune 2016
	# $currLine =~ /(\s*)(.*?),([0-9]*\.?[0-9]+?),(.*)/ or die "Error in regular expression on the current line $currLine\n";
	#  if ($2 =~ /\"/)
	#  {
	# 	$currLine =~ /(\s*)\"(.*?)\",([0-9]*\.?[0-9]+?),(.*)/ or die "Error in regular expression on the current line $currLine\n";
	#  	$funcOnly = $2;
	#  	$depth = length ($1);
	#  	$selfTime = $3*1000; # selfTime in msec
	#  	$dllName = $4;
	#  }
	#  else
	#  {
	#  	$funcOnly = $2;
	#  	$depth = length ($1);
	#  	$selfTime = $3*1000; # selfTime in msec
	#  	$dllName = $4;
	#  }
	#  my $func = $dllName.'!'.$funcOnly; # Eg : m_lxe.dll!MathWorks::lxe::IrEngineDecorator::Apply
	 ### VTune 2016

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
