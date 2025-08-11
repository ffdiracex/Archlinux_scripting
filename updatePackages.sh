#!/usr/bin/env bash
# update-system — Safe Arch Linux package & software updater

set -euo pipefail

LOG_DIR="/var/log/arch-updates"
LOG_FILE="$LOG_DIR/update_$(date +%Y%m%dT%H%M%S).log"
CLEAN_CACHE="auto"  # auto|on|off

have() { command -v "$1" >/dev/null 2>&1; }
log() { printf '%s %s\n' "$(date -Is)" "$*" | tee -a "$LOG_FILE"; }

# Prepare logging
mkdir -p "$LOG_DIR"
exec > >(tee -a "$LOG_FILE") 2>&1

# Require root
if [[ $EUID -ne 0 ]]; then
  if have sudo; then exec sudo -E -- bash "$0" "$@"; else
    echo "Run as root or install sudo"; exit 1
  fi
fi

log "[start] System update initiated"

# Refresh databases & update
log "[pacman] Synchronizing package databases"
pacman -Syy --noconfirm

log "[pacman] Upgrading all packages"
pacman -Syu --noconfirm

# Check for pacnew/pacsave
if have pacdiff; then
  log "[config] Checking for .pacnew/.pacsave files"
  DIFFS=$(DIFFPROG=diff pacdiff -o 2>/dev/null || true)
  [[ -n "$DIFFS" ]] && { echo "$DIFFS"; log "[action] Please review differences"; } || log "[config] No config diffs"
fi

# Cache clean policy
FREE_MB=$(df -Pm / | awk 'NR==2{print $4}')
case "$CLEAN_CACHE" in
  on) CLEAN=1 ;;
  off) CLEAN=0 ;;
  auto) (( FREE_MB < 2048 )) && CLEAN=1 || CLEAN=0 ;;
esac

if [[ $CLEAN -eq 1 ]]; then
  log "[cleanup] Cleaning pacman cache"
  have paccache && paccache -r || true
  pacman -Sc --noconfirm || true
fi

# Post‑update info
log "[kernel] Running: $(uname -srmo)"
if pacman -Qdtq >/dev/null 2>&1; then
  ORPHANS=$(pacman -Qdtq | wc -l)
  (( ORPHANS > 0 )) && log "[note] $ORPHANS orphan packages found"
fi

log "[done] System update complete"
