#!/usr/bin/env bash
# ==============================================================================
# Khôi phục các tiện ích desktop cốt lõi cho Hyprland
# ==============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "[!] Vui lòng chạy với quyền sudo: sudo bash $0"
   exit 1
fi

echo ">> Đang cài đặt lại các tiện ích desktop thiết yếu..."
pacman -S --needed --noconfirm \
    xdg-desktop-portal-hyprland \
    wl-clipboard \
    uwsm \
    brightnessctl \
    grim \
    slurp \
    hyprpicker \
    qt6ct \
    swash \
    adw-gtk-theme \
    xorg-xhost \
    gvfs \
    gvfs-mtp

echo ">> Hoàn tất! Tất cả tiện ích desktop cần thiết đã được khôi phục."
