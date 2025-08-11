#!/usr/bin/env bash
# Requirements: bash, sudo, coreutils, iproute2, procps, util-linux, net-tools, nmap
# Optional: lsof, ethtool, iw, wireless_tools, nftables, iptables, ufw, firewalld, docker, podman
#NOTE: You are responsible for what YOU DO with the output on this.

#@Copyright ffdiracex@github  bashscripter123@gmail.com 

set -euo pipefail

# --- Sudo self‑elevation ---
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "[INFO] Not root. Relaunching with sudo..."
    exec sudo -E -- bash "$0" "$@"
  else
    echo "[ERROR] Script requires root. Install sudo or run as root."
    exit 1
  fi
fi

# --- Pretty printing helpers ---
have() { command -v "$1" >/dev/null 2>&1; }
hr() { printf '%*s\n' "$(tput cols 2>/dev/null || echo 80)" '' | tr ' ' -; }
section() { hr; printf "[SECTION] %s\n" "$1"; hr; }
pause() { echo; sleep 0.5; }

# --- Start audit ---
section "SYSTEM OVERVIEW"
echo "[INFO] Date & Time:        $(date -Is)"
echo "[INFO] Hostname (FQDN):    $(hostname -f 2>/dev/null || hostname)"
. /etc/os-release 2>/dev/null || true
echo "[INFO] OS:                 ${PRETTY_NAME:-unknown}"
echo "[INFO] Kernel:             $(uname -srmo)"
echo "[INFO] Uptime:             $(uptime -p)"
pause

section "USERS & GROUPS"
echo "[INFO] Currently logged in users:"
who
echo
echo "[INFO] Last logins:"
last -n 5
echo
echo "[INFO] Group memberships for current user:"
id
pause

section "CPU, MEMORY, STORAGE"
echo "[INFO] CPU info:"
lscpu
echo
echo "[INFO] Memory usage:"
free -h
echo
echo "[INFO] Swap usage:"
swapon --show
echo
echo "[INFO] Disk space usage:"
df -hT
pause

section "INSTALLED PACKAGES & UPDATES"
if have pacman; then
  echo "[INFO] Pacman pending updates:"
  pacman -Qu || echo "(no updates or failed to check)"
fi
pause

section "NETWORK INTERFACES & STATUS"
echo "[INFO] Interfaces (brief):"
ip -br link
echo
echo "[INFO] IP addresses (brief):"
ip -br addr
echo
echo "[INFO] Routing table (IPv4):"
ip -4 route show
echo
echo "[INFO] Routing table (IPv6):"
ip -6 route show
pause

section "NEIGHBORS (ARP/NDP)"
ip neigh show
pause

section "DNS CONFIGURATION"
if have resolvectl; then
  echo "[INFO] resolvectl status:"
  resolvectl status
fi
echo
echo "[INFO] /etc/resolv.conf:"
cat /etc/resolv.conf
pause

section "SOCKETS & LISTENING SERVICES"
echo "[INFO] Listening TCP/UDP sockets (ss):"
ss -tulpen
echo
if have lsof; then
  echo "[INFO] Internet sockets (lsof):"
  lsof -nP -i
fi
pause

section "FIREWALL STATUS"
if have nft; then nft list ruleset; fi
if have iptables; then iptables -S; fi
if have ip6tables; then ip6tables -S; fi
if have ufw; then ufw status verbose; fi
if have firewall-cmd; then firewall-cmd --state; fi
pause

section "LINK-LAYER / ETHERNET"
if have ethtool; then
  for i in /sys/class/net/*; do
    iface=$(basename "$i")
    echo "[INFO] Interface: $iface"
    ethtool "$iface" || true
    echo
  done
else
  echo "(ethtool not installed — skipping)"
fi
pause

section "WIRELESS INFO"
if have iw; then iw dev; fi
if have iwconfig; then iwconfig; fi
pause

section "CONTAINER STATUS"
if have docker; then docker ps; fi
if have podman; then podman ps; fi
pause

section "LOCALHOST NMAP SCAN"
if have nmap; then
  echo "[INFO] Performing nmap scan of localhost (127.0.0.1) — top 1000 TCP ports"
  nmap -vv -T4 127.0.0.1
else
  echo "(nmap not installed — skipping localhost scan)"
fi
pause

section "AUDIT COMPLETE"
echo "[INFO] Review above output for open ports, active services, and possible misconfigurations."
