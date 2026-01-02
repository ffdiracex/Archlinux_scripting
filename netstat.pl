#!/usr/bin/perl

use strict;
use warnings;

print "NETWORK INFORMATION\n";
print "=" x 50, "\n";

# Get network interfaces from /sys
if (-d "/sys/class/net") {
    opendir(my $dh, "/sys/class/net") or die "Cannot open /sys/class/net: $!";
    
    my @interfaces = grep { !/^\./ } readdir($dh);
    closedir $dh;
    
    foreach my $iface (sort @interfaces) {
        next if $iface eq 'lo';  # Skip loopback
        
        print "Interface: $iface\n";
        
        my $addr_file = "/sys/class/net/$iface/address";
        my $state_file = "/sys/class/net/$iface/operstate";
        my $speed_file = "/sys/class/net/$iface/speed";
        my $duplex_file = "/sys/class/net/$iface/duplex";
        
        if (-e $addr_file) {
            open(my $addr_fh, '<', $addr_file) or warn $!;
            my $mac = <$addr_fh>;
            chomp $mac;
            print "  MAC: $mac\n" if $mac;
            close $addr_fh;
        }
        
        if (-e $state_file) {
            open(my $state_fh, '<', $state_file) or warn $!;
            my $state = <$state_fh>;
            chomp $state;
            print "  State: $state\n" if $state;
            close $state_fh;
        }
        
        if (-e $speed_file) {
            open(my $speed_fh, '<', $speed_file) or warn $!;
            my $speed = <$speed_fh>;
            chomp $speed;
            print "  Speed: $speed Mbps\n" if $speed ne '-1';
            close $speed_fh;
        }
        
        if (-e $duplex_file) {
            open(my $duplex_fh, '<', $duplex_file) or warn $!;
            my $duplex = <$duplex_fh>;
            chomp $duplex;
            print "  Duplex: $duplex\n" if $duplex ne 'unknown';
            close $duplex_fh;
        }
        
        print "\n";
    }
}

# Get IP addresses from /proc/net
print "IP ADDRESSES:\n";
if (-e "/proc/net/fib_trie") {
    open(my $fib, '<', "/proc/net/fib_trie") or warn $!;
    
    my %ips;
    while (my $line = <$fib>) {
        if ($line =~ /^\s+(\S+)\s+(\d+\.\d+\.\d+\.\d+)/) {
            my $ip = $2;
            # Skip localhost and private network IPs if desired
            next if $ip =~ /^127\./;
            $ips{$ip} = 1;
        }
    }
    close $fib;
    
    foreach my $ip (sort keys %ips) {
        print "  $ip\n";
    }
}

# Get default gateway
print "\nDEFAULT GATEWAY:\n";
if (-e "/proc/net/route") {
    open(my $route, '<', "/proc/net/route") or warn $!;
    
    # Skip header
    <$route>;
    
    while (my $line = <$route>) {
        chomp $line;
        my @fields = split(/\s+/, $line);
        if (@fields >= 8 && $fields[1] eq '00000000' && $fields[7] eq '0003') {
            my $gateway_hex = $fields[2];
            # Convert hex IP to dotted decimal
            my $gateway = join('.', map { hex } reverse unpack("A2A2A2A2", $gateway_hex));
            print "  $gateway via $fields[0]\n";
            last;
        }
    }
    close $route;
}