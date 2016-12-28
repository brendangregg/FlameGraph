#!/usr/bin/perl

use Getopt::Std;

getopt('urt');

unless ($opt_r && $opt_t){
	print "Usage: $0 [ -u user] -r sample_count -t sleep_time\n";
	exit(0);
}

my $i;
my @proc = "";
for ($i = 0; $i < $opt_r ; $i++){
    if ($opt_u){
	$proc = `/usr/sysv/bin/ps -u $opt_u `;
	$proc =~ s/^.*\n//;
	$proc =~ s/\s*(\d+).*\n/\1 /g;
	@proc = split(/\s+/,$proc);
    } else {
	opendir(my $dh, '/proc') || die "Cant't open /proc: $!";
	@proc = grep { /^[\d]+$/ } readdir($dh);
	closedir ($dh);
    }	

    foreach my $pid (@proc){
	my $command = "/usr/bin/procstack $pid";
	print `$command 2>/dev/null`;
    }
    select(undef, undef, undef, $opt_t);
}
