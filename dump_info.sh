#!/bin/bash

# Dump credentials and information about your system
# NOTE: Do not share this information, it can put your system at risk of being compromised.

output_file="info_dump_$(date +%Y%m%d_%H%M%S).txt" #Year/Month/Day /Hour/Minute/Second

clear

echo "information dump and system logs" >> $output_file
echo "time of execution : $(date)" >> $output_file
echo "executed by: $(whoami)" >> $output_file
echo -e "\n" >> $output_file #printf "\n"

echo "Hostname: $(hostname)" >> $output_file
echo "os: $(uname -o)" >> $output_file
echo "kernel_v: $(uname -r)" >> $output_file
echo "cpu_arch: $(uname  -m)" >> $output_file #x86_64, aarch64 etc.
echo -e "\n" >> $output_file #printf "\n"

if [ -f /etc/os-release ]; then
  echo "cpu info:" >> $output_file
  lscpu | grep "Model name" >> $output_file
  echo "mem info:" >> $output_file
  free -h >> $output_file # Format: Mem Swap, total | used | free | shared | buff | cache | avail
fi

echo "disk" >> $output_file
df -h >> $output_file

echo "dumping /sys info, /sys/class/dmi/id " >> $output_file
cat /sys/class/dmi/id*

echo -e "\ndumping /sys/block for disk info " >> $output_file
ls -l /sys/block/

echo "\nchecking if we're on laptop or desktop " >> $output_file
if grep -qi 'Laptop' /sys/class/dmi/id/product_name 2>/dev/null || \
   grep -qi 'Notebook' /sys/class/dmi/id/product_name 2>/dev/null || \
   grep -qi 'ThinkPad' /sys/class/dmi/id/product_name 2>/dev/null; then
      echo "system type: laptop" >> $output_file
elif grep -qi 'Desktop' /sys/class/dmi/id/product_name 2>/dev/null || \
     grep -qi 'Workstation' /sys/class/dmi/id/product_name 2>/dev/null; then
      echo "system type: desktop" >> $output_file
else
    echo "unknown machine type" >> $output_file
fi

echo -e "\nchecking if disk is ssd or hdd" >> $output_file
for disk in /sys/block/sd* /sys/block/nvme*; do
    if [ -d "$disk" ]; then
        disk_name=$(basename "$disk")
        rotational_path="$disk/queue/rotational"
        if [ -f "$rotational_path" ]; then
            rotational=$(cat "$rotational_path")
            if [ "$rotational" -eq 0 ]; then
                echo "$disk_name: ssd" >> $output_file
            else
                echo "$disk_name: hdd" >> $output_file
            fi
        fi
    fi
done

echo -e "\nIpaddr info" >> $output_file
echo "addr:" >> $output_file
ip -4 addr show | grep -v "127.0.0.1" | grep inet >> $output_file
echo -e "\nISP ip: " >> $output_file
pub_ip=$(curl -s https://icanhazip.com)
echo "$pub_ip" >> $output_file

echo -e "\nproc info" >> $output_file
echo -e "\nTotal running procs: $(ps aux | wc -l)" >> $output_file

echo -e "\nUptime" >> $output_file
uptime >> $output_file

echo -e "\nCurrent users" >> $output_file
who | cut -d' ' -f1 | sort -u >> $output_file
echo -e "\n"

echo -e "\nHave a totally nice day my dear!, clear your browser history"
