#!/usr/bin/env bash

set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

srcdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage_description="
Disables Swap on Linux

Designed to be called modularly from other provisioners to reuse code between scripts

eg. Vagrant provisioners that differ by OS / setup can call this from /github/bash-tools/disable_swap.sh within their scripts

"

usage_args=""

help_usage "$@"

os="$(uname -s)"

if [ "$os" != Linux ]; then
    echo "OS '$os' != Linux, aborting disabling swap"
    exit 1
fi

#echo 0 > /proc/sys/vm/swappiness

timestamp "Disabling All Swap"
swapoff -a

timestamp "Commenting out any Swap lines in /etc/fstab"
sed -i 's,\(/.*[[:space:]]none[[:space:]]*swap[[:space:]]\),#\1,' /etc/fstab

timestamp "Swap disabled"