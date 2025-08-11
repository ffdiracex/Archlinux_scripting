#!/usr/bin/env bash
# Features: sudo self-elevation, live + file logging, robust host/distro detection,
#           SSH key file inventory (no secrets printed), and graceful fallbacks.
#
# Requirements: bash, coreutils (tee, stat, find), iproute2 (ip), procps (free, uptime), util-linux (lsblk/df/swapon), nmap
# Optional: sudo, lsof, ethtool, iw, wireless_tools (iwconfig), nftables, iptables, ufw, firewalld, docker, podman, file, ssh-keygen

#NOTE: NEVER SHARE THE OUTPUT OF THIS AS IT PUTS YOUR SYSTEM AT RISK. Read the other files description for detailed risks.
#I hereby give the reader the responsibility of their actions, I shall not have the responsibility over their actions.
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

# --- Helpers ---
have() { command -v "$1" >/dev/null 2>&1; }
term_width() { printf '%s' "${COLUMNS:-$(stty size 2>/dev/null | awk '{print $2}')}" | grep -E '^[0-9]+$' >/dev/null || printf '%s' '80'; }
hr() { local w; w="$(term_width)"; printf '%s' '%*s\n' "$w" '' | tr ' ' -; }
section() { hr; printf "[SECTION] %s\n" "$1"; hr; }
pause() { echo; sleep 0.3; }

# --- Robust host & distro detection (no fragile commands) ---
HOSTNAME_FQDN="$(
  if have hostname; then hostname -f 2>/dev/null || hostname 2>/dev/null; \
  elif have uname; then uname -n 2>/dev/null; \
  else echo "unknown-host"; fi
)"

if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  . /etc/os-release
  DISTRO_NAME="${PRETTY_NAME:-${NAME:-${ID:-unknown}}}"
else
  DISTRO_NAME="unknown"
fi

# --- Logging: choose log dir, create file, and tee output ---
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEFAULT_LOG_DIR="/var/log/ultra-verbose-audit"
LOG_DIR="${AUDIT_LOG_DIR:-$DEFAULT_LOG_DIR}"

ensure_log_dir() {
  if mkdir -p "$LOG_DIR" 2>/dev/null && touch "$LOG_DIR/.write_test" 2>/dev/null; then
    rm -f "$LOG_DIR/.write_test" 2>/dev/null || true
    return 0
  fi
  LOG_DIR="./audit-logs"
  mkdir -p "$LOG_DIR"
}
ensure_log_dir
LOG_FILE="$LOG_DIR/audit_${HOSTNAME_FQDN}_${TIMESTAMP}.log"

# Start tee after we know the log path
exec > >(tee -a "$LOG_FILE") 2>&1

# --- Exit summary ---
cleanup() {
  echo
  section "SESSION SUMMARY"
  echo "[INFO] Log saved to: $LOG_FILE"
}
trap cleanup EXIT

# --- Intro banner ---
section "AUDIT START"
echo "[INFO] Host:             $HOSTNAME_FQDN"
echo "[INFO] Distro:           $DISTRO_NAME"
echo "[INFO] Started (UTC):    $TIMESTAMP"
echo "[INFO] Log path:         $LOG_FILE"
echo "[INFO] Note: SSH key inventory lists paths + safe metadata only; private key contents are never printed."
pause

# --- System overview ---
section "SYSTEM OVERVIEW"
echo "[INFO] Date & Time:        $(date -Is)"
echo "[INFO] Kernel:             $(uname -srmo)"
echo "[INFO] Uptime:             $(uptime -p || echo 'N/A')"
if have getenforce; then
  echo "[INFO] SELinux:            $(getenforce)"
else
  echo "[INFO] SELinux:            N/A"
fi
if have aa-status; then
  echo "[INFO] AppArmor profiles:  $(aa-status --profiled 2>/dev/null | wc -l) profiled"
else
  echo "[INFO] AppArmor:           N/A"
fi
pause

# --- Users & groups ---
section "USERS & GROUPS"
if have who; then echo "[INFO] Logged-in users:" && who || true; else echo "(who not found)"; fi
echo
if have last; then echo "[INFO] Last 5 logins:" && last -n 5 || true; else echo "(last not found)"; fi
echo
if have id; then echo "[INFO] Current user identity:" && id || true; else echo "(id not found)"; fi
pause

# --- CPU, memory, storage ---
section "CPU, MEMORY, STORAGE"
if have lscpu; then echo "[INFO] CPU info:" && lscpu || true; else echo "(lscpu not found)"; fi
echo
if have free; then echo "[INFO] Memory usage:" && free -h || true; else echo "(free not found)"; fi
echo
if have swapon; then echo "[INFO] Swap devices:" && swapon --show || true; else echo "(swapon not found)"; fi
echo
if have df; then echo "[INFO] Disk space usage:" && df -hT || true; else echo "(df not found)"; fi
pause

# --- Installed packages & updates (multi-distro friendly) ---
section "INSTALLED PACKAGES & UPDATES"
if have pacman; then
  echo "[INFO] Pacman pending updates:" && pacman -Qu || echo "(no updates or failed to check)"
elif have apt; then
  echo "[INFO] APT upgradable packages:" && apt list --upgradable 2>/dev/null || echo "(no updates or failed to check)"
elif have dnf; then
  echo "[INFO] DNF check-update:" && dnf -q check-update || echo "(no updates or failed to check)"
elif have zypper; then
  echo "[INFO] Zypper list-updates:" && zypper lu || echo "(no updates or failed to check)"
else
  echo "(no known package manager detected — skipping updates check)"
fi
pause

# --- Network: interfaces, IPs, routes ---
section "NETWORK INTERFACES & STATUS"
if have ip; then
  echo "[INFO] Interfaces (brief):" && ip -br link || true
  echo
  echo "[INFO] IP addresses (brief):" && ip -br addr || true
  echo
  echo "[INFO] Routing table (IPv4):" && ip -4 route show || true
  echo
  echo "[INFO] Routing table (IPv6):" && ip -6 route show || true
else
  echo "(ip command not found — skipping interface, address, and route details)"
fi
pause

# --- Neighbors (ARP/NDP) ---
section "NEIGHBORS (ARP/NDP)"
if have ip; then ip neigh show || true; else echo "(ip not found — skipping neighbors)"; fi
pause

# --- DNS configuration ---
section "DNS CONFIGURATION"
if have resolvectl; then
  echo "[INFO] resolvectl status:" && resolvectl status || true
else
  echo "(resolvectl not found — skipping systemd-resolved status)"
fi
echo
echo "[INFO] /etc/resolv.conf:"
if [[ -r /etc/resolv.conf ]]; then cat /etc/resolv.conf || true; else echo "(resolv.conf not readable)"; fi
pause

# --- Sockets & listening services ---
section "SOCKETS & LISTENING SERVICES"
if have ss; then
  echo "[INFO] Listening TCP/UDP sockets (ss):" && ss -tulpen || true
else
  echo "(ss not found — skipping socket summary)"
fi
echo
if have lsof; then
  echo "[INFO] Internet sockets (lsof):" && lsof -nP -i || true
else
  echo "(lsof not installed — skipping extended socket listing)"
fi
pause

# --- Firewall status ---
section "FIREWALL STATUS"
if have nft; then echo "[INFO] nftables ruleset:" && nft list ruleset || true; else echo "(nft not installed — skipping nftables ruleset)"; fi
echo
if have iptables; then echo "[INFO] iptables (IPv4):" && iptables -S || true; else echo "(iptables not installed — skipping IPv4 rules)"; fi
echo
if have ip6tables; then echo "[INFO] ip6tables (IPv6):" && ip6tables -S || true; else echo "(ip6tables not installed — skipping IPv6 rules)"; fi
echo
if have ufw; then echo "[INFO] UFW status:" && ufw status verbose || true; else echo "(ufw not installed — skipping UFW status)"; fi
echo
if have firewall-cmd; then echo "[INFO] firewalld state:" && firewall-cmd --state || true; else echo "(firewalld not installed — skipping firewalld state)"; fi
pause

# --- Link-layer / Ethernet ---
section "LINK-LAYER / ETHERNET"
if have ethtool; then
  for i in /sys/class/net/*; do
    [[ -e "$i" ]] || continue
    iface="$(basename "$i")"
    echo "[INFO] Interface: $iface"
    ethtool "$iface" || true
    echo
  done
else
  echo "(ethtool not installed — skipping Ethernet link details)"
fi
pause

# --- Wireless info ---
section "WIRELESS INFO"
if have iw; then echo "[INFO] Wi‑Fi devices (iw dev):" && iw dev || true; else echo "(iw not installed — skipping iw dev)"; fi
echo
if have iwconfig; then echo "[INFO] Wireless config (iwconfig):" && iwconfig || true; else echo "(iwconfig not installed — skipping iwconfig)"; fi
pause

# --- Container status ---
section "CONTAINER STATUS"
if have docker; then echo "[INFO] Docker containers:" && docker ps || true; else echo "(docker not installed — skipping Docker)"; fi
echo
if have podman; then echo "[INFO] Podman containers:" && podman ps || true; else echo "(podman not installed — skipping Podman)"; fi
pause

# --- SSH key files inventory (paths & metadata only; no private contents) ---
section "SSH KEY FILES INVENTORY (PATHS & METADATA ONLY)"
echo "[INFO] Host key files under /etc/ssh:"
shopt -s nullglob
host_key_candidates=(/etc/ssh/ssh_host_* /etc/ssh/*_key /etc/ssh/*_key.pub)
if (( ${#host_key_candidates[@]} )); then
  for f in "${host_key_candidates[@]}"; do
    [[ -e "$f" ]] || continue
    printf "[HOSTKEY] %s\n" "$f"
    if have stat; then
      stat -c "  perms=%A owner=%U group=%G size=%s bytes" "$f" 2>/dev/null || ls -l "$f"
    else
      ls -l "$f" || true
    fi
    if [[ "$f" == *.pub ]] && have ssh-keygen; then
      ssh-keygen -l -f "$f" || true
    else
      if have file; then file "$f" || true; fi
    fi
    echo
  done
else
  echo "(no host key files matched under /etc/ssh)"
fi
shopt -u nullglob
echo

echo "[INFO] User SSH key candidates in /root and /home (common filenames only):"
SSH_FIND_PATHS=()
[[ -d /root ]] && SSH_FIND_PATHS+=("/root")
[[ -d /home ]] && SSH_FIND_PATHS+=("/home")
if (( ${#SSH_FIND_PATHS[@]} )); then
  while IFS= read -r -d '' file; do
    printf "[USERKEY] %s\n" "$file"
    if have stat; then
      stat -c "  perms=%A owner=%U group=%G size=%s bytes" "$file" 2>/dev/null || ls -l "$file"
    else
      ls -l "$file" || true
    fi
    if [[ "$file" == *.pub ]] && have ssh-keygen; then
      ssh-keygen -l -f "$file" || true
    else
      if have file; then file "$file" || true; fi
    fi
    echo
  done < <(find "${SSH_FIND_PATHS[@]}" -maxdepth 4 -type f \( \
              -path "*/.ssh/*" -a \
              \( -name "id_*" -o -name "*.pub" -o -name "*.pem" -o -name "*.key" -o -name "*.cert" \) \
            \) -print0 2>/dev/null)
else
  echo "(no /root or /home directories to scan)"
fi
echo
echo "[INFO] Note: Only file paths and safe metadata are printed. Private key contents are never shown."
pause

# --- Localhost nmap scan ---
section "LOCALHOST NMAP SCAN"
if have nmap; then
  echo "[INFO] Performing nmap scan of localhost (127.0.0.1) — top 1000 TCP ports, verbose"
  nmap -vv -T4 127.0.0.1 || true
else
  echo "(nmap not installed — skipping localhost scan)"
fi
pause

# --- Audit complete ---
section "AUDIT COMPLETE"
echo "[INFO] Review above output for open ports, active services, and possible misconfigurations."
echo "[INFO] Finished at: $(date -Is)"

