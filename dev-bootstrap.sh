#!/usr/bin/env bash
# dev-bootstrap.sh — Arch developer setup for Rust, C/C++, JS/TS, Python
# Installs packages via pacman and performs optional per-user steps.
# Usage examples:
#   sudo ./dev-bootstrap.sh --all --full --yes
#   sudo ./dev-bootstrap.sh --rust --cpp --minimal --with-editors
#   sudo ./dev-bootstrap.sh --js --python --dry-run
#
# Flags:
#   --rust --cpp --js --python --all     Select stacks (default: --all)
#   --minimal | --full                   Preset scope (default: --full)
#   --with-editors                       Install neovim + code (VS Code)
#   --with-containers                    Install podman + docker (+compose)
#   --lsp | --no-lsp                     Language servers (default: --lsp on --full, off on --minimal)
#   --yes                                Non-interactive pacman (adds --noconfirm)
#   --dry-run                            Print planned actions only
#   --user USER                          Target non-root user for rustup/corepack (default: SUDO_USER)

set -euo pipefail

# ----- defaults -----
DO_RUST=0 DO_CPP=0 DO_JS=0 DO_PY=0
PRESET="full"              # minimal|full
WITH_EDITORS=0
WITH_CONTAINERS=0
LSP=""                     # "", on, off (auto by preset)
ASSUME_YES=0
DRY_RUN=0
TARGET_USER="${SUDO_USER:-}"

have() { command -v "$1" >/dev/null 2>&1; }
die() { echo "[ERR] $*" >&2; exit 1; }
info() { echo "[..] $*"; }
ok() { echo "[OK] $*"; }

usage() { sed -n '1,60p' "$0" | sed -n '1,40p'; exit 0; }

# ----- args -----
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rust) DO_RUST=1 ;;
    --cpp) DO_CPP=1 ;;
    --js) DO_JS=1 ;;
    --python) DO_PY=1 ;;
    --all) DO_RUST=1; DO_CPP=1; DO_JS=1; DO_PY=1 ;;
    --minimal) PRESET="minimal" ;;
    --full) PRESET="full" ;;
    --with-editors) WITH_EDITORS=1 ;;
    --with-containers) WITH_CONTAINERS=1 ;;
    --lsp) LSP="on" ;;
    --no-lsp) LSP="off" ;;
    --yes) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --user) TARGET_USER="$2"; shift ;;
    -h|--help) usage ;;
    *) die "Unknown argument: $1" ;;
  esac
  shift
done

# auto-select all if none specified
if (( DO_RUST==0 && DO_CPP==0 && DO_JS==0 && DO_PY==0 )); then
  DO_RUST=1; DO_CPP=1; DO_JS=1; DO_PY=1
fi
# default LSP based on preset
if [[ -z "$LSP" ]]; then
  if [[ "$PRESET" == "full" ]]; then LSP="on"; else LSP="off"; fi
fi

# require root for pacman
if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  if have sudo; then exec sudo -E -- bash "$0" "$@"; else die "Run as root or install sudo"; fi
fi

# ----- package sets -----
CORE_MIN=(base-devel git curl wget openssh gnupg pkgconf cmake ninja gcc clang llvm lld gdb)
CORE_FULL=(
  "${CORE_MIN[@]}"
  clang-tools-extra lldb valgrind strace ltrace ccache bear mold
  ripgrep fd fzf jq direnv just tmux
)

RUST_PKGS=(rustup rust-analyzer)
CPP_PKGS_MIN=()    # covered by CORE
CPP_PKGS_FULL=()   # extras covered by CORE_FULL

JS_MIN=(nodejs npm typescript typescript-language-server)
JS_FULL=("${JS_MIN[@]}" yarn pnpm eslint prettier)
# note: corepack ships with node; enabling is a user step

PY_MIN=(python python-pip python-pipx ipython)
PY_FULL=("${PY_MIN[@]}" python-black python-ruff python-mypy python-virtualenv python-poetry)

LSP_PKGS=(pyright bash-language-server) # rust-analyzer, ts-ls included above

EDITORS_PKGS=(neovim code)
CONTAINERS_PKGS=(podman docker docker-compose)

# choose core set
if [[ "$PRESET" == "full" ]]; then
  CORE_PKGS=("${CORE_FULL[@]}")
else
  CORE_PKGS=("${CORE_MIN[@]}")
fi

# build final package list
declare -a PKGS=()
PKGS+=("${CORE_PKGS[@]}")

if (( DO_RUST )); then PKGS+=("${RUST_PKGS[@]}"); fi
if (( DO_CPP )); then PKGS+=("${CPP_PKGS_MIN[@]}"); [[ "$PRESET" == "full" ]] && PKGS+=("${CPP_PKGS_FULL[@]}"); fi
if (( DO_JS )); then [[ "$PRESET" == "full" ]] && PKGS+=("${JS_FULL[@]}") || PKGS+=("${JS_MIN[@]}"); fi
if (( DO_PY )); then [[ "$PRESET" == "full" ]] && PKGS+=("${PY_FULL[@]}") || PKGS+=("${PY_MIN[@]}"); fi
if [[ "$LSP" == "on" ]]; then PKGS+=("${LSP_PKGS[@]}"); fi
if (( WITH_EDITORS )); then PKGS+=("${EDITORS_PKGS[@]}"); fi
if (( WITH_CONTAINERS )); then PKGS+=("${CONTAINERS_PKGS[@]}"); fi

# de-duplicate (preserve order)
declare -A seen=()
declare -a FINAL_PKGS=()
for p in "${PKGS[@]}"; do
  [[ -n "${seen[$p]:-}" ]] && continue
  FINAL_PKGS+=("$p"); seen["$p"]=1
done

# ----- plan -----
info "Preset: $PRESET | Stacks: rust=$DO_RUST cpp=$DO_CPP js=$DO_JS py=$DO_PY | LSP=$LSP"
info "Editors: $WITH_EDITORS | Containers: $WITH_CONTAINERS"
info "Packages to install (${#FINAL_PKGS[@]}): ${FINAL_PKGS[*]}"

if (( DRY_RUN )); then
  ok "Dry run complete. No changes made."
  exit 0
fi

# ----- install -----
PACMAN_OPTS=(-S --needed)
(( ASSUME_YES )) && PACMAN_OPTS+=(--noconfirm) || true

info "Synchronizing databases and upgrading system..."
pacman -Syu "${ASSUME_YES:+--noconfirm}"

info "Installing packages..."
pacman "${PACMAN_OPTS[@]}" "${FINAL_PKGS[@]}"

ok "Package installation complete."

# ----- post-install per-user steps -----
# Determine target non-root user for rustup/corepack
if [[ -z "${TARGET_USER}" || "$TARGET_USER" == "root" ]]; then
  # try to infer from SUDO_USER; otherwise skip
  TARGET_USER="${SUDO_USER:-}"
fi

run_as_user() {
  local u="$1"; shift
  sudo -u "$u" -H bash -lc "$*"
}

if [[ -n "${TARGET_USER}" ]]; then
  info "Running user-level setup for: $TARGET_USER"

  # Rustup initialization
  if (( DO_RUST )) && have rustup; then
    info "Initializing rustup for $TARGET_USER (stable + clippy + rustfmt + rust-src)"
    run_as_user "$TARGET_USER" "rustup default stable || true"
    run_as_user "$TARGET_USER" "rustup component add clippy rustfmt rust-src || true"
  fi

  # Node corepack enable (to manage yarn/pnpm via Node)
  if (( DO_JS )) && have corepack; then
    info "Enabling corepack for $TARGET_USER (yarn/pnpm shims)"
    run_as_user "$TARGET_USER" "corepack enable || true"
  fi

  # pipx path setup (even if tools were installed via pacman, this prepares future use)
  if (( DO_PY )) && have pipx; then
    info "Ensuring pipx path for $TARGET_USER"
    run_as_user "$TARGET_USER" "pipx ensurepath || true"
  fi
else
  info "No non-root user detected for user-level steps. You can run:"
  echo "  rustup default stable && rustup component add clippy rustfmt rust-src"
  echo "  corepack enable"
  echo "  pipx ensurepath"
fi

# Optional: enable docker service when containers requested
if (( WITH_CONTAINERS )); then
  if have systemctl; then
    info "Enabling container services (docker, podman.socket)"
    systemctl enable --now docker.service 2>/dev/null || true
    systemctl enable --now podman.socket 2>/dev/null || true
  fi
fi

ok "Developer environment is ready."
echo "Tip: Add language servers to your editor (clangd, rust-analyzer, pyright, typescript-language-server)."
