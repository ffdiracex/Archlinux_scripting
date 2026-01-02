#!/usr/bin/perl

use strict;
use warnings;

print "DISK INFORMATION\n";
print "=" x 50, "\n";

# Get disk usage from df
print "DISK USAGE:\n";
open(my $df, '-|', 'df -h 2>/dev/null') or die "Cannot run df: $!";
while (my $line = <$df>) {
    # Skip tmpfs and loop devices
    next if $line =~ /(tmpfs|udev|dev\/loop)/;
    print $line;
}
close $df;

print "\nBLOCK DEVICES:\n";
if (-d "/sys/block") {
    opendir(my $dh, "/sys/block") or die "Cannot open /sys/block: $!";
    
    while (my $device = readdir($dh)) {
        next if $device =~ /^\./;
        
        my $size_file = "/sys/block/$device/size";
        my $model_file = "/sys/block/$device/device/model";
        
        if (-e $size_file) {
            open(my $size_fh, '<', $size_file) or next;
            my $sectors = <$size_fh>;
            chomp $sectors;
            close $size_fh;
            
            my $gb = int(($sectors * 512) / (1024 * 1024 * 1024));
            
            my $model = "Unknown";
            if (-e $model_file) {
                open(my $model_fh, '<', $model_file) or next;
                $model = <$model_fh>;
                chomp $model;
                close $model_fh;
            }
            
            print "$device: $model ($gb GB)\n";
        }
    }
    closedir $dh;
}

# Check for partitions
print "\nPARTITIONS:\n";
if (-d "/proc/partitions") {
    open(my $parts, '<', "/proc/partitions") or die "Cannot open /proc/partitions: $!";
    
    # Skip header lines
    <$parts>; <$parts>;
    
    while (my $line = <$parts>) {
        chomp $line;
        my @fields = split(/\s+/, $line);
        if (@fields >= 4) {
            my $name = $fields[3];
            my $blocks = $fields[2];
            my $mb = int($blocks / 2048);  # Convert 1K blocks to MB
            
            # Skip whole disks (like sda, vda)
            next if $name =~ /^[a-z]+[a-z]$/;
            
            print "$name: $mb MB\n";
        }
    }
    close $parts;
}