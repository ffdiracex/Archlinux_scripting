#!/usr/bin/perl

use strict;
use warnings;

my %expected_perms = (
    # Critical system directories - should be root:root with restrictive permissions
    '/bin' => '0755',
    '/boot' => '0755',
    '/dev' => '0755',
    '/etc' => '0755',
    '/etc/passwd' => '0644',
    '/etc/shadow' => '0640',
    '/etc/group' => '0644',
    '/etc/gshadow' => '0640',
    '/etc/sudoers' => '0440',
    '/home' => '0755',
    '/lib' => '0755',
    '/lib64' => '0755',
    '/media' => '0755',
    '/mnt' => '0755',
    '/opt' => '0755',
    '/proc' => '0555',
    '/root' => '0750',
    '/run' => '0755',
    '/sbin' => '0755',
    '/srv' => '0755',
    '/sys' => '0555',
    '/tmp' => '1777',
    '/usr' => '0755',
    '/usr/bin' => '0755',
    '/usr/sbin' => '0755',
    '/usr/lib' => '0755',
    '/usr/local' => '0755',
    '/var' => '0755',
    '/var/log' => '0755',
    '/var/tmp' => '1777',
    
    # SSH files
    '/etc/ssh/ssh_host_rsa_key' => '0600',
    '/etc/ssh/ssh_host_dsa_key' => '0600',
    '/etc/ssh/ssh_host_ecdsa_key' => '0600',
    '/etc/ssh/ssh_host_ed25519_key' => '0600',
    '/etc/ssh/sshd_config' => '0600',
    '/root/.ssh' => '0700',
    '/root/.ssh/authorized_keys' => '0600',
    
    # User directories (pattern matching)
    'HOME_DIR/.ssh' => '0700',
    'HOME_DIR/.ssh/authorized_keys' => '0600',
    'HOME_DIR/.ssh/id_rsa' => '0600',
    'HOME_DIR/.ssh/id_dsa' => '0600',
    'HOME_DIR/.ssh/known_hosts' => '0644',
    
    # Important binaries that should not be world-writable
    '/bin/bash' => '0755',
    '/bin/sh' => '0755',
    '/usr/bin/sudo' => '4755',
    '/bin/su' => '4755',
    '/usr/bin/passwd' => '4755',
    '/bin/mount' => '4755',
    '/bin/umount' => '4755',
    '/bin/ping' => '4755',
    
    # Crontabs
    '/etc/crontab' => '0644',
    '/etc/cron.hourly' => '0755',
    '/etc/cron.daily' => '0755',
    '/etc/cron.weekly' => '0755',
    '/etc/cron.monthly' => '0755',
    '/var/spool/cron' => '0700',
    
    # Web server files (if applicable)
    '/var/www' => '0755',
    '/var/www/html' => '0755',
    
    # Database files (if applicable)
    '/var/lib/mysql' => '0755',
    '/etc/mysql/my.cnf' => '0644',
);

# Additional patterns for checking
my %pattern_perms = (
    '/etc/ssh/ssh_host_.*_key' => '0600',
    '/home/.*/\.ssh' => '0700',
    '/home/.*/\.ssh/authorized_keys' => '0600',
    '/home/.*/\.ssh/id_.*' => '0600',
    '/usr/bin/.*' => '0755',
    '/usr/sbin/.*' => '0755',
    '/bin/.*' => '0755',
    '/sbin/.*' => '0755',
);

# Known dangerous permissions
my @dangerous_perms = qw/4777 2777 1777 0666 0777/;

print "SYSTEM PERMISSIONS CHECK\n";
print "=" x 60, "\n\n";

my $issues_found = 0;
my $warnings_found = 0;

# Check specific files/directories
foreach my $path (sort keys %expected_perms) {
    next if $path =~ /^HOME_DIR/;  # Skip patterns for now
    
    my $expected = $expected_perms{$path};
    
    if (-e $path) {
        my ($mode, $owner, $group) = get_file_info($path);
        
        if ($mode ne $expected) {
            print "ISSUE: $path\n";
            printf "  Expected: %04o, Found: %04o, Owner: %s:%s\n", 
                   oct($expected), oct($mode), $owner, $group;
            
            if (is_dangerous_permission($mode)) {
                print "  WARNING: Potentially dangerous permission!\n";
            }
            print "\n";
            $issues_found++;
        }
    }
}

# Check for world-writable files in sensitive locations
print "\nCHECKING FOR WORLD-WRITABLE FILES:\n";
print "-" x 40, "\n";

check_world_writable("/etc");
check_world_writable("/bin");
check_world_writable("/sbin");
check_world_writable("/usr/bin");
check_world_writable("/usr/sbin");
check_world_writable("/lib");
check_world_writable("/lib64");
check_world_writable("/boot");

# Check for SUID/SGID files
print "\nCHECKING SUID/SGID FILES:\n";
print "-" x 40, "\n";

check_suid_sgid("/usr/bin");
check_suid_sgid("/bin");
check_suid_sgid("/sbin");
check_suid_sgid("/usr/sbin");

# Check /tmp and /var/tmp for sticky bit
print "\nCHECKING TEMPORARY DIRECTORIES:\n";
print "-" x 40, "\n";

check_sticky_bit("/tmp");
check_sticky_bit("/var/tmp");

# Check user home directories
print "\nCHECKING USER HOME DIRECTORIES:\n";
print "-" x 40, "\n";

if (-e "/etc/passwd") {
    open(my $passwd, '<', "/etc/passwd") or warn "Cannot open /etc/passwd: $!";
    while (my $line = <$passwd>) {
        chomp $line;
        my @fields = split(/:/, $line);
        my $username = $fields[0];
        my $homedir = $fields[5];
        
        next unless $homedir && -d $homedir;
        next if $username =~ /^(nobody|root|bin|daemon|sys|sync)$/;
        
        my ($mode, $owner, $group) = get_file_info($homedir);
        
        # Home directories should not be world-readable
        if (oct($mode) & 0004) {  # World read bit is set
            print "WARNING: $homedir (user: $username) is world-readable\n";
            printf "  Permissions: %04o, Owner: %s:%s\n", oct($mode), $owner, $group;
            $warnings_found++;
        }
        
        # Check .ssh directory if it exists
        my $ssh_dir = "$homedir/.ssh";
        if (-d $ssh_dir) {
            my ($ssh_mode, $ssh_owner, $ssh_group) = get_file_info($ssh_dir);
            if ($ssh_mode ne '0700') {
                print "ISSUE: $ssh_dir should be 0700, found $ssh_mode\n";
                $issues_found++;
            }
            
            # Check authorized_keys
            my $auth_keys = "$ssh_dir/authorized_keys";
            if (-e $auth_keys) {
                my ($ak_mode) = get_file_info($auth_keys);
                if ($ak_mode ne '0600' && $ak_mode ne '0644') {
                    print "ISSUE: $auth_keys should be 0600 or 0644, found $ak_mode\n";
                    $issues_found++;
                }
            }
        }
    }
    close $passwd;
}

# Check for files with no owner (orphaned)
print "\nCHECKING FOR FILES WITH NO OWNER:\n";
print "-" x 40, "\n";

check_no_owner("/etc");
check_no_owner("/bin");
check_no_owner("/sbin");
check_no_owner("/usr/bin");
check_no_owner("/usr/sbin");

# Summary
print "\n" . "=" x 60 . "\n";
print "SUMMARY:\n";
print "  Issues found: $issues_found\n";
print "  Warnings: $warnings_found\n";

if ($issues_found == 0 && $warnings_found == 0) {
    print "\n All checks passed!\n";
} else {
    print "\n Please review the issues above.\n";
}

# Helper functions
sub get_file_info {
    my ($path) = @_;
    
    my @stat = stat($path);
    return unless @stat;
    
    my $mode = sprintf("%04o", $stat[2] & 07777);
    my $uid = $stat[4];
    my $gid = $stat[5];
    
    my $owner = get_username($uid) || $uid;
    my $group = get_groupname($gid) || $gid;
    
    return ($mode, $owner, $group);
}

sub get_username {
    my ($uid) = @_;
    
    if (open(my $passwd, '<', "/etc/passwd")) {
        while (my $line = <$passwd>) {
            chomp $line;
            my @fields = split(/:/, $line);
            if ($fields[2] == $uid) {
                close $passwd;
                return $fields[0];
            }
        }
        close $passwd;
    }
    return undef;
}

sub get_groupname {
    my ($gid) = @_;
    
    if (open(my $group, '<', "/etc/group")) {
        while (my $line = <$group>) {
            chomp $line;
            my @fields = split(/:/, $line);
            if ($fields[2] == $gid) {
                close $group;
                return $fields[0];
            }
        }
        close $group;
    }
    return undef;
}

sub is_dangerous_permission {
    my ($mode) = @_;
    my $oct_mode = oct($mode);
    
    # Check for world-writable or SUID/SGID with world-writable
    return 1 if ($oct_mode & 0002) && (($oct_mode & 04000) || ($oct_mode & 02000));
    return 1 if ($oct_mode & 0002) && ($oct_mode & 0111);  # World-writable and executable
    
    # Check against known dangerous patterns
    foreach my $danger (@dangerous_perms) {
        return 1 if $mode eq $danger;
    }
    
    return 0;
}

sub check_world_writable {
    my ($dir) = @_;
    
    return unless -d $dir;
    
    if (open(my $find, '-|', "find '$dir' -type f -perm -0002 -ls 2>/dev/null | head -20")) {
        my $count = 0;
        while (my $line = <$find>) {
            $count++;
            if ($count == 1) {
                print "World-writable files in $dir:\n";
            }
            print "  $line";
        }
        close $find;
        
        if ($count > 20) {
            print "  ... and more (truncated)\n";
        } elsif ($count == 0) {
            print "  No world-writable files found\n";
        }
        print "\n";
    }
}

sub check_suid_sgid {
    my ($dir) = @_;
    
    return unless -d $dir;
    
    print "SUID/SGID files in $dir:\n";
    
    if (open(my $find, '-|', "find '$dir' \\( -perm -4000 -o -perm -2000 \\) -type f -ls 2>/dev/null")) {
        my $count = 0;
        while (my $line = <$find>) {
            $count++;
            print "  $line";
        }
        close $find;
        
        if ($count == 0) {
            print "  None found\n";
        }
        print "\n";
    }
}

sub check_sticky_bit {
    my ($dir) = @_;
    
    return unless -d $dir;
    
    my ($mode) = get_file_info($dir);
    my $oct_mode = oct($mode);
    
    if ($oct_mode & 01000) {
        print "✓ $dir has sticky bit set (good)\n";
    } else {
        print "✗ $dir missing sticky bit (should be 1777)\n";
        $issues_found++;
    }
}

sub check_no_owner {
    my ($dir) = @_;
    
    return unless -d $dir;
    
    if (open(my $find, '-|', "find '$dir' -nouser -o -nogroup -ls 2>/dev/null | head -10")) {
        my $count = 0;
        while (my $line = <$find>) {
            $count++;
            if ($count == 1) {
                print "Files with no owner/group in $dir:\n";
            }
            print "  $line";
        }
        close $find;
        
        if ($count == 0) {
            print "  No orphaned files found\n";
        }
        print "\n";
    }
}