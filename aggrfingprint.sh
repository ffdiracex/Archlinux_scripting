#!/usr/bin/env bash
# Features:
#   - sudo self-elevation
#   - live + file logging (timestamped)
#   - robust host/distro detection (works without hostname)
#   - SSH key inventory (paths + safe metadata; never prints private key contents -- legal considerations)
#   - controllers/drivers/displays fingerprinting (PCI/USB/DRM)
#   - storage & RAID/LVM/ZFS/Btrfs overview
#   - kernel modules & key security sysctls
#   - services/timers/time sync/log health
#   - localhost nmap with service fingerprinting (non penetrative, add -Pn -O for OS-fingerprinting)
#
# Requirements (core): bash, coreutils (tee, stat, find), iproute2 (ip), procps (free, uptime, sysctl), util-linux (df, swapon, lsblk, mount)
# Optional (auto-detected): sudo, lscpu, lspci, lsusb, dmidecode, ethtool, iw, iwconfig, nft, iptables/ip6tables, ufw, firewall-cmd,
#                           docker, podman, file, ssh-keygen, smartctl, mdadm, lvm (pvdisplay/vgdisplay/lvdisplay), zpool/zfs, btrfs,
#                           efibootmgr, bootctl, systemctl, journalctl, timedatectl, chronyc, ntpq, rfkill, xrandr, glxinfo, nmap
#NOTE: READ THE README.md FOR THE LEGAL CONSIDERATIONS
# @Copyright ffdiracex@github  bashscripter123@gmail.com


set -euo pipefail

# --- Sudo self-elevation ---
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
term_width() { printf '%s' "${COLUMNS:-$(stty size 2>/dev/null | awk '{print $2}')}" | grep -Eq '^[0-9]+$' || printf '80'; }
hr() { local w; w="$(term_width)"; printf '%s' '%*s\n' "$w" '' | tr ' ' -; }
section() { hr; printf "[SECTION] %s\n" "$1"; hr; }
pause() { echo; sleep 0.25; }

# --- Robust host & distro detection ---
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

# --- Logging config ---
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEFAULT_LOG_DIR="/var/log/ultra-verbose-audit"
LOG_DIR="${AUDIT_LOG_DIR:-$DEFAULT_LOG_DIR}"
ensure_log_dir() {
  if mkdir -p "$LOG_DIR" 2>/dev/null && touch "$LOG_DIR/.write_test" 2>/dev/null; then
    rm -f "$LOG_DIR/.write_test" 2>/dev/null || true
  else
    LOG_DIR="./audit-logs"; mkdir -p "$LOG_DIR"
  fi
}
ensure_log_dir
LOG_FILE="$LOG_DIR/audit_${HOSTNAME_FQDN}_${TIMESTAMP}.log"

# Start tee after log path known
exec > >(tee -a "$LOG_FILE") 2>&1

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
echo "[WARN] This audit exposes identifying hardware details (serials/UUIDs) if available. Handle logs securely."
pause

# --- System overview ---
section "SYSTEM OVERVIEW"
echo "[INFO] Date & Time:        $(date -Is)"
echo "[INFO] Kernel:             $(uname -srmo)"
echo "[INFO] Uptime:             $(uptime -p || echo 'N/A')"
if have getenforce; then echo "[INFO] SELinux:            $(getenforce)"; else echo "[INFO] SELinux:            N/A"; fi
if have aa-status; then echo "[INFO] AppArmor profiles:  $(aa-status --profiled 2>/dev/null | wc -l) profiled"; else echo "[INFO] AppArmor:           N/A"; fi
if have systemd-detect-virt; then echo "[INFO] Virtualization:     $(systemd-detect-virt || true)"; fi
if have sysctl; then echo "[INFO] Kernel cmdline:     $(cat /proc/cmdline 2>/dev/null || echo 'N/A')"; fi
pause

# --- Users & groups ---
section "USERS & GROUPS"
if have who; then echo "[INFO] Logged-in users:" && who || true; else echo "(who not found)"; fi
echo
if have last; then echo "[INFO] Last 5 logins:" && last -n 5 || true; else echo "(last not found)"; fi
echo
if have id; then echo "[INFO] Current user identity:" && id || true; else echo "(id not found)"; fi
pause

# --- CPU, memory, storage basics ---
section "CPU, MEMORY, STORAGE"
if have lscpu; then echo "[INFO] CPU info:" && lscpu || true; else echo "(lscpu not found)"; fi
echo
if have free; then echo "[INFO] Memory usage:" && free -h || true; else echo "(free not found)"; fi
echo
if have swapon; then echo "[INFO] Swap devices:" && swapon --show || true; else echo "(swapon not found)"; fi
echo
if have df; then echo "[INFO] Disk space usage:" && df -hT || true; else echo "(df not found)"; fi
pause

# --- Installed packages & updates ---
section "INSTALLED PACKAGES & UPDATES"
if have pacman; then echo "[INFO] Pacman pending updates:" && pacman -Qu || echo "(no updates or failed to check)"
elif have apt; then echo "[INFO] APT upgradable packages:" && apt list --upgradable 2>/dev/null || echo "(no updates or failed to check)"
elif have dnf; then echo "[INFO] DNF check-update:" && dnf -q check-update || echo "(no updates or failed to check)"
elif have zypper; then echo "[INFO] Zypper list-updates:" && zypper lu || echo "(no updates or failed to check)"
else echo "(no known package manager detected — skipping updates check)"; fi
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
if have resolvectl; then echo "[INFO] resolvectl status:" && resolvectl status || true; else echo "(resolvectl not found — skipping)"; fi
echo
echo "[INFO] /etc/resolv.conf:"; if [[ -r /etc/resolv.conf ]]; then cat /etc/resolv.conf || true; else echo "(resolv.conf not readable)"; fi
pause

# --- Sockets & listening services ---
section "SOCKETS & LISTENING SERVICES"
if have ss; then echo "[INFO] Listening TCP/UDP sockets (ss):" && ss -tulpen || true; else echo "(ss not found — skipping)"; fi
echo
if have lsof; then echo "[INFO] Internet sockets (lsof):" && lsof -nP -i || true; else echo "(lsof not installed — skipping)"; fi
pause

# --- Firewall status ---
section "FIREWALL STATUS"
if have nft; then echo "[INFO] nftables ruleset:" && nft list ruleset || true; else echo "(nft not installed — skipping nftables rules)"; fi
echo
if have iptables; then echo "[INFO] iptables (IPv4):" && iptables -S || true; else echo "(iptables not installed — skipping IPv4 rules)"; fi
echo
if have ip6tables; then echo "[INFO] ip6tables (IPv6):" && ip6tables -S || true; else echo "(ip6tables not installed — skipping IPv6 rules)"; fi
echo
if have ufw; then echo "[INFO] UFW status:" && ufw status verbose || true; else echo "(ufw not installed — skipping UFW status)"; fi
echo
if have firewall-cmd; then echo "[INFO] firewalld state:" && firewall-cmd --state || true; else echo "(firewalld not installed — skipping)"; fi
pause

# --- Link-layer / Ethernet (driver/firmware/features/stats) ---
section "LINK-LAYER / ETHERNET (DRIVERS, FEATURES, STATS)"
if have ethtool; then
  for p in /sys/class/net/*; do
    [[ -e "$p" ]] || continue
    iface="$(basename "$p")"
    echo "[INFO] Interface: $iface"
    if have ethtool; then
      echo "  - driver/firmware:"; ethtool -i "$iface" || true
      echo "  - features:"; ethtool -k "$iface" || true
      echo "  - stats (top lines):"; ethtool -S "$iface" | head -n 50 || true
    fi
    echo
  done
else
  echo "(ethtool not installed — skipping Ethernet driver/feature details)"
fi
pause

# --- Wireless info ---
section "WIRELESS INFO"
if have rfkill; then echo "[INFO] RFKill status:" && rfkill list || true; fi
if have iw; then echo "[INFO] Wi‑Fi devices (iw dev):" && iw dev || true; else echo "(iw not installed — skipping iw dev)"; fi
echo
if have iw; then echo "[INFO] Capabilities (iw list):" && iw list || true; fi
if have iwconfig; then echo "[INFO] Wireless config (iwconfig):" && iwconfig || true; else echo "(iwconfig not installed — skipping)"; fi
pause

# --- SSH key files inventory (paths & metadata only; no private contents) ---
section "SSH KEY FILES INVENTORY (PATHS & METADATA ONLY)"
echo "[INFO] Host key files under /etc/ssh:"
shopt -s nullglob
host_key_candidates=(/etc/ssh/ssh_host_* /etc/ssh/*_key /etc/ssh/*_key.pub)
if (( ${#host_key_candidates[@]} )); then
  for f in "${host_key_candidates[@]}"; do
    [[ -e "$f" ]] || continue
    printf '%s' "[HOSTKEY] %s\n" "$f"
    if have stat; then stat -c "  perms=%A owner=%U group=%G size=%s bytes" "$f" 2>/dev/null || ls -l "$f"; else ls -l "$f" || true; fi
    if [[ "$f" == *.pub ]] && have ssh-keygen; then ssh-keygen -l -f "$f" || true; else if have file; then file "$f" || true; fi; fi
    echo
  done
else
  echo "(no host key files matched under /etc/ssh)"
fi
shopt -u nullglob
echo
echo "[INFO] User SSH key candidates in /root and /home (common filenames only):"
SSH_FIND_PATHS=(); [[ -d /root ]] && SSH_FIND_PATHS+=("/root"); [[ -d /home ]] && SSH_FIND_PATHS+=("/home")
if (( ${#SSH_FIND_PATHS[@]} )); then
  while IFS= read -r -d '' file; do
    printf '%s' "[USERKEY] %s\n" "$file"
    if have stat; then stat -c "  perms=%A owner=%U group=%G size=%s bytes" "$file" 2>/dev/null || ls -l "$file"; else ls -l "$file" || true; fi
    if [[ "$file" == *.pub ]] && have ssh-keygen; then ssh-keygen -l -f "$file" || true; else if have file; then file "$file" || true; fi; fi
    echo
  done < <(find "${SSH_FIND_PATHS[@]}" -maxdepth 4 -type f \( -path "*/.ssh/*" -a \( -name "id_*" -o -name "*.pub" -o -name "*.pem" -o -name "*.key" -o -name "*.cert" \) \) -print0 2>/dev/null)
else
  echo "(no /root or /home directories to scan)"
fi
echo
echo "[INFO] Note: Only file paths and safe metadata are printed. Private key contents are never shown."
pause

# --- Hardware fingerprinting: DMI/SMBIOS, CPU microcode, IOMMU/virt ---
section "HARDWARE FINGERPRINTING (DMI/SMBIOS, MICROCODE, IOMMU)"
if have dmidecode; then
  echo "[INFO] System DMI (system/baseboard/BIOS/chassis):"
  dmidecode -t system -t baseboard -t bios -t chassis || true
else
  echo "(dmidecode not installed — skipping DMI/SMBIOS)"
fi
echo
if have lscpu; then echo "[INFO] CPU microarchitecture & flags:" && lscpu || true; fi
echo
echo "[INFO] IOMMU/VT-d/AMD-Vi (dmesg excerpts):"
dmesg | grep -Ei 'iommu|vt-d|amd[- ]?vi' | tail -n 50 || true
pause

# --- Bus controllers & kernel drivers ---
section "BUS CONTROLLERS & KERNEL DRIVERS (PCI/USB)"
if have lspci; then
  echo "[INFO] PCI devices with kernel drivers:"
  lspci -nnk || true
  echo
  echo "[INFO] Storage/Network/Display controllers (filtered):"
  lspci -nn | grep -Ei 'storage|sata|nvme|raid|ethernet|network|wireless|vga|3d|display|usb' || true
else
  echo "(lspci not installed — skipping PCI)"
fi
echo
if have lsusb; then
  echo "[INFO] USB topology (lsusb -t):"
  lsusb -t || true
  echo
  echo "[INFO] USB verbose (top 200 lines):"
  lsusb -v 2>/dev/null | head -n 200 || true
else
  echo "(lsusb not installed — skipping USB)"
fi
pause

# --- Graphics / displays ---
section "GRAPHICS & DISPLAYS"
if have lspci; then echo "[INFO] VGA/3D/Display adapters:" && lspci | grep -Ei 'vga|3d|display' || true; fi
if [[ -d /sys/class/drm ]]; then
  echo "[INFO] DRM devices:"; ls -l /sys/class/drm || true
fi
if [[ -n "${DISPLAY:-}" ]] && have xrandr; then
  echo "[INFO] Xrandr displays:"; xrandr --query || true
fi
if have glxinfo; then
  echo "[INFO] GL renderer info:"; glxinfo -B || true
fi
pause

# --- Storage details: controllers, disks, serials, RAID/LVM/ZFS/Btrfs ---
section "STORAGE CONTROLLERS & DEVICES"
if have lsblk; then
  echo "[INFO] Block devices (lsblk):"
  lsblk -e7 -o NAME,MODEL,SERIAL,WWN,TRAN,HCTL,TYPE,SIZE,FSTYPE,LABEL,UUID,MOUNTPOINT,RM,RO,STATE || true
else
  echo "(lsblk not found — skipping block device overview)"
fi
echo
echo "[INFO] Filesystem mounts:"; mount | sort || true
echo
if have blkid; then echo "[INFO] blkid signatures:" && blkid || true; fi
echo
if have smartctl; then
  echo "[INFO] SMART device identities (smartctl -i):"
  for dev in /dev/sd[a-z] /dev/nvme[0-9]n[0-9]; do
    [[ -e "$dev" ]] || continue
    echo "--- $dev ---"; smartctl -i "$dev" || true; echo
  done
else
  echo "(smartctl not installed — skipping SMART identities)"
fi
echo
echo "[INFO] Linux software RAID status:"
cat /proc/mdstat 2>/dev/null || echo "(no mdraid)"
if have mdadm; then mdadm --detail --scan 2>/dev/null || true; fi
echo
if have pvs; then echo "[INFO] LVM PVs:" && pvs -o+pv_uuid || true; fi
if have vgs; then echo "[INFO] LVM VGs:" && vgs -o+vg_uuid || true; fi
if have lvs; then echo "[INFO] LVM LVs:" && lvs -o+devices,lv_uuid || true; fi
echo
if have zpool; then echo "[INFO] ZFS pools:" && zpool status -v || true; fi
if have zfs; then echo "[INFO] ZFS datasets:" && zfs list -o name,used,avail,mountpoint || true; fi
echo
if have btrfs; then echo "[INFO] Btrfs filesystems:" && btrfs filesystem show || true; fi
pause

# --- Kernel modules & security sysctls ---
section "KERNEL MODULES & SECURITY SYSCTLS"
echo "[INFO] Loaded modules (top 50 by size):"
if have lsmod; then lsmod | sort -k2 -nr | head -n 50 || true; else echo "(lsmod not found)"; fi
echo
echo "[INFO] Kernel security-relevant sysctls:"
if have sysctl; then
  for k in \
    kernel.kptr_restrict \
    kernel.randomize_va_space \
    kernel.yama.ptrace_scope \
    kernel.unprivileged_bpf_disabled \
    fs.protected_hardlinks \
    fs.protected_symlinks \
    fs.protected_fifos \
    fs.protected_regular \
    net.ipv4.ip_forward \
    net.ipv4.conf.all.rp_filter \
    net.ipv4.tcp_syncookies \
    net.ipv4.conf.all.accept_redirects \
    net.ipv4.conf.default.accept_redirects \
    net.ipv4.conf.all.send_redirects \
    net.ipv4.conf.all.accept_source_route \
    net.ipv6.conf.all.accept_ra \
    net.ipv6.conf.all.accept_redirects \
  ; do sysctl -n "$k" 2>/dev/null | xargs -I{} printf "  %-45s %s\n" "$k" "{}"; done
else
  echo "(sysctl not found)"
fi
pause

# --- Boot mode & firmware ---
section "BOOT MODE & FIRMWARE"
if have efibootmgr; then echo "[INFO] EFI boot entries:" && efibootmgr -v || true; elif have bootctl; then echo "[INFO] bootctl status:" && bootctl status || true; else echo "(efibootmgr/bootctl not installed — skipping)"; fi
echo
echo "[INFO] dmesg errors/warnings (last 200 lines):"
dmesg -T --level=err,warn 2>/dev/null | tail -n 200 || dmesg | tail -n 200 || true
echo
echo "[INFO] Crashkernel setting (if any):"
grep -o 'crashkernel=[^ ]*' /proc/cmdline 2>/dev/null || echo "(none)"
pause

# --- Services, timers, processes ---
section "SERVICES, TIMERS, PROCESSES"
if have systemctl; then
  echo "[INFO] Running services:"; systemctl list-units --type=service --state=running || true
  echo
  echo "[INFO] Failed units:"; systemctl --failed || true
  echo
  echo "[INFO] Timers:"; systemctl list-timers --all || true
else
  echo "(systemctl not found — skipping service/timer listing)"
fi
echo
echo "[INFO] Process tree snapshot:"
if have pstree; then pstree -alpu 2>/dev/null || true; else ps axo pid,ppid,uid,stime,stat,cmd --forest || true; fi
pause

# --- Time sync status ---
section "TIME SYNC STATUS"
if have timedatectl; then timedatectl status || true; fi
if have chronyc; then echo; echo "[INFO] chrony sources:"; chronyc -n sources || true; fi
if have ntpq; then echo; echo "[INFO] NTP peers (ntpq -p):"; ntpq -pn || true; fi
pause

# --- Logs health (journal) ---
section "LOG HEALTH (JOURNAL ERRORS THIS BOOT)"
if have journalctl; then journalctl -p 3 -b --no-pager || true; else echo "(journalctl not found — skipping)"; fi
pause

# --- Localhost nmap scan (service fingerprinting) ---
section "LOCALHOST NMAP SCAN"
if have nmap; then
  echo "[INFO] Performing nmap scan of localhost (127.0.0.1) — SYN, service/version, default scripts"
  nmap -vv -T4 -sS -sV -sC 127.0.0.1 || true
else
  echo "(nmap not installed — skipping localhost scan)"
fi
pause

# --- Audit complete ---
section "AUDIT COMPLETE"
echo "[INFO] Review above output for open ports, drivers/firmware mismatches, storage health, and security hardening opportunities."
echo "[INFO] Finished at: $(date -Is)"

