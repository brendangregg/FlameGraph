use strict;
use warnings;
use Test::More tests => 1;

# Import the function to test
do 'stackcollapse-instruments.pl';

sub capture_stdout(&) {
    my $code = shift;
    open my $oldout, ">&STDOUT" or die "Can't dup STDOUT: $!";
    open STDOUT, '>', \my $output or die "Can't redirect STDOUT: $!";
    $code->();
    open STDOUT, ">&", $oldout or die "Can't restore STDOUT: $!";
    return $output;
}

sub test_parse_line_with_seconds {
    # Example input: "12.34 s    56.78% 1.23 s\t \t    my_function"
    # Should print: "my_function 1230\n"
    # (1.23 s = 1230 ms)
    our @stack;
    my $input = "12.34 s    56.78% 1.23 s\t \t    my_function";
    my $expected = "my_function 1230\n";
    my $output = capture_stdout { parse_line($input) };
    $output =~ s/.*?((?:[^;]*;)*my_function \d+\n)\z/$1/s; # Extract the last stack line
    is($output, $expected, "Correctly parses and prints stack trace for seconds");
}

test_parse_line_with_seconds();