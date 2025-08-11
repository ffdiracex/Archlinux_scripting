#!/bin/bash
# Install or update yay AUR helper

if ! command -v yay &>/dev/null; then
    echo "Installing yay..."
    git clone https://aur.archlinux.org/yay.git /tmp/yay
    (cd /tmp/yay && makepkg -si --noconfirm)
    rm -rf /tmp/yay
else
    echo "Updating yay..."
    yay -Syu --noconfirm
fi
