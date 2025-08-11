#!/usr/bin/env bash
#more verbose version of netinfo.sh -- reveals more information on the surrounding packets & configs (.conf  & .route directories & status)
#NOTE: NEVER share the output of this script, it puts you and your system at great risk. 
#I HEREBY GIVE THE READER THE RESPONSIBILITY OF THEIR ACTIONS, I SHALL NOT TAKE RESPONSIBILITY FOR WHAT THEY PLAN TO DO. with great power comes great responsibility

#@Copyright ffdiracex@github bashscripter123@gmail.com  

set -euo pipefail

# Self-escalate to root
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    echo "Re-executing with sudo..."
    exec sudo -E -- bash "$0" "$@"
  else
    echo "This script requires root (sudo not found). Try: su -c '$0 $*'" >&2
    exit 1
  fi
fi

# Style
if [[ -t 1 ]]; then
  BOLD="$(printf '\033[1m')"; DIM="$(printf '\033[2m')"; RESET="$(printf '\033[0m')"
else
  BOLD=""; DIM=""; RESET=""
fi

have() { command -v "$1" >/dev/null 2>&1; }
hr() { printf '%s\n' "--------------------------------------------------------------------------------"; }
section() { hr; printf '%s%s%s\n' "$BOLD" "$*" "$RESET"; hr; }
sub() { printf '%s%s%s\n' "$DIM" "$*" "$RESET"; }

# Redaction (best-effort masking)
FILTER_CMD="cat"
if [[ "${REDACT:-0}" == "1" ]]; then
  FILTER_CMD="sed -E \
    -e 's/([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}/XX:XX:XX:XX:XX:XX/g' \
    -e 's/([0-9]{1,3}\.){3}[0-9]{1,3}/X.X.X.X/g' \
    -e 's/([0-9A-Fa-f]{0,4}:){2,7}[0-9A-Fa-f]{0,4}/xxxx:xxxx::xxxx/g'"
fi

run() {
  local title="$1"; shift
  section "$title"
  if [[ $# -eq 0 ]]; then echo "(no command)"; echo; return; fi
  # shellcheck disable=SC2068
  bash -lc "$*" 2>&1 | eval "$FILTER_CMD" || true
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

# Header and context
section "System overview"
echo "Date:            $(date -Is)"
echo "Hostname:        $(hostname -f 2>/dev/null || hostname)"
echo "Kernel:          $(uname -srmo)"
echo "SELinux:         $(getenforce 2>/dev/null || echo 'N/A')"
echo "AppArmor:        $(aa-status --profiled 2>/dev/null | head -n1 || echo 'N/A')"
echo "Open files limit: $(ulimit -n 2>/dev/null || true)"
echo
if have hostnamectl; then sub "hostnamectl"; hostnamectl || true; echo; fi

# Kernel and stack internals
run "Kernel ring buffer (network-related dmesg)" "dmesg -T | grep -iE 'net|eth|en[0-9]|wl|mtu|tcp|udp|link|nic|ixgbe|mlx|bond|team' || true"
run "Journal (last boot, network)" "journalctl -b -t kernel -g 'net\\|eth\\|wlan\\|link\\|tcp\\|udp' --no-pager || true"
run "Network sysctls (all net.*)" "sysctl -a | grep -E '^net\\.'"
info_if_present "nstat counters (iproute2)" "nstat -az 2>/dev/null || true"
run "/proc/net stats (snmp, netstat, sockstat)" "for f in snmp snmp6 netstat sockstat sockstat6 softnet_stat dev; do echo '###' /proc/net/\$f; cat /proc/net/\$f; echo; done"

# Interfaces, drivers, and link-layer details
run "Interfaces (detailed + stats)" "ip -d -s link show"
run "IP addresses (detailed)" "ip -d -s addr show"
info_if_present "Ethernet features (all ifaces)" "for i in \$(ls /sys/class/net); do echo; echo '###' \$i; ethtool -k \$i 2>/dev/null; done"
info_if_present "Ethernet stats (all ifaces)" "for i in \$(ls /sys/class/net); do echo; echo '###' \$i; ethtool -S \$i 2>/dev/null; done"
info_if_present "Pause/flow control (all ifaces)" "for i in \$(ls /sys/class/net); do echo; echo '###' \$i; ethtool -a \$i 2>/dev/null; done"

# VLANs, bridges, bonding
info_if_present "Bridges: link and forwarding DB" "bridge link show; echo; bridge fdb show 2>/dev/null || true; echo; bridge vlan show 2>/dev/null || true"
run "Bond/team interfaces (if any)" "grep -R . /proc/net/bonding 2>/dev/null || echo 'No bonding detected.'"

# Routing, policy routing, multicast
run "IPv4/IPv6 routes (all tables)" "ip -4 route show table all; echo; ip -6 route show table all"
run "Routing rules" "ip rule show"
run "Multicast (group membership + routes)" "ip maddress show; echo; ip mroute show 2>/dev/null || true"

# Neighbors and ARP/NDP
run "Neighbors (ARP/NDP) with stats" "ip -s neigh show"

# DNS and name resolution
if have resolvectl; then
  run "DNS status (resolvectl)" "resolvectl status"
  run "DNS stats (resolvectl)" "resolvectl statistics || true"
elif have systemd-resolve; then
  run "DNS status (systemd-resolve)" "systemd-resolve --status"
fi
run "/etc/resolv.conf" "cat /etc/resolv.conf"
run "nsswitch.conf (non-comment lines)" "grep -v '^[[:space:]]*#' /etc/nsswitch.conf || true"
info_if_present "dig diagnostics (root + search)" "dig +timeout=2 +tries=1 example.com A; echo; dig +timeout=2 +tries=1 @127.0.0.1 localhost A"

# Socket and port visibility
run "Listening sockets (TCP/UDP) with processes" "ss -tulpenH"
run "All TCP connections with processes" "ss -pantH"
run "All UDP sockets with processes" "ss -pauH"
run "UNIX domain sockets (listening and connected)" "ss -xapH"
info_if_present "lsof: internet sockets" "lsof -nP -i"
info_if_present "lsof: UNIX sockets" "lsof -nP -U"
run "Socket summary and memory" "ss -s; echo; ss --memory || true"
if [[ "${DEEP:-0}" == "1" ]]; then
  run "TCP internals for established sockets (sample)" "ss -ti state established | head -n 500"
fi

# Firewall and packet filtering
info_if_present "nftables ruleset (with handles)" "nft list ruleset -a"
info_if_present "iptables-save (IPv4)" "iptables-save"
info_if_present "ip6tables-save (IPv6)" "ip6tables-save"
info_if_present "UFW status" "ufw status verbose"
if have firewall-cmd; then
  run "firewalld: state and zones" "firewall-cmd --state; echo; firewall-cmd --get-active-zones; echo; firewall-cmd --list-all"
fi
info_if_present "Conntrack stats" "conntrack -S"
if [[ "${DEEP:-0}" == "1" ]] && have conntrack; then
  run "Conntrack table (DEEP mode, can be huge)" "conntrack -L || true"
fi

# QoS and traffic control
info_if_present "qdisc and class stats (all interfaces)" "for i in \$(ls /sys/class/net); do echo; echo '###' \$i; tc -s qdisc show dev \$i 2>/dev/null; tc -s class show dev \$i 2>/dev/null; tc -s filter show dev \$i 2>/dev/null; done"

# Wireless diagnostics
if have iw; then
  run "Wi‑Fi devices (iw)" "iw dev"
  run "Wi‑Fi capabilities (iw list)" "iw list"
  for w in $(iw dev 2>/dev/null | awk '/Interface/ {print $2}'); do
    run "Wi‑Fi link status ($w)" "iw dev $w link"
    run "Wi‑Fi stations ($w)" "iw dev $w station dump"
    run "Wi‑Fi survey ($w)" "iw dev $w survey dump"
  done
fi
info_if_present "Wireless config (iwconfig)" "iwconfig"

# Network managers
if have nmcli; then
  run "NetworkManager: general status" "nmcli general status"
  run "NetworkManager: devices" "nmcli -f DEVICE,TYPE,STATE,CONNECTION dev status"
  run "NetworkManager: device details" "nmcli -g all device show"
  run "NetworkManager: connections (details)" "nmcli -g all connection show"
fi
if systemctl list-unit-files 2>/dev/null | grep -q '^systemd-networkd.service'; then
  run "systemd-networkd: links" "networkctl list"
  run "systemd-networkd: status (all)" "networkctl status --all"
  run "systemd-networkd logs (this boot)" "journalctl -u systemd-networkd -b --no-pager"
fi

# Systemd sockets and services listening
if have systemctl; then
  run "Systemd socket units (active)" "systemctl list-sockets"
  run "Network-related units (active)" "systemctl list-units | grep -Ei 'network|dhcp|dns|wg|openvpn|firewalld|ssh|cups|smb|nfs' || true"
fi

# Containers and namespaces
if have lsns; then
  run "Network namespaces" "lsns -t net"
fi
if have ip; then
  NS_LIST="$(ip netns list 2>/dev/null | awk '{print $1}')"
  if [[ -n "${NS_LIST}" ]]; then
    for ns in ${NS_LIST}; do
      run "Netns [$ns]: addresses and routes" "ip -n $ns addr; echo; ip -n $ns -4 route; echo; ip -n $ns -6 route"
      if [[ "${DEEP:-0}" == "1" ]]; then
        info_if_present "Netns [$ns]: sockets (DEEP)" "ip netns exec $ns ss -tulpenH"
      fi
    done
  fi
fi
if have docker; then
  run "Docker networks" "docker network ls"
  run "Docker network inspect (all)" "for n in \$(docker network ls --format '{{.Name}}'); do echo; echo '###' \$n; docker network inspect \$n; done"
  run "Docker containers (ports)" "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'"
fi
if have podman; then
  run "Podman networks" "podman network ls"
  run "Podman containers (ports)" "podman ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}'"
fi

# Hosts and local overrides
run "/etc/hosts" "cat /etc/hosts"
run "/etc/hosts.allow (legacy)" "test -f /etc/hosts.allow && cat /etc/hosts.allow || echo 'Not present.'"
run "/etc/hosts.deny (legacy)" "test -f /etc/hosts.deny && cat /etc/hosts.deny || echo 'Not present.'"

section "Done"
echo "Note: Output is sensitive. Consider REDACT=1 if you need to share it."
