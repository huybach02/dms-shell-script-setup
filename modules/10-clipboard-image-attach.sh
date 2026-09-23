#!/usr/bin/env bash
# ==============================================================================
# Module 10: Clipboard Image Attachment for AI Agents & Terminals
# Description: Tự động đính kèm ảnh từ clipboard vào terminal / AI agent (Kitty Kitten & Hyprland keybind)
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

log_header "MODULE 10: TỰ ĐỘNG ĐÍNH KÈM ẢNH TỪ CLIPBOARD VÀO TERMINAL / AI AGENT"

# 1. Cài đặt các gói phụ thuộc cần thiết
log_info "1/5. Kiểm tra và cài đặt các tiện ích hỗ trợ (wl-clipboard, wtype, jq, libnotify)..."
DEPENDENCIES=()
for pkg in wl-clipboard wtype jq libnotify; do
    if ! pacman -Qi "$pkg" &>/dev/null; then
        DEPENDENCIES+=("$pkg")
    fi
done

if [[ ${#DEPENDENCIES[@]} -gt 0 ]]; then
    log_info "Cài đặt các gói: ${DEPENDENCIES[*]}"
    sudo pacman -S --noconfirm --needed "${DEPENDENCIES[@]}"
else
    log_info "Các tiện ích phụ thuộc đã được cài đặt đầy đủ."
fi

# 2. Tạo Kitty Kitten: ~/.config/kitty/kittens/paste_image.py
log_info "2/5. Cấu hình Kitty Kitten (paste_image.py)..."
KITTY_KITTEN_DIR="${HOME}/.config/kitty/kittens"
mkdir -p "$KITTY_KITTEN_DIR"
KITTEN_FILE="${KITTY_KITTEN_DIR}/paste_image.py"

cat << 'EOF' > "$KITTEN_FILE"
#!/usr/bin/env python3
"""
Kitty Kitten: Paste Image from Clipboard as File Path
When the user presses Ctrl+Shift+V:
- If the clipboard contains an image (PNG, JPEG, WebP):
  1. Saves the image data to ~/Pictures/Screenshots/clipboard_<timestamp>.<ext>
  2. Pastes the quoted path (e.g. '/home/user/Pictures/Screenshots/clipboard_...png' ) directly into terminal.
  3. Sends a gentle notification via notify-send.
- If the clipboard contains text or anything else:
  Falls back immediately to standard clipboard paste without any delay.
"""

import os
import subprocess
import time
from kitty.boss import Boss
from kittens.tui.handler import result_handler


def main(args):
    pass


@result_handler(no_ui=True)
def handle_result(args, answer, target_window_id, boss: Boss):
    w = boss.window_id_map.get(target_window_id)
    if w is None:
        w = boss.active_window
    if w is None:
        return

    # Check clipboard mime types via wl-paste
    has_image = False
    mime = "image/png"
    try:
        types_raw = subprocess.check_output(
            ["wl-paste", "--list-types"],
            text=True,
            stderr=subprocess.DEVNULL,
            timeout=1
        )
        types = set(types_raw.splitlines())

        if "image/png" in types:
            has_image = True
            mime = "image/png"
        elif "image/jpeg" in types:
            has_image = True
            mime = "image/jpeg"
        elif "image/webp" in types:
            has_image = True
            mime = "image/webp"
    except Exception:
        has_image = False

    if has_image:
        screenshots_dir = os.path.expanduser("~/Pictures/Screenshots")
        os.makedirs(screenshots_dir, exist_ok=True)
        timestamp = time.strftime("%Y-%m-%d_%H-%M-%S")
        ext = "png" if mime == "image/png" else ("jpg" if mime == "image/jpeg" else "webp")
        filepath = os.path.join(screenshots_dir, f"clipboard_{timestamp}.{ext}")

        try:
            with open(filepath, "wb") as f:
                subprocess.run(
                    ["wl-paste", "--type", mime],
                    stdout=f,
                    check=True,
                    timeout=2
                )
            if os.path.exists(filepath) and os.path.getsize(filepath) > 0:
                w.paste_text(f"'{filepath}' ")
                try:
                    subprocess.Popen([
                        "notify-send",
                        "-a", "Clipboard",
                        "-i", filepath,
                        "-t", "1800",
                        "Đã đính kèm ảnh",
                        f"Đã chèn {os.path.basename(filepath)} vào terminal"
                    ])
                except Exception:
                    pass
                return
        except Exception:
            pass

    # Standard clipboard text paste fallback
    boss.paste_from_clipboard()
EOF

chmod +x "$KITTEN_FILE"
log_success "Đã cập nhật Kitty kitten: $KITTEN_FILE"

# 3. Cập nhật kitty.conf
log_info "3/5. Cập nhật phím tắt trong ~/.config/kitty/kitty.conf..."
KITTY_CONF="${HOME}/.config/kitty/kitty.conf"
if [[ -f "$KITTY_CONF" ]]; then
    if ! grep -q "kitten kittens/paste_image.py" "$KITTY_CONF"; then
        echo "" >> "$KITTY_CONF"
        echo "# Clipboard image paste: saves image and pastes file path, or pastes text normally" >> "$KITTY_CONF"
        echo "map ctrl+shift+v kitten kittens/paste_image.py" >> "$KITTY_CONF"
        log_success "Đã thêm mapping ctrl+shift+v vào kitty.conf"
    else
        log_info "kitty.conf đã được cấu hình mapping paste_image.py từ trước."
    fi
fi

# Reload Kitty config nếu Kitty đang chạy
if pidof kitty &>/dev/null; then
    kill -SIGUSR1 $(pidof kitty) 2>/dev/null || true
    log_info "Đã gửi tín hiệu reload tới Kitty."
fi

# 4. Tạo script dán ảnh toàn hệ thống: ~/.local/bin/paste-clipboard-image.sh
log_info "4/5. Cài đặt script dán ảnh toàn hệ thống (~/.local/bin/paste-clipboard-image.sh)..."
LOCAL_BIN="${HOME}/.local/bin"
mkdir -p "$LOCAL_BIN"
GLOBAL_SCRIPT="${LOCAL_BIN}/paste-clipboard-image.sh"

cat << 'EOF' > "$GLOBAL_SCRIPT"
#!/usr/bin/env bash
set -eo pipefail

SCREENSHOT_DIR="${HOME}/Pictures/Screenshots"
mkdir -p "$SCREENSHOT_DIR"

# Kiểm tra loại dữ liệu trong clipboard
TYPES=$(wl-paste --list-types 2>/dev/null || true)
MIME=""
EXT="png"

if echo "$TYPES" | grep -qx "image/png"; then
    MIME="image/png"
    EXT="png"
elif echo "$TYPES" | grep -qx "image/jpeg"; then
    MIME="image/jpeg"
    EXT="jpg"
elif echo "$TYPES" | grep -qx "image/webp"; then
    MIME="image/webp"
    EXT="webp"
fi

if [[ -z "$MIME" ]]; then
    notify-send -t 1500 -a "Clipboard" "Không có ảnh" "Clipboard hiện không chứa hình ảnh." 2>/dev/null || true
    exit 0
fi

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
IMG_PATH="${SCREENSHOT_DIR}/clipboard_${TIMESTAMP}.${EXT}"

# Lưu ảnh từ clipboard ra file
wl-paste --type "$MIME" > "$IMG_PATH"

if [[ ! -s "$IMG_PATH" ]]; then
    rm -f "$IMG_PATH"
    exit 0
fi

# Chờ người dùng nhả phím modifier (Super / Shift / Alt)
sleep 0.15

# Lưu đường dẫn kèm dấu nháy đơn và khoảng trắng vào clipboard
wl-copy "'$IMG_PATH' " 2>/dev/null || true

# Xác định cửa sổ đang active để dán phù hợp
ACTIVE_CLASS=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // empty' 2>/dev/null || true)

if [[ "$ACTIVE_CLASS" =~ ^(kitty|Alacritty|foot|wezterm|ghostty)$ ]]; then
    wtype -M ctrl -M shift -k v -m shift -m ctrl 2>/dev/null || true
else
    wtype -M ctrl -k v -m ctrl 2>/dev/null || true
fi

notify-send \
    -a "Clipboard" \
    -i "$IMG_PATH" \
    -t 1800 \
    "Đã đính kèm ảnh" \
    "Đã dán $(basename "$IMG_PATH") vào cửa sổ" 2>/dev/null || true
EOF

chmod +x "$GLOBAL_SCRIPT"
log_success "Đã cập nhật script: $GLOBAL_SCRIPT"

# 5. Cấu hình phím tắt trong Hyprland (binds.lua)
log_info "5/5. Cấu hình phím tắt trong Hyprland (binds.lua)..."
BINDS_LUA="${HOME}/.config/hypr/config/binds.lua"
if [[ -f "$BINDS_LUA" ]]; then
    if ! grep -q "paste-clipboard-image.sh" "$BINDS_LUA"; then
        # Thêm keybind SUPER + SHIFT + V và SUPER + ALT + V sau phần Clipboard
        sed -i '/dmsCall \.\. "clipboard toggle"/a hl.bind(mainMod .. " + SHIFT + V", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/paste-clipboard-image.sh"))\nhl.bind(mainMod .. " + ALT + V",   hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/paste-clipboard-image.sh"))' "$BINDS_LUA"
        log_success "Đã thêm phím tắt SUPER+SHIFT+V và SUPER+ALT+V vào binds.lua"
    else
        log_info "binds.lua đã có cấu hình paste-clipboard-image.sh từ trước."
    fi
    hyprctl reload &>/dev/null || true
    log_info "Đã reload cấu hình Hyprland."
fi

log_success "HOÀN THÀNH SETUP ĐÍNH KÈM ẢNH TỪ CLIPBOARD VÀO TERMINAL / AI AGENT!"
