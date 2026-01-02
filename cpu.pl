#!/usr/bin/perl

use strict;
use warnings;

print "CPU INFORMATION\n";
print "=" x 50, "\n";

if (-e "/proc/cpuinfo") {
    open(my $cpu, '<', "/proc/cpuinfo") or die "Cannot open /proc/cpuinfo: $!";
    
    my $core_count = 0;
    my %cpu_info;
    
    while (my $line = <$cpu>) {
        chomp $line;
        if ($line =~ /^processor\s*:\s*(\d+)/) {
            $core_count++;
            $cpu_info{processor}{$1} = {};
        }
        elsif ($line =~ /^([^:]+):\s*(.+)/) {
            my $key = $1;
            my $val = $2;
            
            # Store first occurrence for summary
            if (!exists $cpu_info{summary}{$key}) {
                $cpu_info{summary}{$key} = $val;
            }
        }
    }
    close $cpu;
    
    print "Cores: $core_count\n";
    
    if (exists $cpu_info{summary}{'model name'}) {
        print "Model: $cpu_info{summary}{'model name'}\n";
    }
    if (exists $cpu_info{summary}{'cpu MHz'}) {
        printf "Frequency: %.2f MHz\n", $cpu_info{summary}{'cpu MHz'};
    }
    if (exists $cpu_info{summary}{'cache size'}) {
        print "Cache: $cpu_info{summary}{'cache size'}\n";
    }
}

# Check CPU scaling
if (-d "/sys/devices/system/cpu") {
    print "\nCPU FREQUENCY SCALING:\n";
    
    opendir(my $dh, "/sys/devices/system/cpu") or die $!;
    my @cpus = grep { /^cpu[0-9]+$/ } readdir($dh);
    closedir $dh;
    
    foreach my $cpu (sort @cpus) {
        my $gov_file = "/sys/devices/system/cpu/$cpu/cpufreq/scaling_governor";
        my $freq_file = "/sys/devices/system/cpu/$cpu/cpufreq/scaling_cur_freq";
        
        if (-e $gov_file && -e $freq_file) {
            open(my $gov, '<', $gov_file) or next;
            open(my $freq, '<', $freq_file) or next;
            
            my $governor = <$gov>;
            my $frequency = <$freq>;
            
            chomp $governor;
            chomp $frequency;
            
            printf "$cpu: %s @ %.2f GHz\n", $governor, $frequency / 1000000;
            
            close $gov;
            close $freq;
        }
    }
}