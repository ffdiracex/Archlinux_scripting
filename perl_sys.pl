#!/usr/bin/perl

use strict;
use warnings;

my $ts = `date +%Y%m%d_%H%M%S`;
chomp $ts;
my $output = "system_info_$ts.txt";

open(my $fh, '>', $output) or die "Cannot open $output: $!";

print $fh "System Information Report - ", scalar localtime, "\n";
print $fh "=" x 50, "\n\n";

# 1. Basic system info
print $fh "1. SYSTEM INFO\n";
print $fh "-" x 15, "\n";

if (-e "/sys/devices/virtual/dmi/id/product_name") {
    open(my $prod, '<', "/sys/devices/virtual/dmi/id/product_name") or warn $!;
    my $product = <$prod>;
    chomp $product;
    print $fh "Product: $product\n" if $product;
    close $prod;
}

my $hostname = `hostname`;
chomp $hostname;
my $kernel = `uname -r`;
chomp $kernel;
my $arch = `uname -m`;
chomp $arch;

print $fh "Hostname: $hostname\n";
print $fh "Kernel: $kernel\n";
print $fh "Arch: $arch\n";

if (-e "/etc/os-release") {
    open(my $os, '<', "/etc/os-release") or warn $!;
    while (my $line = <$os>) {
        if ($line =~ /^(PRETTY_NAME|NAME|VERSION_ID)=/) {
            $line =~ s/^PRETTY_NAME=/OS: /;
            $line =~ s/^NAME=/OS: /;
            $line =~ s/^VERSION_ID=/Version: /;
            $line =~ s/"//g;
            print $fh $line;
        }
    }
    close $os;
}
print $fh "\n";

# 2. CPU info
print $fh "2. CPU INFO\n";
print $fh "-" x 15, "\n";

if (-e "/proc/cpuinfo") {
    open(my $cpu, '<', "/proc/cpuinfo") or warn $!;
    my $cores = 0;
    my $model = "";
    my $mhz = "";
    
    while (my $line = <$cpu>) {
        if ($line =~ /^processor/) {
            $cores++;
        }
        if ($line =~ /^model name\s*:\s*(.+)/ && !$model) {
            $model = $1;
        }
        if ($line =~ /^cpu MHz\s*:\s*(.+)/ && !$mhz) {
            $mhz = $1;
        }
    }
    close $cpu;
    
    print $fh "Model: $model\n" if $model;
    print $fh "Cores: $cores\n";
    print $fh "MHz: $mhz\n" if $mhz;
}

if (-e "/sys/devices/system/cpu/online") {
    open(my $online, '<', "/sys/devices/system/cpu/online") or warn $!;
    my $online_cpus = <$online>;
    chomp $online_cpus;
    print $fh "Online CPUs: $online_cpus\n" if $online_cpus;
    close $online;
}
print $fh "\n";

# 3. Memory info
print $fh "3. MEMORY INFO\n";
print $fh "-" x 15, "\n";

if (-e "/proc/meminfo") {
    open(my $mem, '<', "/proc/meminfo") or warn $!;
    my %memdata;
    
    while (my $line = <$mem>) {
        if ($line =~ /^(MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree):\s*(\d+)/) {
            $memdata{$1} = int($2 / 1024);
        }
    }
    close $mem;
    
    foreach my $key (qw/MemTotal MemFree MemAvailable SwapTotal SwapFree/) {
        print $fh "$key: $memdata{$key} MB\n" if exists $memdata{$key};
    }
}
print $fh "\n";

# 4. Uptime and load
print $fh "4. UPTIME AND LOAD\n";
print $fh "-" x 15, "\n";

my $uptime = `uptime`;
chomp $uptime;
print $fh "$uptime\n";

if (-e "/proc/loadavg") {
    open(my $load, '<', "/proc/loadavg") or warn $!;
    my $loadavg = <$load>;
    chomp $loadavg;
    print $fh "Load avg: $loadavg\n";
    close $load;
}

close $fh;
print "Report saved to: $output\n";