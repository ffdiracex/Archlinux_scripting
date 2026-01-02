#!/bin/sh

# Minimal system info script
OUTPUT="sysinfo_$(date +%s).txt"

{
echo "=== SYSTEM INFO $(date) ==="

# CPU
[ -f /proc/cpuinfo ] && {
    echo "CPU: $(grep 'model name' /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)"
    echo "Cores: $(grep -c processor /proc/cpuinfo)"
}

# Memory
[ -f /proc/meminfo ] && {
    mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    echo "Memory: $((mem / 1024)) MB"
}

# Disk
df -h 2>/dev/null | grep '^/dev/' | head -5

# Network
for iface in /sys/class/net/*; do
    [ -f "$iface/address" ] && [ "$(basename "$iface")" != "lo" ] && \
    echo "Net: $(basename "$iface") $(cat "$iface/address")"
done

# Temperature
[ -d /sys/class/thermal ] && for zone in /sys/class/thermal/thermal_zone*; do
    [ -f "$zone/temp" ] && echo "Temp: $(( $(cat "$zone/temp") / 1000 ))°C"
done

# Uptime
uptime
} > "$OUTPUT"

echo "Saved to $OUTPUT"