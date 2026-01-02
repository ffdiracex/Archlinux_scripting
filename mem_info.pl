#!/usr/bin/perl

use strict;
use warnings;

print "MEMORY INFORMATION\n";
print "=" x 50, "\n";

if (-e "/proc/meminfo") {
    open(my $mem, '<', "/proc/meminfo") or die "Cannot open /proc/meminfo: $!";
    
    my %mem;
    while (my $line = <$mem>) {
        chomp $line;
        if ($line =~ /^(\w+):\s+(\d+)/) {
            $mem{$1} = $2;
        }
    }
    close $mem;
    
    # Convert kB to MB for display
    print "Total Memory: ", int($mem{MemTotal} / 1024), " MB\n";
    print "Free Memory: ", int($mem{MemFree} / 1024), " MB\n";
    
    if (exists $mem{MemAvailable}) {
        print "Available Memory: ", int($mem{MemAvailable} / 1024), " MB\n";
        my $usage_percent = 100 - int(($mem{MemAvailable} * 100) / $mem{MemTotal});
        print "Memory Usage: $usage_percent%\n";
    }
    
    if (exists $mem{SwapTotal} && $mem{SwapTotal} > 0) {
        print "\nSWAP INFORMATION:\n";
        print "Total Swap: ", int($mem{SwapTotal} / 1024), " MB\n";
        print "Free Swap: ", int($mem{SwapFree} / 1024), " MB\n";
        
        if (exists $mem{SwapCached}) {
            print "Cached Swap: ", int($mem{SwapCached} / 1024), " MB\n";
        }
    }
}

# Check hugepages if available
if (-e "/proc/sys/vm/nr_hugepages") {
    print "\nHUGE PAGES:\n";
    open(my $huge, '<', "/proc/sys/vm/nr_hugepages") or warn $!;
    my $hugepages = <$huge>;
    chomp $hugepages;
    print "Number of hugepages: $hugepages\n";
    close $huge;
}