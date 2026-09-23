#!/usr/bin/env bash
# ==============================================================================
# Script chuyển đổi sạch sẽ từ Noctalia sang DankMaterialShell (DMS) trên CachyOS
# ==============================================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
   echo "[!] Vui lòng chạy script này với quyền sudo: sudo bash $0"
   exit 1
fi

REAL_USER="${SUDO_USER:-$USER}"
USER_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

echo "=========================================================="
echo ">> [1/5] Cài đặt DankMaterialShell và các gói liên quan..."
echo "=========================================================="
pacman -Sy --needed --noconfirm dms-shell-hyprland greetd-tuigreet matugen wtype

echo "=========================================================="
echo ">> [2/5] Cấu hình Login Greeter (greetd + tuigreet)..."
echo "=========================================================="
if [[ -f /etc/greetd/config.toml ]]; then
    cp /etc/greetd/config.toml /etc/greetd/config.toml.bak-noctalia
    echo "    Đã sao lưu /etc/greetd/config.toml sang /etc/greetd/config.toml.bak-noctalia"
fi

cat <<'EOF' > /etc/greetd/config.toml
[terminal]
vt = 1

[default_session]
command = "tuigreet --time --remember --remember-session --sessions /usr/share/wayland-sessions"
user = "greeter"
EOF

mkdir -p /var/cache/tuigreet
chown -R greeter:greeter /var/cache/tuigreet
chmod 755 /var/cache/tuigreet
echo "    Đã cập nhật /etc/greetd/config.toml sử dụng tuigreet thành công."

echo "=========================================================="
echo ">> [3/5] Dừng tiến trình Noctalia đang chạy..."
echo "=========================================================="
killall noctalia 2>/dev/null || true

echo "=========================================================="
echo ">> [4/5] Gỡ bỏ sạch sẽ các gói Noctalia khỏi hệ thống..."
echo "=========================================================="
# Gỡ bỏ cachyos-hypr-noctalia, noctalia và noctalia-greeter cùng các dependencies không dùng
pacman -Rns --noconfirm cachyos-hypr-noctalia noctalia noctalia-greeter 2>/dev/null || \
pacman -Rdd --noconfirm cachyos-hypr-noctalia noctalia noctalia-greeter || true

echo "=========================================================="
echo ">> [5/5] Dọn dẹp thư mục cấu hình và cache của Noctalia..."
echo "=========================================================="
rm -rf "$USER_HOME/.config/noctalia"
rm -rf "$USER_HOME/.cache/noctalia"
rm -rf /usr/share/noctalia-greeter
rm -rf /var/lib/noctalia-greeter

echo "=========================================================="
echo ">> HOÀN TẤT CHUYỂN ĐỔI!"
echo "=========================================================="
echo "Desktop Shell hiện tại đã được chuyển hoàn toàn sang DankMaterialShell."
echo "Khởi chạy thử DMS: su - $REAL_USER -c 'dms run &'"
echo "Hoặc bạn có thể khởi động lại máy để trải nghiệm giao diện mới: reboot"
