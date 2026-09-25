#!/usr/bin/env bash
# Description: Cài đặt Cloudflare WARP 1.1.1.1, tối ưu chống rò rỉ DNS (DNS Leak), và tích hợp widget bật/tắt trên Control Center DankMaterialShell
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

log_info "Bắt đầu thiết lập Cloudflare WARP và widget Control Center cho DankMaterialShell..."

# ==============================================================================
# 1. Cài đặt gói Cloudflare WARP từ repository của CachyOS
# ==============================================================================
log_header "1. CÀI ĐẶT GÓI CLOUDFLARE WARP"
if ! pacman -Q cloudflare-warp-bin >/dev/null 2>&1; then
    log_info "Đang cài đặt cloudflare-warp-bin..."
    cache_sudo
    sudo pacman -S --needed --noconfirm cloudflare-warp-bin
else
    log_success "cloudflare-warp-bin đã được cài đặt trên hệ thống."
fi

# ==============================================================================
# 2. Kích hoạt và khởi chạy daemon warp-svc
# ==============================================================================
log_header "2. KÍCH HOẠT SERVICE WARP-SVC"
if ! systemctl is-active --quiet warp-svc; then
    cache_sudo
    log_info "Đang kích hoạt và khởi chạy warp-svc.service..."
    sudo systemctl enable --now warp-svc
    sleep 2
else
    log_success "Service warp-svc đang hoạt động."
fi

# ==============================================================================
# 3. Đăng ký thiết bị lần đầu (nếu chưa có registration)
# ==============================================================================
log_header "3. ĐĂNG KÝ THIẾT BỊ VỚI CLOUDFLARE"
if ! warp-cli registration show >/dev/null 2>&1; then
    log_info "Đang đăng ký thiết bị mới với Cloudflare WARP..."
    warp-cli --accept-tos registration new || warp-cli registration new || true
    log_success "Đã hoàn tất đăng ký thiết bị."
else
    log_success "Thiết bị đã được đăng ký với Cloudflare WARP từ trước."
fi

# ==============================================================================
# 4. Cấu hình DNS chống rò rỉ (Fix DNS Leak trên Linux / systemd-resolved)
# ==============================================================================
log_header "4. CẤU HÌNH CHỐNG RÒ RỈ DNS (DNS LEAK)"
if command -v nmcli >/dev/null 2>&1; then
    log_info "Thiết lập DNS 1.1.1.1 / 1.0.0.1 và chặn DNS router nhà mạng cho kết nối Ethernet/WiFi..."
    ACTIVE_CONNS=$(nmcli -t -f NAME,TYPE con show --active 2>/dev/null | grep -E "ethernet|wifi" | cut -d: -f1 || true)
    while IFS= read -r conn; do
        if [[ -n "$conn" ]]; then
            log_info "Cập nhật DNS cho: '$conn'..."
            nmcli con mod "$conn" ipv4.dns "1.1.1.1 1.0.0.1" ipv4.ignore-auto-dns yes 2>/dev/null || true
            nmcli con up "$conn" 2>/dev/null || true
        fi
    done <<< "$ACTIVE_CONNS"

    if command -v resolvectl >/dev/null 2>&1; then
        resolvectl flush-caches 2>/dev/null || true
    fi
    log_success "Đã cấu hình DNS sạch và xóa cache DNS hệ thống."
fi

# ==============================================================================
# 5. Cài đặt plugin Cloudflare WARP cho DankMaterialShell
# ==============================================================================
log_header "5. TÍCH HỢP WIDGET VÀO CONTROL CENTER DANKMATERIALSNELL"
PLUGIN_DIR="${HOME}/.config/DankMaterialShell/plugins/cloudflareWarp"
mkdir -p "$PLUGIN_DIR"

log_info "Tạo manifest plugin.json..."
cat <<'EOF' > "${PLUGIN_DIR}/plugin.json"
{
    "id": "cloudflareWarp",
    "name": "Cloudflare WARP",
    "description": "Quick toggle for Cloudflare WARP 1.1.1.1 VPN",
    "version": "1.0.0",
    "author": "HuyBach",
    "type": "widget",
    "capabilities": ["control-center", "dankbar-widget"],
    "component": "./WarpWidget.qml",
    "icon": "vpn_key",
    "permissions": ["settings_read", "settings_write"]
}
EOF

log_info "Tạo component WarpWidget.qml..."
cat <<'EOF' > "${PLUGIN_DIR}/WarpWidget.qml"
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool isConnected: false
    property bool isConnecting: false

    ccWidgetIcon: isConnected ? "vpn_lock" : (isConnecting ? "sync" : "vpn_key")
    ccWidgetPrimaryText: "Cloudflare WARP"
    ccWidgetSecondaryText: isConnecting ? "Connecting..." : (isConnected ? "Connected" : "Disconnected")
    ccWidgetIsActive: isConnected

    function toggleWarp() {
        if (isConnected) {
            isConnecting = false;
            isConnected = false;
            if (!disconnectProcess.running) {
                disconnectProcess.running = true;
            }
            ToastService.showInfo("Cloudflare WARP", "Disconnecting...");
        } else {
            isConnecting = true;
            if (!connectProcess.running) {
                connectProcess.running = true;
            }
            ToastService.showInfo("Cloudflare WARP", "Connecting...");
        }
    }

    onCcWidgetToggled: {
        toggleWarp();
    }

    // Horizontal bar pill for top/bottom DankBar
    horizontalBarPill: Component {
        StyledRect {
            width: pillRow.implicitWidth + Theme.spacingM * 2
            height: parent.widgetThickness
            radius: Theme.cornerRadius
            color: root.isConnected ? Theme.primaryContainer : Theme.surfaceContainerHigh

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    name: root.isConnected ? "vpn_lock" : (root.isConnecting ? "sync" : "vpn_key")
                    color: root.isConnected ? Theme.onPrimaryContainer : Theme.surfaceVariantText
                    size: Theme.iconSize - 4
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: root.isConnecting ? "WARP..." : (root.isConnected ? "WARP" : "OFF")
                    color: root.isConnected ? Theme.onPrimaryContainer : Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // Vertical bar pill for left/right DankBar
    verticalBarPill: Component {
        StyledRect {
            width: parent.widgetThickness
            height: vPillCol.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: root.isConnected ? Theme.primaryContainer : Theme.surfaceContainerHigh

            Column {
                id: vPillCol
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                DankIcon {
                    name: root.isConnected ? "vpn_lock" : (root.isConnecting ? "sync" : "vpn_key")
                    color: root.isConnected ? Theme.onPrimaryContainer : Theme.surfaceVariantText
                    size: Theme.iconSize - 4
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                StyledText {
                    text: root.isConnected ? "ON" : "OFF"
                    color: root.isConnected ? Theme.onPrimaryContainer : Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeSmall
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    pillClickAction: () => {
        root.toggleWarp();
    }

    // Status Checker Process
    Process {
        id: statusProcess
        command: ["warp-cli", "status"]
        running: false

        stdout: StdioCollector {
            onStreamFinished: {
                const out = text || "";
                if (out.indexOf("Connected") !== -1) {
                    root.isConnected = true;
                    root.isConnecting = false;
                } else if (out.indexOf("Connecting") !== -1) {
                    root.isConnected = false;
                    root.isConnecting = true;
                } else {
                    root.isConnected = false;
                    root.isConnecting = false;
                }
            }
        }
    }

    // Connect Process
    Process {
        id: connectProcess
        command: ["warp-cli", "connect"]
        running: false

        onExited: (exitCode, exitStatus) => {
            statusTimer.restart();
            if (!statusProcess.running) {
                statusProcess.running = true;
            }
        }
    }

    // Disconnect Process
    Process {
        id: disconnectProcess
        command: ["warp-cli", "disconnect"]
        running: false

        onExited: (exitCode, exitStatus) => {
            root.isConnected = false;
            root.isConnecting = false;
            statusTimer.restart();
            if (!statusProcess.running) {
                statusProcess.running = true;
            }
        }
    }

    // Periodic status refresh
    Timer {
        id: statusTimer
        interval: 3000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            if (!statusProcess.running && !connectProcess.running && !disconnectProcess.running) {
                statusProcess.running = true;
            }
        }
    }
}
EOF

# ==============================================================================
# 6. Cập nhật plugin_settings.json & settings.json của DankMaterialShell
# ==============================================================================
log_info "Kích hoạt plugin trong plugin_settings.json và thêm vào controlCenterWidgets..."
python3 - <<'EOF'
import json
from pathlib import Path

dms_dir = Path.home() / ".config" / "DankMaterialShell"

# 1. Kích hoạt trong plugin_settings.json
plugin_settings_file = dms_dir / "plugin_settings.json"
plugin_data = {}
if plugin_settings_file.exists():
    try:
        plugin_data = json.loads(plugin_settings_file.read_text(encoding="utf-8"))
    except Exception:
        plugin_data = {}

if "cloudflareWarp" not in plugin_data:
    plugin_data["cloudflareWarp"] = {"enabled": True}
else:
    plugin_data["cloudflareWarp"]["enabled"] = True

plugin_settings_file.write_text(json.dumps(plugin_data, indent=2), encoding="utf-8")

# 2. Thêm vào controlCenterWidgets trong settings.json
settings_file = dms_dir / "settings.json"
if settings_file.exists():
    try:
        settings_data = json.loads(settings_file.read_text(encoding="utf-8"))
    except Exception:
        settings_data = {}

    default_widgets = [
        {"id": "volumeSlider", "enabled": True, "width": 50},
        {"id": "brightnessSlider", "enabled": True, "width": 50},
        {"id": "wifi", "enabled": True, "width": 50},
        {"id": "bluetooth", "enabled": True, "width": 50},
        {"id": "audioOutput", "enabled": True, "width": 50},
        {"id": "audioInput", "enabled": True, "width": 50},
        {"id": "nightMode", "enabled": True, "width": 50},
        {"id": "darkMode", "enabled": True, "width": 50}
    ]

    if "controlCenterWidgets" not in settings_data:
        settings_data["controlCenterWidgets"] = default_widgets + [{"id": "plugin_cloudflareWarp", "enabled": True, "width": 50}]
    else:
        existing_ids = [w.get("id") for w in settings_data["controlCenterWidgets"]]
        if "plugin_cloudflareWarp" not in existing_ids:
            settings_data["controlCenterWidgets"].append({"id": "plugin_cloudflareWarp", "enabled": True, "width": 50})

    settings_file.write_text(json.dumps(settings_data, indent=2), encoding="utf-8")
EOF

# ==============================================================================
# 7. Tải lại cấu hình DMS nếu đang chạy
# ==============================================================================
if pgrep -x "dms" >/dev/null 2>&1 || pgrep -f "qs.*DankMaterialShell" >/dev/null 2>&1; then
    log_info "Đang áp dụng thay đổi vào DankMaterialShell..."
    if command -v dms >/dev/null 2>&1; then
        dms restart >/dev/null 2>&1 || true
    fi
fi

log_success "Hoàn tất cài đặt Cloudflare WARP và widget Control Center!"
