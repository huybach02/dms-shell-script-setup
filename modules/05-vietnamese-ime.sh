#!/usr/bin/env bash
# Description: Cài đặt Fcitx5 Lotus (không gạch chân), phím tắt Alt+Shift, tự động chuyển đổi IME cho Spotlight
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
--password-store=basic
EOF

cat <<'EOF' > "${HOME}/.config/chromium-flags.conf"
--ozone-platform-hint=auto
--ozone-platform=wayland
--enable-wayland-ime
--wayland-text-input-version=3
--password-store=basic
EOF

# 7. Cấu hình biến môi trường toàn cục cho Wayland/Hyprland
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

# 8. Đảm bảo fcitx5 được autostart trong Hyprland và DMS chạy với biến môi trường IME
HYPR_AUTOSTART="${HOME}/.config/hypr/config/autostart.lua"
if [[ -f "$HYPR_AUTOSTART" ]]; then
    if grep -q 'dms run' "$HYPR_AUTOSTART"; then
        sed -i 's|hl.exec_cmd(".*dms run.*")|hl.exec_cmd("env DMS_HYPRLAND_EXCLUSIVE_FOCUS=1 DMS_SHELL_DIR=" .. os.getenv("HOME") .. "/.config/DankMaterialShell/shell QT_IM_MODULE=fcitx XMODIFIERS=@im=fcitx dms run")|g' "$HYPR_AUTOSTART"
    fi
    if ! grep -q "fcitx5 -d" "$HYPR_AUTOSTART"; then
        sed -i '/dms run/a \    hl.exec_cmd("fcitx5 -d")' "$HYPR_AUTOSTART"
    fi
fi

# 9. Tự động chuyển sang Tiếng Anh khi mở Spotlight Launcher và khôi phục Tiếng Việt khi đóng
log_info "Cấu hình tự động chuyển đổi IME khi mở/đóng Spotlight Launcher..."
python3 << 'EOF'
import pathlib
import re

dms_dir = pathlib.Path.home() / ".config" / "DankMaterialShell" / "shell"
text_field = dms_dir / "DankCommon" / "Widgets" / "DankTextField.qml"
spotlight = dms_dir / "Modals" / "DankLauncherV2" / "SpotlightLauncherContent.qml"
launcher = dms_dir / "Modals" / "DankLauncherV2" / "LauncherContent.qml"
spotlight_modal = dms_dir / "Modals" / "DankLauncherV2" / "DankLauncherV2ModalSpotlight.qml"
modal_v2 = dms_dir / "Modals" / "DankLauncherV2" / "DankLauncherV2Modal.qml"

# Dọn dẹp triệt để các thay đổi tạm thời cũ (nếu có) để giữ mã nguồn nguyên bản sạch sẽ
if text_field.exists():
    c = text_field.read_text(encoding="utf-8")
    if "property alias displayText: textInput.displayText" in c:
        c = re.sub(
            r'    property alias text: textInput\.text\n    property alias displayText: textInput\.displayText\n    property alias inputMethodComposing: textInput\.inputMethodComposing\n    readonly property string effectiveText:.*?\n',
            '    property alias text: textInput.text\n',
            c
        )
        text_field.write_text(c, encoding="utf-8")
        print("Đã dọn dẹp DankTextField.qml về nguyên bản.")

if spotlight.exists():
    c = spotlight.read_text(encoding="utf-8")
    changed = False
    if "searchInput.effectiveText" in c:
        c = c.replace("searchInput.effectiveText.length > 0", "searchInput.text.length > 0")
        c = c.replace("root.controller.setSearchQuery(searchInput.effectiveText);", "root.controller.setSearchQuery(searchInput.text);")
        changed = True
    if "function _updateSearch()" in c:
        old_patch = """                function _updateSearch() {
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
        clean_code = """                onTextChanged: {
                    if (root.suspendSearchUpdates)
                        return;
                    actionPanel.hide();
                    if (text.length > 0) {
                        root.controller.setSearchQuery(text);
                    } else {
                        root.resetSearch();
                    }
                }"""
        if old_patch in c:
            c = c.replace(old_patch, clean_code, 1)
            changed = True
    if changed:
        spotlight.write_text(c, encoding="utf-8")
        print("Đã dọn dẹp SpotlightLauncherContent.qml về nguyên bản.")

if launcher.exists():
    c = launcher.read_text(encoding="utf-8")
    if "function _updateSearch()" in c:
        old_patch = """                function _updateSearch() {
                    controller.setSearchQuery(effectiveText);
                    if (actionPanel.expanded) {
                        actionPanel.hide();
                    }
                }

                onTextChanged: _updateSearch()
                onDisplayTextChanged: _updateSearch()"""
        clean_code = """                onTextChanged: {
                    controller.setSearchQuery(text);
                    if (actionPanel.expanded) {
                        actionPanel.hide();
                    }
                }"""
        if old_patch in c:
            c = c.replace(old_patch, clean_code, 1)
            launcher.write_text(c, encoding="utf-8")
            print("Đã dọn dẹp LauncherContent.qml về nguyên bản.")

if spotlight_modal.exists():
    c = spotlight_modal.read_text(encoding="utf-8")
    if "Qt.callLater(() => { if (root.spotlightOpen && root.spotlightContent?.searchField)" in c:
        c = re.sub(
            r'\n\s*Qt\.callLater\(\(\) => \{\s*if \(root\.spotlightOpen && root\.spotlightContent\?\.searchField\) \{\s*root\.spotlightContent\.searchField\.forceActiveFocus\(\);\s*\}\s*\}\);',
            '',
            c
        )
        spotlight_modal.write_text(c, encoding="utf-8")
        print("Đã dọn dẹp DankLauncherV2ModalSpotlight.qml về nguyên bản.")

# Áp dụng giải pháp tập trung duy nhất tại DankLauncherV2Modal.qml
if modal_v2.exists():
    content = modal_v2.read_text(encoding="utf-8")
    if "import Quickshell.Io" not in content:
        content = content.replace("import QtQuick\n", "import QtQuick\nimport Quickshell.Io\n", 1)
    if "_wasVietnameseIme" not in content:
        target_prop = "    property bool edgeHoverManaged: false\n"
        ime_logic = """    property bool edgeHoverManaged: false
    property bool _wasVietnameseIme: false

    Process {
        id: checkImeProc
        command: ["fcitx5-remote"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const state = data.trim();
                if (state === "2") {
                    root._wasVietnameseIme = true;
                    if (switchImeToEnglishProc.running)
                        switchImeToEnglishProc.running = false;
                    switchImeToEnglishProc.running = true;
                } else {
                    root._wasVietnameseIme = false;
                }
            }
        }
    }

    Process {
        id: switchImeToEnglishProc
        command: ["fcitx5-remote", "-c"]
        running: false
    }

    Process {
        id: restoreImeProc
        command: ["fcitx5-remote", "-o"]
        running: false
    }

    function _restoreImeIfNeeded() {
        if (root._wasVietnameseIme) {
            root._wasVietnameseIme = false;
            if (restoreImeProc.running)
                restoreImeProc.running = false;
            restoreImeProc.running = true;
        }
    }

    onSpotlightOpenChanged: {
        if (spotlightOpen) {
            if (checkImeProc.running)
                checkImeProc.running = false;
            checkImeProc.running = true;
        } else {
            _restoreImeIfNeeded();
        }
    }
"""
        if target_prop in content:
            content = content.replace(target_prop, ime_logic, 1)
            modal_v2.write_text(content, encoding="utf-8")
            print("Đã cấu hình DankLauncherV2Modal.qml tự động chuyển IME cho Spotlight.")
EOF

# Đồng bộ file vào thư mục runtime cache (nếu đang tồn tại)
for cache_dir in /run/user/$(id -u)/danklinux-shell/*/; do
    if [[ -d "$cache_dir" ]]; then
        chmod -R u+w "$cache_dir" 2>/dev/null || true
        cp -f "${HOME}/.config/DankMaterialShell/shell/DankCommon/Widgets/DankTextField.qml" "${cache_dir}/DankCommon/Widgets/" 2>/dev/null || true
        cp -f "${HOME}/.config/DankMaterialShell/shell/Modals/DankLauncherV2/DankLauncherV2Modal.qml" "${cache_dir}/Modals/DankLauncherV2/" 2>/dev/null || true
        cp -f "${HOME}/.config/DankMaterialShell/shell/Modals/DankLauncherV2/DankLauncherV2ModalSpotlight.qml" "${cache_dir}/Modals/DankLauncherV2/" 2>/dev/null || true
        cp -f "${HOME}/.config/DankMaterialShell/shell/Modals/DankLauncherV2/SpotlightLauncherContent.qml" "${cache_dir}/Modals/DankLauncherV2/" 2>/dev/null || true
        cp -f "${HOME}/.config/DankMaterialShell/shell/Modals/DankLauncherV2/LauncherContent.qml" "${cache_dir}/Modals/DankLauncherV2/" 2>/dev/null || true
        chmod -R u-w "$cache_dir" 2>/dev/null || true
    fi
done

# 10. Khởi động fcitx5 và DMS nếu đang chạy
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
