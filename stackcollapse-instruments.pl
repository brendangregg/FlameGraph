#!/usr/bin/perl -w
#
# stackcollapse-instruments.pl
#
# Parses a file containing a call tree as produced by XCode Instruments
# (Edit > Deep Copy) and produces output suitable for flamegraph.pl.
#
# USAGE: ./stackcollapse-instruments.pl infile > outfile

use strict;

my @stack = ();
my @stack;

# Skip the first line
<>;

# Main function to process all input
sub process_input {
    foreach (<>) {
        chomp;
        parse_line($_);
    }
}

# Parse a single line and print the stack trace with time
sub parse_line {
    my ($line) = @_;
    
    $line =~ /\d+\.\d+ (?:min|s|ms)\s+\d+\.\d+%\s+(\d+(?:\.\d+)?) (min|s|ms)\t \t(\s*)(.+)/ or die;
    
    my $func = $4;
    my $depth = length($3);
    $stack[$depth] = $4;
    
    # Print the stack trace
    foreach my $i (0 .. $depth - 1) {
        print $stack[$i];
        print ";";
    }
    
    # Convert time to milliseconds
    my $time = 0 + $1;
    if ($2 eq "min") {
        $time *= 60*1000;
    } elsif ($2 eq "s") {
        $time *= 1000;
    }
    
    # Print the function name and time
    printf("%s %.0f\n", $func, $time);
}

# Call the main processing function
process_input();