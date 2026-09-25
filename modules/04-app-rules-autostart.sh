#!/usr/bin/env bash
# Description: Gán ứng dụng vào đúng Workspace (Edge, Helium, VSCode, Chromium) & thiết lập tự khởi động khi mở máy
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

log_info "Bắt đầu thiết lập Window Rules và Autostart cho các ứng dụng..."

HYPR_CONFIG_DIR="${HOME}/.config/hypr/config"
WINDOWRULES_FILE="${HYPR_CONFIG_DIR}/windowrules.lua"
AUTOSTART_FILE="${HYPR_CONFIG_DIR}/autostart.lua"

# 1. Cấu hình Window Rules cho các app gán vào đúng workspace
log_info "Cập nhật Window Rules trong windowrules.lua..."
if [[ -f "$WINDOWRULES_FILE" ]]; then
    # Kiểm tra nếu chưa có cấu hình gán workspace cho app
    if ! grep -q "Workspace assignment for specific apps" "$WINDOWRULES_FILE"; then
        python3 - <<'EOF'
import re

path = "/home/huybach02/.config/hypr/config/windowrules.lua"
with open(path, "r") as f:
    content = f.read()

rules = """-- Workspace assignment for specific apps
hl.window_rule({ match = { class = "^([Mm]icrosoft-[Ee]dge.*)$" }, workspace = "1" })
hl.window_rule({ match = { class = "^([Hh]elium.*)$" }, workspace = "2" })
hl.window_rule({ match = { class = "^([Cc]ode|code-url-handler)$" }, workspace = "3" })
hl.window_rule({ match = { class = "^([Cc]hromium.*)$" }, workspace = "4" })

"""

if "-- Apps" in content:
    content = content.replace("-- Apps", rules + "-- Apps")
else:
    content = content + "\n" + rules

with open(path, "w") as f:
    f.write(content)
EOF
    fi
fi

# 2. Cấu hình Autostart
log_info "Cập nhật danh sách ứng dụng tự khởi động trong autostart.lua..."
cat <<'EOF' > "$AUTOSTART_FILE"
-- Auto-start config
-- if you dont use UWSM add your auto start programs here, otherwise use XDG autostart https://wiki.archlinux.org/title/XDG_Autostart

hl.on("hyprland.start", function ()
    hl.exec_cmd("dbus-update-activation-environment --systemd --all")
    hl.exec_cmd("dms run")
    hl.exec_cmd("xhost +SI:localuser:root")

    -- Tự động mở các ứng dụng theo từng Workspace chỉ định khi khởi động
    hl.exec_cmd("microsoft-edge-stable")
    hl.exec_cmd("helium-browser")
    hl.exec_cmd("code")
    hl.exec_cmd("chromium")
    if [[ -f "${HOME}/.local/bin/hypr-emulator-toolbar-sync.py" ]]; then
        hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/hypr-emulator-toolbar-sync.py")
    fi
end)
EOF

# 3. Reload Hyprland
if pgrep -x "Hyprland" >/dev/null 2>&1; then
    log_info "Đang reload Hyprland..."
    hyprctl reload >/dev/null 2>&1 || true
fi

log_success "Hoàn tất cấu hình App Window Rules & Autostart:"
echo -e "  - Workspace 1 (Edge):     microsoft-edge-stable"
echo -e "  - Workspace 2 (Helium):   helium-browser"
echo -e "  - Workspace 3 (VSCode):   code"
echo -e "  - Workspace 4 (Chromium): chromium"
