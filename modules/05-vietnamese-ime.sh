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

[Behavior]
ShareInputState=All
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
quickshell=4
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
DMS_HYPRLAND_EXCLUSIVE_FOCUS=1
EOF

HYPR_CONF_ENTRY="${HOME}/.config/hypr/hyprland.lua"
if [[ -f "$HYPR_CONF_ENTRY" ]]; then
    if grep -q "require(\"config.environment\")" "$HYPR_CONF_ENTRY"; then
        # Đảm bảo environment được nạp trước autostart
        sed -i '/require("config.environment")/d' "$HYPR_CONF_ENTRY"
        sed -i '/require("config.autostart")/i require("config.environment")' "$HYPR_CONF_ENTRY"
    fi
fi

HYPR_ENV="${HOME}/.config/hypr/config/environment.lua"
if [[ -f "$HYPR_ENV" ]]; then
    if ! grep -q "GTK_IM_MODULE" "$HYPR_ENV"; then
        sed -i 's/-- if you don'\''t use UWSM.*/&\nhl.env("GTK_IM_MODULE", "fcitx")\nhl.env("QT_IM_MODULE", "fcitx")\nhl.env("XMODIFIERS", "@im=fcitx")\nhl.env("DMS_HYPRLAND_EXCLUSIVE_FOCUS", "1")\nhl.env("DMS_SHELL_DIR", os.getenv("HOME") .. "\/.config\/DankMaterialShell\/shell")/' "$HYPR_ENV"
    elif ! grep -q "DMS_SHELL_DIR" "$HYPR_ENV"; then
        sed -i '/hl.env("DMS_HYPRLAND_EXCLUSIVE_FOCUS", "1")/a hl.env("DMS_SHELL_DIR", os.getenv("HOME") .. "/.config/DankMaterialShell/shell")' "$HYPR_ENV"
    fi
fi

# 6. Đảm bảo fcitx5 được autostart trong Hyprland và DMS chạy với biến môi trường IME
HYPR_AUTOSTART="${HOME}/.config/hypr/config/autostart.lua"
if [[ -f "$HYPR_AUTOSTART" ]]; then
    if grep -q 'dms run' "$HYPR_AUTOSTART"; then
        sed -i 's|hl.exec_cmd(".*dms run.*")|hl.exec_cmd("env DMS_HYPRLAND_EXCLUSIVE_FOCUS=1 DMS_SHELL_DIR=" .. os.getenv("HOME") .. "/.config/DankMaterialShell/shell QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx dms run")|g' "$HYPR_AUTOSTART"
    fi
    if ! grep -q "fcitx5 -d" "$HYPR_AUTOSTART"; then
        sed -i '/dms run/a \    hl.exec_cmd("fcitx5 -d")' "$HYPR_AUTOSTART"
    fi
fi

# 7. Sửa lỗi focus cho DankMaterialShell Spotlight khi mở bằng Super+Space
SPOTLIGHT_QML="${HOME}/.config/DankMaterialShell/shell/Modals/DankLauncherV2/DankLauncherV2ModalSpotlight.qml"
if [[ -f "$SPOTLIGHT_QML" ]]; then
    if ! grep -q "root.spotlightContent?.searchField?.forceActiveFocus" "$SPOTLIGHT_QML"; then
        sed -i 's/spotlightContent.searchField.selectAll();/&\n            Qt.callLater(() => { if (root.spotlightOpen \&\& root.spotlightContent?.searchField) { root.spotlightContent.searchField.forceActiveFocus(); } });/' "$SPOTLIGHT_QML"
    fi
fi

# 8. Sửa lỗi filter kết quả tìm kiếm theo thời gian thực (realtime) khi gõ tiếng Việt trong Spotlight
log_info "Cấu hình tối ưu gõ tiếng Việt trong Spotlight Launcher (real-time filter)..."
python3 << 'EOF'
import pathlib

dms_dir = pathlib.Path.home() / ".config" / "DankMaterialShell" / "shell"
text_field = dms_dir / "DankCommon" / "Widgets" / "DankTextField.qml"
spotlight = dms_dir / "Modals" / "DankLauncherV2" / "SpotlightLauncherContent.qml"
launcher = dms_dir / "Modals" / "DankLauncherV2" / "LauncherContent.qml"

# 1. Patch DankTextField.qml (hỗ trợ displayText và effectiveText cho bộ gõ IME)
if text_field.exists():
    content = text_field.read_text(encoding="utf-8")
    if "property alias displayText: textInput.displayText" not in content:
        content = content.replace(
            "    property alias text: textInput.text\n",
            "    property alias text: textInput.text\n    property alias displayText: textInput.displayText\n    property alias inputMethodComposing: textInput.inputMethodComposing\n    readonly property string effectiveText: textInput.displayText.length > 0 ? textInput.displayText : textInput.text\n",
            1
        )
        text_field.write_text(content, encoding="utf-8")
        print("Đã patch DankTextField.qml (hỗ trợ displayText và effectiveText)")

# 2. Patch SpotlightLauncherContent.qml (filter kết quả real-time khi đang soạn chữ)
if spotlight.exists():
    content = spotlight.read_text(encoding="utf-8")
    changed = False
    if "searchInput.effectiveText.length > 0" not in content:
        content = content.replace("searchInput.text.length > 0", "searchInput.effectiveText.length > 0")
        changed = True
    if "function _updateSearch()" not in content:
        old_search = """                onTextChanged: {
                    if (root.suspendSearchUpdates)
                        return;
                    actionPanel.hide();
                    if (text.length > 0) {
                        root.controller.setSearchQuery(text);
                    } else {
                        root.resetSearch();
                    }
                }"""
        new_search = """                function _updateSearch() {
                    if (root.suspendSearchUpdates)
                        return;
                    actionPanel.hide();
                    const q = searchInput.effectiveText;
                    if (q.length > 0) {
                        root.controller.setSearchQuery(q);
                    } else {
                        root.resetSearch();
                    }
                }

                onTextChanged: _updateSearch()
                onDisplayTextChanged: _updateSearch()"""
        if old_search in content:
            content = content.replace(old_search, new_search, 1)
            changed = True
    if "root.controller.setSearchQuery(searchInput.effectiveText);" not in content:
        content = content.replace(
            "root.controller.setSearchQuery(searchInput.text);",
            "root.controller.setSearchQuery(searchInput.effectiveText);"
        )
        changed = True
    if changed:
        spotlight.write_text(content, encoding="utf-8")
        print("Đã patch SpotlightLauncherContent.qml (filter kết quả real-time khi gõ tiếng Việt)")

# 3. Patch LauncherContent.qml
if launcher.exists():
    content = launcher.read_text(encoding="utf-8")
    if "onDisplayTextChanged: _updateSearch()" not in content:
        old_launcher = """                onTextChanged: {
                    controller.setSearchQuery(effectiveText);
                    if (actionPanel.expanded) {
                        actionPanel.hide();
                    }
                }"""
        if old_launcher not in content:
            old_launcher = """                onTextChanged: {
                    controller.setSearchQuery(text);
                    if (actionPanel.expanded) {
                        actionPanel.hide();
                    }
                }"""
        new_launcher = """                function _updateSearch() {
                    controller.setSearchQuery(effectiveText);
                    if (actionPanel.expanded) {
                        actionPanel.hide();
                    }
                }

                onTextChanged: _updateSearch()
                onDisplayTextChanged: _updateSearch()"""
        if old_launcher in content:
            content = content.replace(old_launcher, new_launcher, 1)
            launcher.write_text(content, encoding="utf-8")
            print("Đã patch LauncherContent.qml (hỗ trợ real-time filter)")
EOF

# Đồng bộ file đã patch vào thư mục runtime cache (nếu đang tồn tại)
for cache_dir in /run/user/$(id -u)/danklinux-shell/*/; do
    if [[ -d "$cache_dir" ]]; then
        chmod -R u+w "$cache_dir" 2>/dev/null || true
        cp -f "${HOME}/.config/DankMaterialShell/shell/DankCommon/Widgets/DankTextField.qml" "${cache_dir}/DankCommon/Widgets/" 2>/dev/null || true
        cp -f "${HOME}/.config/DankMaterialShell/shell/Modals/DankLauncherV2/SpotlightLauncherContent.qml" "${cache_dir}/Modals/DankLauncherV2/" 2>/dev/null || true
        cp -f "${HOME}/.config/DankMaterialShell/shell/Modals/DankLauncherV2/LauncherContent.qml" "${cache_dir}/Modals/DankLauncherV2/" 2>/dev/null || true
        chmod -R u-w "$cache_dir" 2>/dev/null || true
    fi
done

# 9. Khởi động fcitx5 và DMS nếu đang chạy
if pgrep -x "Hyprland" >/dev/null 2>&1; then
    if command -v fcitx5 >/dev/null 2>&1; then
        log_info "Đang khởi động lại Fcitx5 trong phiên hiện tại..."
        killall fcitx5 2>/dev/null || true
        fcitx5 -d >/dev/null 2>&1 || true
    fi
    if pgrep -x "dms" >/dev/null 2>&1; then
        log_info "Khởi động lại DMS với cấu hình UI mới..."
        dms kill 2>/dev/null || true
        sleep 1
        DMS_SHELL_DIR="${HOME}/.config/DankMaterialShell/shell" dms run -d 2>/dev/null || true
    fi
    hyprctl reload >/dev/null 2>&1 || true
fi

log_success "Hoàn tất thiết lập Bộ gõ tiếng Việt Fcitx5 Lotus!"
echo -e "  - Bộ gõ: Lotus (Telex mặc định)"
echo -e "  - Phím tắt chuyển đổi Anh / Việt: Alt + Left Shift (Alt+Shift_L)"
echo -e "  - Tự động khởi động cùng Hyprland: fcitx5 -d"
