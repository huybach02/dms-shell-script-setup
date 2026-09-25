#!/usr/bin/env bash
# Description: Thiết lập phím tắt Hyprland (Workspace SUPER+1..9, Mở Dolphin SUPER+SHIFT+F, Chụp màn hình SUPER+SHIFT+S, Monitor SUPER+ALT+1..3)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

log_info "Bắt đầu thiết lập phím tắt Hyprland và chức năng chụp màn hình..."

HYPR_CONFIG_DIR="${HOME}/.config/hypr/config"
BINDS_FILE="${HYPR_CONFIG_DIR}/binds.lua"
WINDOWRULES_FILE="${HYPR_CONFIG_DIR}/windowrules.lua"

if [[ ! -f "$BINDS_FILE" ]]; then
    log_error "Không tìm thấy file: $BINDS_FILE"
    exit 1
fi

# 1. Cài đặt công cụ chỉnh sửa ảnh Satty nếu chưa có
if ! command -v satty >/dev/null 2>&1; then
    log_info "Đang cài đặt công cụ chỉnh sửa ảnh chụp màn hình Satty..."
    if sudo -n true 2>/dev/null; then
        sudo pacman -S --needed --noconfirm satty || true
    fi
    if ! command -v satty >/dev/null 2>&1; then
        mkdir -p "${HOME}/.local/bin" /tmp/satty-extract
        PKG_URL=$(pacman -Sp satty 2>/dev/null | grep "^http" | head -n 1 || true)
        if [[ -n "$PKG_URL" ]]; then
            curl -sL "$PKG_URL" -o /tmp/satty-pkg.tar.zst
            tar -xf /tmp/satty-pkg.tar.zst -C /tmp/satty-extract 2>/dev/null || true
            if [[ -f /tmp/satty-extract/usr/bin/satty ]]; then
                cp /tmp/satty-extract/usr/bin/satty "${HOME}/.local/bin/satty"
                chmod +x "${HOME}/.local/bin/satty"
            fi
            rm -rf /tmp/satty-pkg.tar.zst /tmp/satty-extract
        fi
    fi
fi

# 2. Cấu hình Satty (vẽ bút pen, hình khối shape, tự thoát khi copy...)
mkdir -p "${HOME}/.config/satty"
cat <<'EOF' > "${HOME}/.config/satty/config.toml"
[general]
fullscreen = false
early-exit = ["copy"]
initial-tool = "brush"
copy-command = "wl-copy"
corner-roundness = 8
save-after-copy = true
actions-on-enter = ["save-to-clipboard", "save-to-file", "exit"]
EOF

# 3. Tạo script chụp màn hình tự động copy và popup edit
mkdir -p "${HOME}/.local/bin"
cat <<'EOF' > "${HOME}/.local/bin/dms-screenshot-area.sh"
#!/usr/bin/env bash
set -eo pipefail

export PATH="${HOME}/.local/bin:${PATH}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_CURRENT_DESKTOP="${XDG_CURRENT_DESKTOP:-Hyprland}"

MODE="${1:-region}"
SCREENSHOT_DIR="${HOME}/Pictures/Screenshots"
mkdir -p "$SCREENSHOT_DIR"

SATTY="${HOME}/.local/bin/satty"
if command -v satty >/dev/null 2>&1; then
    SATTY=$(command -v satty)
fi

if [[ "$MODE" == "full" ]]; then
    IMG_FILE=$(dms screenshot full --no-notify 2>/dev/null || true)
else
    # Region mode: kéo thả chọn vùng tự chụp ngay khi nhả chuột, không cần bấm Enter
    IMG_FILE=$(dms screenshot --no-confirm --no-notify 2>/dev/null || true)
fi

# Nếu người dùng hủy hoặc không có file trả về
if [[ -z "$IMG_FILE" || ! -f "$IMG_FILE" ]]; then
    LATEST=$(find "$SCREENSHOT_DIR" -maxdepth 1 -name "screenshot_*.png" -mmin -0.1 2>/dev/null | sort -r | head -n 1)
    if [[ -n "$LATEST" && -f "$LATEST" ]]; then
        IMG_FILE="$LATEST"
    else
        exit 0
    fi
fi

# Đảm bảo chắc chắn ảnh được nạp vào clipboard dưới dạng image/png
if command -v wl-copy >/dev/null 2>&1; then
    wl-copy -t image/png < "$IMG_FILE" 2>/dev/null || true
fi

# Hiển thị mini popup thông báo ở góc màn hình có ảnh thumbnail và 1 nút duy nhất
ACTION=$(notify-send \
    -a "Chụp màn hình" \
    -i "$IMG_FILE" \
    -t 6000 \
    -A edit="Chỉnh sửa ảnh" \
    "Đã chụp ảnh màn hình" \
    "Ảnh đã sao chép vào clipboard.\nNhấp nút bên dưới để chỉnh sửa." \
    2>/dev/null || true)

if [[ -n "$ACTION" ]]; then
    "$SATTY" --filename "$IMG_FILE" --output-filename "$IMG_FILE" --early-exit copy
fi
EOF
chmod +x "${HOME}/.local/bin/dms-screenshot-area.sh"

# 4. Thêm Window Rule cho Satty để mở cửa sổ dạng floating ở giữa màn hình
if [[ -f "$WINDOWRULES_FILE" ]]; then
    if ! grep -q "satty" "$WINDOWRULES_FILE"; then
        sed -i '/-- Apps/a hl.window_rule({ match = { class = "^(com\\.gabm\\.satty|satty)$" }, float = true, center = true, size = { "max(monitor_w, monitor_h)*0.65", "min(monitor_w, monitor_h)*0.75" } })' "$WINDOWRULES_FILE"
    fi
fi

# 5. Cấu hình phím tắt trong binds.lua
python3 - <<'EOF'
import sys
import re
from pathlib import Path

binds_path = Path.home() / ".config" / "hypr" / "config" / "binds.lua"
content = binds_path.read_text(encoding="utf-8")

backup_path = binds_path.with_suffix(".lua.bak")
if not backup_path.exists():
    backup_path.write_text(content, encoding="utf-8")

# Thay thế di chuyển cửa sổ (Window move)
old_move_pattern = re.compile(
    r'(hl\.bind\(mainMod \.\. " \+ SHIFT \+ " \.\. digitCode\(1\),     hl\.dsp\.window\.move\(\{ monitor = MONITOR1 \}\)\)\n'
    r'hl\.bind\(mainMod \.\. " \+ SHIFT \+ " \.\. digitCode\(2\),     hl\.dsp\.window\.move\(\{ monitor = MONITOR2 \}\)\)\n'
    r'hl\.bind\(mainMod \.\. " \+ SHIFT \+ " \.\. digitCode\(3\),     hl\.dsp\.window\.move\(\{ monitor = MONITOR3 \}\)\)|'
    r'-- Move active window to workspace number \(SUPER \+ SHIFT \+ 1\.\.9\)\n'
    r'for i = 1, NUM_WPM do\n'
    r'    local key = i % 10\n'
    r'    hl\.bind\(mainMod \.\. " \+ SHIFT \+ " \.\. (?:digitCode\(key\)|key), hl\.dsp\.window\.move\(\{ workspace = i \}\)\)\n'
    r'end\n'
    r'-- Move active window to monitor \(SUPER \+ ALT \+ SHIFT \+ 1\.\.3\)\n'
    r'hl\.bind\(mainMod \.\. " \+ ALT \+ SHIFT \+ " \.\. (?:digitCode\(1\)|1), hl\.dsp\.window\.move\(\{ monitor = MONITOR1 \}\)\)\n'
    r'hl\.bind\(mainMod \.\. " \+ ALT \+ SHIFT \+ " \.\. (?:digitCode\(2\)|2), hl\.dsp\.window\.move\(\{ monitor = MONITOR2 \}\)\)\n'
    r'hl\.bind\(mainMod \.\. " \+ ALT \+ SHIFT \+ " \.\. (?:digitCode\(3\)|3), hl\.dsp\.window\.move\(\{ monitor = MONITOR3 \}\)\))'
)
new_move_content = (
    '-- Move active window to workspace number (SUPER + SHIFT + 1..9)\n'
    'for i = 1, NUM_WPM do\n'
    '    local key = i % 10\n'
    '    hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))\n'
    'end\n'
    '-- Move active window to monitor (SUPER + ALT + SHIFT + 1..3)\n'
    'hl.bind(mainMod .. " + ALT + SHIFT + 1", hl.dsp.window.move({ monitor = MONITOR1 }))\n'
    'hl.bind(mainMod .. " + ALT + SHIFT + 2", hl.dsp.window.move({ monitor = MONITOR2 }))\n'
    'hl.bind(mainMod .. " + ALT + SHIFT + 3", hl.dsp.window.move({ monitor = MONITOR3 }))'
)
if old_move_pattern.search(content):
    content = old_move_pattern.sub(new_move_content, content, count=1)
    old_shift_alt_loop = re.compile(
        r'for i = 1, NUM_WPM do\n\s*local key = i % 10\n\s*hl\.bind\(mainMod \.\. " \+ SHIFT \+ ALT \+ " \.\. digitCode\(key\), hl\.dsp\.window\.move\(\{ workspace = "m~" \.\. i, follow = false \}\)\)\nend\n?'
    )
    content = old_shift_alt_loop.sub('', content)

# Thay thế chuyển workspace & monitors
old_ws_pattern = re.compile(
    r'(-- Focus on monitors\n'
    r'hl\.bind\(mainMod \.\. " \+ " \.\. digitCode\(1\), hl\.dsp\.focus\(\{ monitor = MONITOR1 \}\)\)\n'
    r'hl\.bind\(mainMod \.\. " \+ " \.\. digitCode\(2\), hl\.dsp\.focus\(\{ monitor = MONITOR2 \}\)\)\n'
    r'hl\.bind\(mainMod \.\. " \+ " \.\. digitCode\(3\), hl\.dsp\.focus\(\{ monitor = MONITOR3 \}\)\)\n\n'
    r'-- Focus on workspace number\n'
    r'-- Absolute\n'
    r'for i = 1, NUM_WPM do\n'
    r'    local key = i % 10\n'
    r'    hl\.bind\(mainMod \.\. " \+ ALT \+ " \.\. digitCode\(key\), hl\.dsp\.focus\(\{ workspace = i \}\)\)\n'
    r'end|'
    r'-- Focus on workspace number\n'
    r'-- Absolute \(SUPER \+ 1\.\.9\)\n'
    r'for i = 1, NUM_WPM do\n'
    r'    local key = i % 10\n'
    r'    hl\.bind\(mainMod \.\. " \+ " \.\. (?:digitCode\(key\)|key), hl\.dsp\.focus\(\{ workspace = i \}\)\)\n'
    r'end\n\n'
    r'-- Focus on monitors \(SUPER \+ ALT \+ 1\.\.3\)\n'
    r'hl\.bind\(mainMod \.\. " \+ ALT \+ " \.\. (?:digitCode\(1\)|1), hl\.dsp\.focus\(\{ monitor = MONITOR1 \}\)\)\n'
    r'hl\.bind\(mainMod \.\. " \+ ALT \+ " \.\. (?:digitCode\(2\)|2), hl\.dsp\.focus\(\{ monitor = MONITOR2 \}\)\)\n'
    r'hl\.bind\(mainMod \.\. " \+ ALT \+ " \.\. (?:digitCode\(3\)|3), hl\.dsp\.focus\(\{ monitor = MONITOR3 \}\)\))'
)
new_ws_content = (
    '-- Focus on workspace number\n'
    '-- Absolute (SUPER + 1..9)\n'
    'for i = 1, NUM_WPM do\n'
    '    local key = i % 10\n'
    '    hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = i }))\n'
    'end\n\n'
    '-- Focus on monitors (SUPER + ALT + 1..3)\n'
    'hl.bind(mainMod .. " + ALT + 1", hl.dsp.focus({ monitor = MONITOR1 }))\n'
    'hl.bind(mainMod .. " + ALT + 2", hl.dsp.focus({ monitor = MONITOR2 }))\n'
    'hl.bind(mainMod .. " + ALT + 3", hl.dsp.focus({ monitor = MONITOR3 }))'
)
if old_ws_pattern.search(content):
    content = old_ws_pattern.sub(new_ws_content, content, count=1)

# Làm sạch các phím relative còn dính digitCode
content = re.sub(
    r'hl\.bind\(mainMod \.\. " \+ SHIFT \+ CONTROL \+ " \.\. digitCode\(key\),',
    'hl.bind(mainMod .. " + SHIFT + CONTROL + " .. key,',
    content
)
content = re.sub(
    r'hl\.bind\(mainMod \.\. " \+ CONTROL \+ " \.\. digitCode\(key\),',
    'hl.bind(mainMod .. " + CONTROL + " .. key,',
    content
)

# Thay thế Scratchpad move bằng SUPER + ALT + S để nhường SUPER + SHIFT + S cho chụp màn hình
content = re.sub(
    r'hl\.bind\(mainMod \.\. " \+ SHIFT \+ S",\s*hl\.dsp\.window\.move\(\{\s*workspace\s*=\s*"special"\s*\}\)\)',
    'hl.bind(mainMod .. " + ALT + S", hl.dsp.window.move({ workspace = "special" }))',
    content
)

# Gán Screen capture sang dms-screenshot-area.sh
screen_capture_block = (
    '-- Screen Capture\n'
    'hl.bind(mainMod .. " + P",         hl.dsp.exec_cmd("hyprpicker -a -n"))\n'
    'hl.bind("Print",                   hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/dms-screenshot-area.sh region"))\n'
    'hl.bind(mainMod .. " + Print",     hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/dms-screenshot-area.sh full"))\n'
    'hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/dms-screenshot-area.sh region"))'
)
content = re.sub(
    r'-- Screen Capture.*?(?=\n\n-- Theming)',
    screen_capture_block,
    content,
    flags=re.DOTALL
)

# Gán phím tắt mở Dolphin (SUPER + SHIFT + F)
if 'mainMod .. " + SHIFT + F"' not in content:
    content = re.sub(
        r'(hl\.bind\(mainMod \.\. " \+ E",\s*hl\.dsp\.exec_cmd\(launchPrefix \.\. FILE_MANAGER\)\))',
        r'\1\nhl.bind(mainMod .. " + SHIFT + F",  hl.dsp.exec_cmd(launchPrefix .. FILE_MANAGER))',
        content
    )

# Gán phím tắt chuyển đổi Floating/Tiling (SUPER + SHIFT + T)
if 'mainMod .. " + SHIFT + T"' not in content:
    content = re.sub(
        r'(hl\.bind\(mainMod \.\. " \+ ALT \+ Space",\s*hl\.dsp\.window\.float\(\{ action = "toggle" \}\)\))',
        r'\1\nhl.bind(mainMod .. " + SHIFT + T",   hl.dsp.window.float({ action = "toggle" }))',
        content
    )

# Gán phím tắt chuyển đổi IME Anh / Việt (ALT + Shift, SHIFT + Alt)
if 'fcitx5-remote -t' not in content:
    ime_binds = (
        '\n-- Switch Vietnamese / English IME (Alt + Shift)\n'
        'hl.bind("ALT + Shift_L", hl.dsp.exec_cmd("fcitx5-remote -t"))\n'
        'hl.bind("SHIFT + Alt_L", hl.dsp.exec_cmd("fcitx5-remote -t"))\n'
        'hl.bind("ALT + Shift_R", hl.dsp.exec_cmd("fcitx5-remote -t"))\n'
        'hl.bind("SHIFT + Alt_R", hl.dsp.exec_cmd("fcitx5-remote -t"))\n'
    )
    if 'hl.bind(mainMod .. " + Tab"' in content:
        content = re.sub(r'(hl\.bind\(mainMod \.\. " \+ Tab".*\n)', r'\1' + ime_binds, content, count=1)
    else:
        content += ime_binds

# Bổ sung non_consuming vào các bind confirmOverview để không nuốt sự kiện nhả phím Alt
content = re.sub(
    r'hl\.bind\("((?:ALT \+ )?Alt_[LR])",\s*hl\.dsp\.exec_cmd\((?:dmsCall \.\. )?"hypr confirmOverview"\),\s*\{([^}]+)\}\)',
    lambda m: f'hl.bind("{m.group(1)}", hl.dsp.exec_cmd(dmsCall .. "hypr confirmOverview"), {{{m.group(2).replace("non_consuming = true,", "").replace("non_consuming = true", "").strip(", ")}, non_consuming = true }})',
    content
)

binds_path.write_text(content, encoding="utf-8")
print("Đã cập nhật file binds.lua thành công!")
EOF


# 6. Cấu hình biến môi trường Qt và theme cho Hyprland & systemd (fix lỗi Dolphin vừa trắng vừa đen khi mở bằng phím tắt)
log_info "Cấu hình biến môi trường Qt / Theme cho systemd user session..."
mkdir -p "${HOME}/.config/environment.d"
cat <<'EOF' > "${HOME}/.config/environment.d/10-theme.conf"
QT_QPA_PLATFORM="wayland;xcb"
QT_QPA_PLATFORMTHEME=qt6ct
ELECTRON_OZONE_PLATFORM_HINT=auto
HYPRCURSOR_THEME="Bibata-Modern-Ice"
HYPRCURSOR_SIZE=24
XCURSOR_THEME="Bibata-Modern-Ice"
XCURSOR_SIZE=24
EOF

log_info "Cập nhật biến môi trường Qt / Theme trong Hyprland environment.lua..."
HYPR_ENV="${HOME}/.config/hypr/config/environment.lua"
if [[ -f "$HYPR_ENV" ]]; then
    python3 - <<'EOF'
import re
from pathlib import Path

env_file = Path.home() / ".config" / "hypr" / "config" / "environment.lua"
if env_file.exists():
    content = env_file.read_text(encoding="utf-8")
    qt_vars = [
        'hl.env("QT_QPA_PLATFORM", "wayland;xcb")',
        'hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")',
        'hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")',
        'hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Ice")',
        'hl.env("HYPRCURSOR_SIZE", "24")',
        'hl.env("XCURSOR_THEME", "Bibata-Modern-Ice")',
        'hl.env("XCURSOR_SIZE", "24")',
    ]
    missing = [v for v in qt_vars if v not in content]
    if missing:
        lines_to_add = "\n".join(missing)
        if 'hl.env("PATH"' in content:
            content = re.sub(r'(hl\.env\("PATH".*\n)', r'\1' + lines_to_add + '\n', content, count=1)
        else:
            content = content + "\n" + lines_to_add + "\n"
        env_file.write_text(content, encoding="utf-8")
        print("Đã cập nhật environment.lua với các biến môi trường Qt/Theme.")
EOF
fi

# Đồng bộ trực tiếp vào session đang chạy
if command -v systemctl >/dev/null 2>&1; then
    systemctl --user set-environment QT_QPA_PLATFORMTHEME=qt6ct QT_QPA_PLATFORM="wayland;xcb" ELECTRON_OZONE_PLATFORM_HINT=auto HYPRCURSOR_THEME="Bibata-Modern-Ice" HYPRCURSOR_SIZE=24 XCURSOR_THEME="Bibata-Modern-Ice" XCURSOR_SIZE=24 2>/dev/null || true
fi
if command -v dbus-update-activation-environment >/dev/null 2>&1; then
    dbus-update-activation-environment --systemd QT_QPA_PLATFORMTHEME=qt6ct QT_QPA_PLATFORM="wayland;xcb" ELECTRON_OZONE_PLATFORM_HINT=auto 2>/dev/null || true
fi

# 7. Reload Hyprland nếu đang chạy
if pgrep -x "Hyprland" >/dev/null 2>&1; then
    log_info "Reload cấu hình Hyprland..."
    hyprctl reload >/dev/null 2>&1 || true
fi

log_success "Hoàn tất cấu hình phím tắt, chụp màn hình và giao diện Qt:"
echo -e "  - ${BOLD}SUPER + SHIFT + T${NC} (hoặc SUPER + ALT + Space) : Chuyển đổi Floating / Tiling của cửa sổ"
echo -e "  - ${BOLD}SUPER + SHIFT + F${NC} (hoặc SUPER + E) : Mở trình quản lý file Dolphin"

echo -e "  - ${BOLD}Giao diện Qt / Dolphin${NC}               : Đồng bộ Dark Theme (qt6ct) cho phím tắt và systemd"
echo -e "  - ${BOLD}SUPER + SHIFT + S${NC} (hoặc Print)     : Kéo chọn vùng màn hình -> Tự copy clipboard -> Hiện popup góc phải"
echo -e "  - ${BOLD}Popup góc phải${NC}                   : Bấm vào để mở cửa sổ chỉnh sửa ảnh (Satty: pen, shape, mũi tên, text)"
echo -e "  - ${BOLD}SUPER + Print${NC}                       : Chụp toàn màn hình"
echo -e "  - ${BOLD}SUPER + 1..9${NC}                        : Chuyển trực tiếp tới Workspace 1..9"
echo -e "  - ${BOLD}SUPER + SHIFT + 1..9${NC}                  : Di chuyển cửa sổ đang focus tới Workspace 1..9"
echo -e "  - ${BOLD}SUPER + S${NC}                             : Bật / ẩn Scratchpad"
echo -e "  - ${BOLD}SUPER + ALT + S${NC}                       : Di chuyển cửa sổ vào Scratchpad"

