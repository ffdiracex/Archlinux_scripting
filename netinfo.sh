#!/usr/bin/env bash
#netinfo.sh
#network and socket information echoes, port activity and much more. If VPN / firewall is running, their configuration and activity will be listed. 
#note: NEVER share these outputs as they put your systems security at risk, main risks with sharing output:
 #1. Host & OS Fingerprinting, 2.Service & port visibility: could point directly to exploitable software or weak configurations
 #3.DNS & routing insight: 1.DNS resolver and IPs and search domains might reveal your ISP, organization name, or internal namespace
 #4. custom /etc/hosts entries & proxy settings may disclose internal systems / private services. Environmental variables might LEAK CREDENTIALS if misconfigured.

# WITH GREAT POWER COMES GREAT RESPONSIBILITY, I Hereby give the viewer the responsibility of their actions, I shall not take responsibility for others doings and actions.
# @COPYRIGHT ffdiracex@github bashscripter123@gmail.com  LICENSE: MIT LICENSE     WRITTEN ON 11th august 2025

set -euo pipefail

# Require root (self-escalate with sudo)
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "Re-executing with sudo..."
    exec sudo -E -- bash "$0" "$@"
  else
    echo "This script requires root, and sudo is not installed." >&2
    echo "Install sudo or run: su -c '$0 $*'" >&2
    exit 1
  fi
fi

# Colors (disable if not a TTY)
if [[ -t 1 ]]; then
  BOLD="$(printf '\033[1m')"; DIM="$(printf '\033[2m')"; RESET="$(printf '\033[0m')"
else
  BOLD=""; DIM=""; RESET=""
fi

have() { command -v "$1" >/dev/null 2>&1; }
hr() { printf '%s\n' "--------------------------------------------------------------------------------"; }
section() { hr; printf '%s%s%s\n' "$BOLD" "$*" "$RESET"; hr; }
subsection() { printf '%s%s%s\n' "$DIM" "$*" "$RESET"; }

run() {
  local title="$1"; shift
  section "$title"
  if [[ $# -eq 0 ]]; then
    echo "(no command provided)"; echo; return
  fi
  bash -lc "$*" || true
  echo
}

info_if_present() {
  local title="$1"; shift
  local cmd="$*"
  local bin="${1%% *}"
  if have "$bin"; then
    run "$title" "$cmd"
  fi
}

# Header
section "System overview"
echo "Date:       $(date -Is)"
echo "Hostname:   $(hostname -f 2>/dev/null || hostname)"
if have hostnamectl; then
  echo
  subsection "hostnamectl"
  hostnamectl || true
fi
echo

# Interfaces and IP addressing
info_if_present "Interfaces (brief)" "ip -br link"
info_if_present "IP addresses (brief)" "ip -br addr"
info_if_present "IPv4 routes" "ip -4 route show table all"
info_if_present "IPv6 routes" "ip -6 route show table all"
info_if_present "Routing rules" "ip rule show"

# DNS and name resolution
if have resolvectl; then
  run "DNS and name resolution (resolvectl)" "resolvectl status"
elif have systemd-resolve; then
  run "DNS and name resolution (systemd-resolve)" "systemd-resolve --status"
fi
run "resolv.conf" "cat /etc/resolv.conf"
run "nsswitch.conf" "grep -v '^[[:space:]]*#' /etc/nsswitch.conf || true"

# Proxy environment
section "Proxy environment variables"
env | grep -iE '^(http|https|ftp|all|no)_proxy=' || echo "No proxy variables set."
echo

# Socket and port information
info_if_present "Listening sockets with processes (ss)" "ss -tulpen"
info_if_present "All TCP connections with processes (ss)" "ss -pant"
if have lsof; then
  run "Open internet sockets (lsof)" "lsof -nP -i"
fi
if have netstat; then
  run "netstat (if installed)" "netstat -tulpen"
fi
info_if_present "Socket statistics" "ss -s"

# ARP/Neighbors
info_if_present "Neighbors (ARP/NDP)" "ip neigh show"
if have arp; then
  run "ARP table (net-tools)" "arp -an"
fi

# Wireless (if applicable)
if have iw; then
  run "Wi‑Fi devices (iw)" "iw dev"
  run "Wi‑Fi capabilities (iw list)" "iw list"
fi
if have iwconfig; then
  run "Wireless config (iwconfig)" "iwconfig"
fi
if have nmcli; then
  run "Wi‑Fi scan (nmcli)" "nmcli -f IN-USE,SSID,BSSID,CHAN,RATE,SIGNAL,SECURITY dev wifi list"
fi

# NetworkManager (if present)
if have nmcli; then
  run "NetworkManager: general status" "nmcli general status"
  run "NetworkManager: devices" "nmcli -f DEVICE,TYPE,STATE,CONNECTION dev status"
  run "NetworkManager: connections" "nmcli -f NAME,UUID,TYPE,DEVICE con show"
fi

# systemd-networkd (if present)
if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-networkd.service'; then
  run "systemd-networkd: links" "networkctl list"
  run "systemd-networkd: status (verbose)" "networkctl status --all"
fi

# Firewall and packet filtering
if have nft; then
  run "nftables ruleset" "nft list ruleset"
fi
if have iptables; then
  run "iptables (IPv4 filter)" "iptables -S"
  run "iptables NAT (IPv4)" "iptables -t nat -S"
fi
if have ip6tables; then
  run "ip6tables (IPv6 filter)" "ip6tables -S"
  run "ip6tables NAT (IPv6)" "ip6tables -t nat -S"
fi
if have ufw; then
  run "UFW status" "ufw status verbose"
fi
if have firewall-cmd; then
  run "firewalld: active state" "firewall-cmd --state"
  run "firewalld: current config" "firewall-cmd --list-all"
  run "firewalld: permanent config" "firewall-cmd --permanent --list-all"
fi

# Important kernel networking settings
if have sysctl; then
  section "Selected kernel networking sysctls"
  sysctl net.ipv4.ip_forward 2>/dev/null || true
  sysctl net.ipv6.conf.all.forwarding 2>/dev/null || true
  sysctl net.ipv4.conf.all.rp_filter 2>/dev/null || true
  sysctl net.core.somaxconn 2>/dev/null || true
  sysctl net.core.netdev_max_backlog 2>/dev/null || true
  echo
fi

# Hosts and local overrides
run "/etc/hosts" "cat /etc/hosts"
run "/etc/hosts.allow (tcpwrappers, legacy)" "test -f /etc/hosts.allow && cat /etc/hosts.allow || echo 'Not present.'"
run "/etc/hosts.deny (tcpwrappers, legacy)" "test -f /etc/hosts.deny && cat /etc/hosts.deny || echo 'Not present.'"

# Services listening on ports (systemd)
if have systemctl; then
  run "Systemd units (network-related, active)" "systemctl list-units | grep -Ei 'network|dhcp|dns|wg|openvpn|firewalld|ssh|cups|smb|nfs' || true"
fi

# VPNs (if present)
if have wg; then
  run "WireGuard status" "wg show"
fi
if have openvpn; then
  run "OpenVPN processes" "ps -eo pid,cmd | grep -E '[o]penvpn' || true"
fi
if have tailscale; then
  run "Tailscale status" "tailscale status"
fi
if have zerotier-cli; then
  run "ZeroTier status" "zerotier-cli info && zerotier-cli listnetworks"
fi

# Containers (if present)
if have docker; then
  run "Docker networks" "docker network ls"
  run "Docker network inspect (all)" "for n in \$(docker network ls --format '{{.Name}}'); do echo; echo '###' \$n; docker network inspect \$n; done"
  run "Docker containers (ports)" "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'"
fi
if have podman; then
  run "Podman networks" "podman network ls"
  run "Podman containers (ports)" "podman ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'"
fi

# Multicast and IGMP
info_if_present "Multicast group membership" "ip maddress show"

# Extra diagnostics if available
if have ethtool; then
  run "Ethernet link info (all interfaces)" "for i in \$(ls /sys/class/net); do echo; echo '###' \$i; ethtool \$i || true; done"
fi
if have tcpdump; then
  run "tcpdump capture interfaces" "tcpdump -D"
fi
if have ss; then
  run "Per-process listening ports (condensed)" "ss -tulpen | awk 'NR>1 {print \$1, \$5, \$7}' | sort -u"
fi

section "Done"
echo "Tip: You ran as root; full process/port details should be visible."
