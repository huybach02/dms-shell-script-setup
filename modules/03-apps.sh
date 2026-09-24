#!/usr/bin/env bash
# Description: Cài đặt phần mềm (Edge, VSCode, Helium, Chromium, AppImageLauncher, LibreOffice, Sublime) & đặt mặc định
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

cache_sudo

log_info "Bắt đầu kiểm tra và cài đặt danh sách phần mềm yêu cầu..."

# Danh sách phần mềm cần cài đặt (CachyOS Repo & AUR qua yay)
PACKAGES=(
    "microsoft-edge-stable-bin" # Microsoft Edge
    "visual-studio-code-bin"    # Visual Studio Code
    "helium-browser-bin"        # Helium Browser
    "chromium"                  # Chromium Browser
    "appimagelauncher-beta-bin" # AppImageLauncher
    "libreoffice-fresh"         # LibreOffice
    "sublime-text-4"            # Sublime Text
)

for pkg in "${PACKAGES[@]}"; do
    if pacman -Qi "$pkg" >/dev/null 2>&1; then
        log_info "Gói [${pkg}] đã được cài đặt từ trước. Bỏ qua."
    else
        log_info "Đang cài đặt [${pkg}]..."
        yay -S --needed --noconfirm "$pkg"
        log_success "Cài đặt thành công [${pkg}]."
    fi
done

log_info "Thiết lập ứng dụng mặc định trong hệ thống..."

# 1. Cấu hình Microsoft Edge làm trình duyệt mặc định
log_info "Đặt Microsoft Edge làm trình duyệt web mặc định..."
xdg-settings set default-web-browser microsoft-edge.desktop 2>/dev/null || true
xdg-mime default microsoft-edge.desktop x-scheme-handler/http 2>/dev/null || true
xdg-mime default microsoft-edge.desktop x-scheme-handler/https 2>/dev/null || true
xdg-mime default microsoft-edge.desktop text/html 2>/dev/null || true
xdg-mime default microsoft-edge.desktop application/xhtml+xml 2>/dev/null || true

# 2. Cấu hình Sublime Text làm trình soạn thảo văn bản mặc định
log_info "Đặt Sublime Text làm trình soạn thảo văn bản mặc định..."
xdg-mime default sublime_text.desktop text/plain 2>/dev/null || true

# Đặt biến môi trường EDITOR / VISUAL trong .bashrc và .zshrc
for rcfile in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    if [[ -f "$rcfile" ]]; then
        if ! grep -q "export EDITOR=.*subl" "$rcfile"; then
            echo -e '\n# Default Editor\nexport EDITOR="subl -w"\nexport VISUAL="subl -w"' >> "$rcfile"
        fi
    fi
done

# 3. Cập nhật biến ứng dụng mặc định trong Hyprland variables.lua
HYPR_VARS="${HOME}/.config/hypr/config/variables.lua"
if [[ -f "$HYPR_VARS" ]]; then
    log_info "Cập nhật BROWSER và EDITOR trong Hyprland variables.lua..."
    sed -i -E 's/^BROWSER[[:space:]]*=.*/BROWSER      = "microsoft-edge-stable"/' "$HYPR_VARS"
    sed -i -E 's/^EDITOR[[:space:]]*=.*/EDITOR       = "subl -n"/' "$HYPR_VARS"
    if pgrep -x "Hyprland" >/dev/null 2>&1; then
        hyprctl reload >/dev/null 2>&1 || true
    fi
fi

# 4. Cấu hình flags tối ưu cho Microsoft Edge và Chromium trên Wayland / Hyprland
log_info "Cấu hình flags tối ưu cho Microsoft Edge và Chromium..."
for flag_file in "${HOME}/.config/microsoft-edge-stable-flags.conf" "${HOME}/.config/chromium-flags.conf"; do
    mkdir -p "$(dirname "$flag_file")"
    cat <<'EOF' > "$flag_file"
--ozone-platform-hint=auto
--ozone-platform=wayland
--enable-wayland-ime
--wayland-text-input-version=3
--password-store=basic
EOF
done

log_success "Hoàn tất cài đặt phần mềm và thiết lập ứng dụng mặc định!"
echo -e "  - Trình duyệt mặc định: Microsoft Edge"
echo -e "  - Trình soạn thảo mặc định: Sublime Text"
