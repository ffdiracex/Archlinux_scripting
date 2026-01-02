#!/bin/sh

# Get timestamp for filename
TS=$(date +%Y%m%d_%H%M%S)
OUTPUT="system_info_$TS.txt"

echo "System Information Report - $(date)" > "$OUTPUT"
echo "====================" >> "$OUTPUT"

# 1. Basic system info
echo "1. SYSTEM INFO" >> "$OUTPUT"
echo "--------------" >> "$OUTPUT"
[ -f /sys/devices/virtual/dmi/id/product_name ] && echo "Product: $(cat /sys/devices/virtual/dmi/id/product_name)" >> "$OUTPUT"
echo "Hostname: $(hostname)" >> "$OUTPUT"
echo "Kernel: $(uname -r)" >> "$OUTPUT"
echo "Architecture: $(uname -m)" >> "$OUTPUT"
[ -f /etc/os-release ] && grep -E '^(NAME|VERSION)=' /etc/os-release | sed 's/^/OS: /' | sed 's/"/ /g' >> "$OUTPUT"
echo "" >> "$OUTPUT"

# 2. CPU info
echo "2. CPU INFO" >> "$OUTPUT"
echo "-----------" >> "$OUTPUT"
if [ -f /proc/cpuinfo ]; then
    grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | sed 's/^[ \t]*//' >> "$OUTPUT"
    echo "Cores: $(grep -c processor /proc/cpuinfo)" >> "$OUTPUT"
    echo "CPU MHz: $(grep "cpu MHz" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)" >> "$OUTPUT"
fi
[ -f /sys/devices/system/cpu/online ] && echo "Online CPUs: $(cat /sys/devices/system/cpu/online)" >> "$OUTPUT"
[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ] && echo "Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)" >> "$OUTPUT"
[ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq ] && echo "Current freq: $(( $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq) / 1000 )) MHz" >> "$OUTPUT"
echo "" >> "$OUTPUT"

# 3. Memory info
echo "3. MEMORY INFO" >> "$OUTPUT"
echo "--------------" >> "$OUTPUT"
if [ -f /proc/meminfo ]; then
    grep -E "MemTotal|MemFree|MemAvailable|SwapTotal|SwapFree" /proc/meminfo | while read line; do
        name=$(echo "$line" | cut -d: -f1)
        value=$(echo "$line" | awk '{print $2}')
        echo "$name: $((value / 1024)) MB" >> "$OUTPUT"
    done
fi
echo "" >> "$OUTPUT"

# 4. Disk info
echo "4. DISK INFO" >> "$OUTPUT"
echo "------------" >> "$OUTPUT"
df -h 2>/dev/null | grep -v "tmpfs\|udev\|/dev/loop" | head -10 >> "$OUTPUT"
echo "" >> "$OUTPUT"

# 5. Network info
echo "5. NETWORK INFO" >> "$OUTPUT"
echo "---------------" >> "$OUTPUT"
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    [ "$iface_name" = "lo" ] && continue
    
    echo "Interface: $iface_name" >> "$OUTPUT"
    [ -f "$iface/address" ] && echo "  MAC: $(cat "$iface/address")" >> "$OUTPUT"
    [ -f "$iface/operstate" ] && echo "  State: $(cat "$iface/operstate")" >> "$OUTPUT"
    [ -f "$iface/speed" ] && echo "  Speed: $(cat "$iface/speed") Mbps" >> "$OUTPUT"
done
echo "" >> "$OUTPUT"

# 6. Temperature sensors
echo "6. TEMPERATURE" >> "$OUTPUT"
echo "--------------" >> "$OUTPUT"
if [ -d /sys/class/thermal ]; then
    for zone in /sys/class/thermal/thermal_zone*; do
        [ -f "$zone/temp" ] && [ -f "$zone/type" ] && \
        echo "$(cat "$zone/type"): $(( $(cat "$zone/temp") / 1000 ))°C" >> "$OUTPUT"
    done
fi
echo "" >> "$OUTPUT"

# 7. USB devices
echo "7. USB DEVICES" >> "$OUTPUT"
echo "--------------" >> "$OUTPUT"
if [ -d /sys/bus/usb/devices ]; then
    for dev in /sys/bus/usb/devices/usb*; do
        [ -f "$dev/product" ] && echo "USB: $(cat "$dev/product" 2>/dev/null)" >> "$OUTPUT"
    done
fi
echo "" >> "$OUTPUT"

# 8. Load and uptime
echo "8. SYSTEM LOAD" >> "$OUTPUT"
echo "--------------" >> "$OUTPUT"
uptime >> "$OUTPUT"
[ -f /proc/loadavg ] && echo "Load avg: $(cat /proc/loadavg)" >> "$OUTPUT"
echo "" >> "$OUTPUT"

# 9. Kernel info from /proc
echo "9. KERNEL INFO" >> "$OUTPUT"
echo "--------------" >> "$OUTPUT"
[ -f /proc/version ] && echo "Version: $(cat /proc/version)" >> "$OUTPUT"
[ -f /proc/cmdline ] && echo "Cmdline: $(cat /proc/cmdline)" >> "$OUTPUT"
[ -f /proc/sys/kernel/hostname ] && echo "Hostname (from /proc): $(cat /proc/sys/kernel/hostname)" >> "$OUTPUT"
echo "" >> "$OUTPUT"

# 10. Block devices
echo "10. BLOCK DEVICES" >> "$OUTPUT"
echo "-----------------" >> "$OUTPUT"
for device in /sys/block/*; do
    dev_name=$(basename "$device")
    [ -f "$device/size" ] && size=$(cat "$device/size") && \
    echo "$dev_name: $((size * 512 / 1024 / 1024 / 1024)) GB" >> "$OUTPUT"
done
echo "" >> "$OUTPUT"

echo "Report saved to: $OUTPUT"