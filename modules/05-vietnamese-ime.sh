#!/usr/bin/env bash
# Description: Cài đặt Fcitx5 Lotus (gõ không gạch chân) & phím tắt Alt + Left Shift
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

cache_sudo

log_info "Bắt đầu cài đặt Fcitx5 và Bộ gõ tiếng Việt Lotus..."

# 1. Cài đặt các gói Fcitx5 và fcitx5-lotus-bin
PACKAGES=(
    "fcitx5"
    "fcitx5-configtool"
    "fcitx5-gtk"
    "fcitx5-qt"
    "fcitx5-lotus-bin"
)

for pkg in "${PACKAGES[@]}"; do
    if pacman -Qi "$pkg" >/dev/null 2>&1; then
        log_info "Gói [${pkg}] đã được cài đặt từ trước."
    else
        log_info "Đang cài đặt [${pkg}]..."
        yay -S --needed --noconfirm "$pkg"
        log_success "Đã cài đặt [${pkg}]."
    fi
done

# 2. Cấu hình quyền và dịch vụ Lotus Server
log_info "Cấu hình quyền truy cập uinput và kích hoạt dịch vụ Lotus Server..."
sudo usermod -aG input "$USER" 2>/dev/null || true
sudo modprobe uinput 2>/dev/null || true

if systemctl list-unit-files | grep -q "fcitx5-lotus-server@"; then
    sudo systemctl enable --now "fcitx5-lotus-server@${USER}.service" 2>/dev/null || true
    log_success "Đã kích hoạt fcitx5-lotus-server@${USER}.service."
fi

# 3. Tạo cấu hình phím tắt Alt + Left Shift trong ~/.config/fcitx5/config
log_info "Thiết lập phím tắt chuyển đổi Alt + Left Shift..."
mkdir -p "${HOME}/.config/fcitx5"

cat <<'EOF' > "${HOME}/.config/fcitx5/config"
[Hotkey]
# Enumerate when press trigger key repeatedly
EnumerateWithTriggerKeys=True
# Skip first input method while enumerating
EnumerateSkipFirst=False

[Hotkey/TriggerKeys]
0=Alt+Shift_L

[Hotkey/AltTriggerKeys]

[Hotkey/EnumerateForwardKeys]
0=Alt+Shift_L

[Hotkey/EnumerateBackwardKeys]

[Hotkey/PrevPage]
0=Up

[Hotkey/NextPage]
0=Down

[Hotkey/PrevCandidate]
0=Shift+Tab

[Hotkey/NextCandidate]
0=Tab
EOF

# 4. Cấu hình profile: Tiếng Anh (keyboard-us) và Tiếng Việt (lotus)
log_info "Cấu hình bộ gõ Lotus vào profile Fcitx5..."
cat <<'EOF' > "${HOME}/.config/fcitx5/profile"
[Groups/0]
# Group Name
Name=Default
# Layout
Default Layout=us
# Default Input Method
DefaultIM=keyboard-us

[Groups/0/Items/0]
# Name
Name=keyboard-us
# Layout
Layout=

[Groups/0/Items/1]
# Name
Name=lotus
# Layout
Layout=

[GroupOrder]
0=Default
EOF

# 5. Cấu hình chế độ gõ không gạch chân (Non-preedit / Smooth qua Uinput & SurroundingText)
log_info "Cấu hình chế độ gõ không gạch chân (Smooth)..."
mkdir -p "${HOME}/.config/fcitx5/conf"
cat <<'EOF' > "${HOME}/.config/fcitx5/conf/lotus.conf"
Mode=Smooth
InputMethod=Telex
OutputCharset=Unicode
FixUinputWithAck=False
useSurroundingTextIfPossible=True
AutoNonVnRestore=True
FreeMarking=True
ModernStyle=True
DdFreeStyle=True
EOF

cat <<'EOF' > "${HOME}/.config/fcitx5/lotus-app-rules.conf"
# Lotus Per-App Configuration
# 0 = Off, 1 = Uinput (Smooth), 2 = Uinput (Slow), 3 = Uinput (Super Smooth), 4 = Surrounding Text, 5 = Preedit, 6 = Emoji Picker, 8 = Minecraft
default=1
microsoft-edge=4
msedge=4
chromium=4
helium-browser=4
code=1
sublime_text=1
kitty=1
EOF

# 6. Cấu hình cờ Wayland IME cho trình duyệt Chromium/Edge để sửa lỗi thanh địa chỉ
log_info "Cấu hình cờ Wayland IME cho Microsoft Edge và Chromium..."
cat <<'EOF' > "${HOME}/.config/microsoft-edge-stable-flags.conf"
--ozone-platform-hint=auto
--ozone-platform=wayland
--enable-wayland-ime
--wayland-text-input-version=3
EOF

cat <<'EOF' > "${HOME}/.config/chromium-flags.conf"
--ozone-platform-hint=auto
--ozone-platform=wayland
--enable-wayland-ime
--wayland-text-input-version=3
EOF

# 5. Cấu hình biến môi trường toàn cục cho Wayland/Hyprland
log_info "Thiết lập biến môi trường IM Module..."
mkdir -p "${HOME}/.config/environment.d"
cat <<'EOF' > "${HOME}/.config/environment.d/fcitx5.conf"
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF

HYPR_ENV="${HOME}/.config/hypr/config/environment.lua"
if [[ -f "$HYPR_ENV" ]]; then
    if ! grep -q "GTK_IM_MODULE" "$HYPR_ENV"; then
        sed -i 's/-- if you don'\''t use UWSM.*/&\nhl.env("GTK_IM_MODULE", "fcitx")\nhl.env("QT_IM_MODULE", "fcitx")\nhl.env("XMODIFIERS", "@im=fcitx")/' "$HYPR_ENV"
    fi
fi

# 6. Đảm bảo fcitx5 được autostart trong Hyprland
HYPR_AUTOSTART="${HOME}/.config/hypr/config/autostart.lua"
if [[ -f "$HYPR_AUTOSTART" ]]; then
    if ! grep -q "fcitx5 -d" "$HYPR_AUTOSTART"; then
        sed -i '/hl.exec_cmd("dms run")/a \    hl.exec_cmd("fcitx5 -d")' "$HYPR_AUTOSTART"
    fi
fi

# 7. Khởi động fcitx5 nếu Hyprland đang chạy
if pgrep -x "Hyprland" >/dev/null 2>&1; then
    if command -v fcitx5 >/dev/null 2>&1; then
        log_info "Đang khởi động lại Fcitx5 trong phiên hiện tại..."
        killall fcitx5 2>/dev/null || true
        fcitx5 -d >/dev/null 2>&1 || true
    fi
    hyprctl reload >/dev/null 2>&1 || true
fi

log_success "Hoàn tất thiết lập Bộ gõ tiếng Việt Fcitx5 Lotus!"
echo -e "  - Bộ gõ: Lotus (Telex mặc định)"
echo -e "  - Phím tắt chuyển đổi Anh / Việt: Alt + Left Shift (Alt+Shift_L)"
echo -e "  - Tự động khởi động cùng Hyprland: fcitx5 -d"
