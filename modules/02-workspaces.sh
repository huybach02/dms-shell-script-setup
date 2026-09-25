#!/usr/bin/env bash
# Description: Thiết lập các workspace cố định (1-Edge, 3-VSCode, 5, 6, 7 trên màn Philips; 2-Helium, 4-Chromium, 8, 9 trên màn AOC)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

log_info "Bắt đầu thiết lập cấu hình Workspaces..."

HYPR_CONFIG_DIR="${HOME}/.config/hypr/config"
VARIABLES_FILE="${HYPR_CONFIG_DIR}/variables.lua"
WORKSPACES_FILE="${HYPR_CONFIG_DIR}/workspaces.lua"
DMS_SETTINGS="${HOME}/.config/DankMaterialShell/settings.json"

# 1. Cập nhật số lượng workspace trong variables.lua để hỗ trợ phím tắt tới workspace 9
if [[ -f "$VARIABLES_FILE" ]]; then
    log_info "Cập nhật NUM_WPM = 9 trong variables.lua..."
    sed -i -E 's/^NUM_WPM[[:space:]]*=.*/NUM_WPM = 9 -- Number of workspaces per monitor (Max 10)/' "$VARIABLES_FILE"
fi

# 2. Ghi cấu hình workspaces.lua
log_info "Ghi đè cấu hình workspaces.lua theo danh sách chỉ định..."
cat <<'EOF' > "$WORKSPACES_FILE"
-- Workspace rules wiki https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- Cấu hình Workspaces:
-- 1 => Edge (Philips)
-- 2 => Helium (AOC)
-- 3 => VSCode (Philips)
-- 4 => Chromium (AOC)
-- 5 => 5 (Philips)
-- 6 => 6 (Philips)
-- 7 => 7 (Philips)
-- 8 => 8 (AOC)
-- 9 => 9 (AOC)

-- Workspace 1: Edge (Màn hình Philips - MONITOR1)
hl.workspace_rule({ workspace = "1", monitor = MONITOR1, default = true, persistent = true, default_name = "Edge" })

-- Workspace 2: Helium (Màn hình AOC - MONITOR2)
hl.workspace_rule({ workspace = "2", monitor = MONITOR2, default = true, persistent = true, default_name = "Helium" })

-- Workspace 3: VSCode (Màn hình Philips - MONITOR1)
hl.workspace_rule({ workspace = "3", monitor = MONITOR1, default = true, persistent = true, default_name = "VSCode" })

-- Workspace 4: Chromium (Màn hình AOC - MONITOR2)
hl.workspace_rule({ workspace = "4", monitor = MONITOR2, default = true, persistent = true, default_name = "Chromium" })

-- Workspace 5: 5 (Màn hình Philips - MONITOR1)
hl.workspace_rule({ workspace = "5", monitor = MONITOR1, default = true, persistent = true, default_name = "5" })

-- Workspaces 6, 7: Cố định trên màn hình Philips (MONITOR1)
hl.workspace_rule({ workspace = "6", monitor = MONITOR1, default = true, persistent = true, default_name = "6" })
hl.workspace_rule({ workspace = "7", monitor = MONITOR1, default = true, persistent = true, default_name = "7" })

-- Workspaces 8, 9: Cố định trên màn hình AOC (MONITOR2)
hl.workspace_rule({ workspace = "8", monitor = MONITOR2, default = true, persistent = true, default_name = "8" })
hl.workspace_rule({ workspace = "9", monitor = MONITOR2, default = true, persistent = true, default_name = "9" })
EOF

# 3. Kích hoạt hiển thị Tên Workspace trên thanh bar (DankMaterialShell)
log_info "Kích hoạt hiển thị tên Workspace trên thanh DankMaterialShell..."
if [[ -f "$DMS_SETTINGS" ]]; then
    tmp=$(mktemp)
    jq '.showWorkspaceName = true' "$DMS_SETTINGS" > "$tmp" && mv "$tmp" "$DMS_SETTINGS"
fi

if pgrep -x "dms" >/dev/null 2>&1; then
    dms ipc call settings set showWorkspaceName true >/dev/null 2>&1 || true
    dms restart >/dev/null 2>&1 || true
fi

# 4. Áp dụng ngay nếu Hyprland đang chạy
if pgrep -x "Hyprland" >/dev/null 2>&1; then
    log_info "Đang reload Hyprland và cập nhật trực tiếp tên, vị trí các workspace..."
    hyprctl reload >/dev/null 2>&1 || true

    # Đổi tên và di chuyển vị trí các workspace đang chạy trong session hiện tại
    hyprctl repl 'pcall(function()
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 1, name = "Edge" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 2, name = "Helium" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 3, name = "VSCode" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 4, name = "Chromium" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 5, name = "5" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 6, name = "6" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 7, name = "7" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 8, name = "8" }))
        hl.dispatch(hl.dsp.workspace.rename({ workspace = 9, name = "9" }))
        hl.dispatch(hl.dsp.workspace.move({ workspace = "6", monitor = "HDMI-A-2" }))
        hl.dispatch(hl.dsp.workspace.move({ workspace = "7", monitor = "HDMI-A-2" }))
        hl.dispatch(hl.dsp.workspace.move({ workspace = "8", monitor = "DP-2" }))
        hl.dispatch(hl.dsp.workspace.move({ workspace = "9", monitor = "DP-2" }))
    end)' >/dev/null 2>&1 || true
fi

log_success "Hoàn tất thiết lập Workspace:"
echo -e "  - Màn hình Philips (Trái): Workspace 1 (Edge), 3 (VSCode), 5 (5), 6 (6), 7 (7)"
echo -e "  - Màn hình AOC (Phải):    Workspace 2 (Helium), 4 (Chromium), 8 (8), 9 (9)"
