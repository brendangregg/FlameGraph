#!/usr/bin/perl -w
#
# stackcollapse-vsprof.pl
#
# Parses the CSV file containing a call tree from a visual studio profiler and produces an output suitable for flamegraph.pl.
#
# USAGE: perl stackcollapse-vsprof.pl infile > outfile
#
# WORKFLOW:
#
# This example assumes you have visual studio 2015 installed.
# 
# 1. Profile C++ your application using visual studio
# 2. On visual studio, choose export the call tree as csv
# 3. Generate a flamegraph: perl stackcollapse-vsprof CallTreeSummary.csv | perl flamegraph.pl > result_vsprof.svg
#
# INPUT EXAMPLE :
#
# Level,Function Name,Inclusive Samples,Exclusive Samples,Inclusive Samples %,Exclusive Samples %,Module Name,
# 1,"main","8,735",0,100.00,0.00,"an_executable.exe",
# 2,"testing::UnitTest::Run","8,735",0,100.00,0.00,"an_executable.exe",
# 3,"boost::trim_end_iter_select<std::iterator<std::val<std::types<char> > >,boost::is_classifiedF>",306,16,3.50,0.18,"an_executable.exe",
#
# OUTPUT EXAMPLE :
#
# main;testing::UnitTest::Run;boost::trim_end_iter_select<std::iterator<std::val<std::types<char>>>,boost::is_classifiedF> 306

use strict;

sub massage_function_names;
sub parse_integer;
sub print_stack_trace;

# data initialization
my @stack = ();
my $line_number = 0;
my $previous_samples = 0;

my $num_args = $#ARGV + 1;
if ($num_args != 1) {
  print "$ARGV[0]\n";
  print "Usage : stackcollapse-vsprof.pl <in.cvs> > out.txt\n";
  exit;
}

my $input_csv_file = $ARGV[0];
my $line_parser_rx = qr{
  ^\s*(\d+?),            # level in the stack
  ("[^"]+" | [^,]+),     # function name (beware of spaces)
  ("[^"]+" | [^,]+),     # number of samples (beware of locale number formatting)
}ox;

open(my $fh, '<', $input_csv_file) or die "Can't read file '$input_csv_file' [$!]\n";

while (my $current_line = <$fh>){
  $line_number = $line_number + 1;

  # to discard first line which typically contains headers
  next if $line_number == 1;
  next if $current_line =~ /^\s*$/o;
 
  ($current_line =~ $line_parser_rx) or die "Error in regular expression at line $line_number : $current_line\n";

  my $level = int $1;
  my $function = massage_function_names($2);
  my $samples = parse_integer($3);
  my $stack_len = @stack;
 
  #print "[DEBUG] $line_number : $level $function $samples $stack_len\n";

  next if not $level;
  ($level <= $stack_len + 1) or die "Error in stack at line $line_number : $current_line\n";

  if ($level <= $stack_len) {
		print_stack_trace(\@stack, $previous_samples);
    my $to_remove = $level - $stack_len - 1;
    splice(@stack, $to_remove);
  }

  $stack_len < 1000 or die "Stack overflow at line $line_number";
  push(@stack, $function);
  $previous_samples = $samples;
}
print_stack_trace(\@stack, $previous_samples);

sub massage_function_names {
  return ($_[0] =~ s/\s*|^"|"$//gro);
}

sub parse_integer {
  return int ($_[0] =~ s/[., ]|^"|"$//gro);
}

sub print_stack_trace {
  my ($stack_ref, $sample) = @_;
	my $stack_trace = join(";", @$stack_ref);
	print "$stack_trace $sample\n";
}
