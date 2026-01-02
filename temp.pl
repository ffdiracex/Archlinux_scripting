#!/usr/bin/perl

use strict;
use warnings;

print "TEMPERATURE MONITORING\n";
print "=" x 50, "\n";

# Check thermal zones
if (-d "/sys/class/thermal") {
    print "THERMAL ZONES:\n";
    
    opendir(my $dh, "/sys/class/thermal") or die "Cannot open /sys/class/thermal: $!";
    my @zones = grep { /^thermal_zone/ } readdir($dh);
    closedir $dh;
    
    foreach my $zone (sort @zones) {
        my $temp_file = "/sys/class/thermal/$zone/temp";
        my $type_file = "/sys/class/thermal/$zone/type";
        my $trip_file = "/sys/class/thermal/$zone/trip_point_0_temp";
        
        if (-e $temp_file && -e $type_file) {
            open(my $temp_fh, '<', $temp_file) or next;
            open(my $type_fh, '<', $type_file) or next;
            
            my $temp = <$temp_fh>;
            my $type = <$type_fh>;
            
            chomp $temp;
            chomp $type;
            
            my $temp_c = int($temp / 1000);
            
            print "  $type: $temp_c°C";
            
            # Check if there's a critical temperature
            if (-e $trip_file) {
                open(my $trip_fh, '<', $trip_file) or next;
                my $trip_temp = <$trip_fh>;
                chomp $trip_temp;
                my $trip_c = int($trip_temp / 1000);
                print " (critical: $trip_c°C)";
                close $trip_fh;
            }
            
            print "\n";
            
            close $temp_fh;
            close $type_fh;
        }
    }
}

# Check hwmon
if (-d "/sys/class/hwmon") {
    print "\nHARDWARE MONITORS:\n";
    
    opendir(my $dh, "/sys/class/hwmon") or die "Cannot open /sys/class/hwmon: $!";
    my @hmons = grep { /^hwmon/ } readdir($dh);
    closedir $dh;
    
    foreach my $hmon (sort @hmons) {
        my $name_file = "/sys/class/hwmon/$hmon/name";
        
        if (-e $name_file) {
            open(my $name_fh, '<', $name_file) or next;
            my $name = <$name_fh>;
            chomp $name;
            close $name_fh;
            
            print "  $name:\n";
            
            # Check for temperature sensors
            opendir(my $hdir, "/sys/class/hwmon/$hmon") or next;
            my @files = readdir($hdir);
            closedir $hdir;
            
            my @temps = grep { /_input$/ && /^temp/ } @files;
            my @fans = grep { /_input$/ && /^fan/ } @files;
            
            foreach my $temp_file (sort @temps) {
                $temp_file =~ /^temp(\d+)_input$/;
                my $temp_num = $1;
                
                my $input_file = "/sys/class/hwmon/$hmon/temp${temp_num}_input";
                my $label_file = "/sys/class/hwmon/$hmon/temp${temp_num}_label";
                
                if (-e $input_file) {
                    open(my $input_fh, '<', $input_file) or next;
                    my $temp = <$input_fh>;
                    chomp $temp;
                    close $input_fh;
                    
                    my $label = "temp$temp_num";
                    if (-e $label_file) {
                        open(my $label_fh, '<', $label_file) or next;
                        $label = <$label_fh>;
                        chomp $label;
                        close $label_fh;
                    }
                    
                    my $temp_c = int($temp / 1000);
                    print "    $label: $temp_c°C\n";
                }
            }
            
            foreach my $fan_file (sort @fans) {
                $fan_file =~ /^fan(\d+)_input$/;
                my $fan_num = $1;
                
                my $input_file = "/sys/class/hwmon/$hmon/fan${fan_num}_input";
                
                if (-e $input_file) {
                    open(my $input_fh, '<', $input_file) or next;
                    my $speed = <$input_fh>;
                    chomp $speed;
                    close $input_fh;
                    
                    print "    fan$fan_num: $speed RPM\n";
                }
            }
        }
    }
}