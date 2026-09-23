#!/usr/bin/env bash
# Description: Cài đặt và cấu hình plugin DankMaterialShell (Antigravity Usage theo dõi quota & hiển thị email trên taskbar)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

log_info "Bắt đầu thiết lập plugin Antigravity Usage cho DankMaterialShell..."

# 1. Kiểm tra các gói phụ thuộc cần thiết
REQUIRED_PKGS=()
for pkg in jq curl secret-tool; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        REQUIRED_PKGS+=("$pkg")
    fi
done

if [[ ${#REQUIRED_PKGS[@]} -gt 0 ]]; then
    log_info "Cài đặt các phụ thuộc: ${REQUIRED_PKGS[*]}..."
    cache_sudo
    sudo pacman -S --needed --noconfirm "${REQUIRED_PKGS[@]}"
fi

# 2. Cài đặt plugin Antigravity Usage vào thư mục DMS plugins
PLUGIN_DIR="${HOME}/.config/DankMaterialShell/plugins/antigravityUsage"
mkdir -p "${HOME}/.config/DankMaterialShell/plugins"

if [[ ! -d "$PLUGIN_DIR" ]]; then
    log_info "Đang clone plugin dms-antigravity-cli..."
    git clone https://github.com/FeikoWielsma/dms-antigravity-cli.git "$PLUGIN_DIR"
else
    log_info "Plugin đã tồn tại tại $PLUGIN_DIR"
fi

if [[ -f "${PLUGIN_DIR}/get-agy-usage" ]]; then
    chmod +x "${PLUGIN_DIR}/get-agy-usage"
fi

# 3. Patch get-agy-usage và AntigravityUsageWidget.qml để hỗ trợ hiển thị Email tài khoản
python3 - <<'EOF'
from pathlib import Path
import re

plugin_dir = Path.home() / ".config" / "DankMaterialShell" / "plugins" / "antigravityUsage"
script_file = plugin_dir / "get-agy-usage"
widget_file = plugin_dir / "AntigravityUsageWidget.qml"

# Patch get-agy-usage
if script_file.exists():
    content = script_file.read_text(encoding="utf-8")
    if "jwt_payload=" not in content:
        old_pattern = 'ACCOUNT=$(printf \'%s\' "$KEYRING_JSON" | jq -r \'.account // .email // empty\' 2>/dev/null || true)'
        new_pattern = (
            'ACCOUNT=$(printf \'%s\' "$KEYRING_JSON" | jq -r \'.account // .email // empty\' 2>/dev/null || true)\n'
            '# Extract email from id_token in keyring blob if available\n'
            'if [ -z "$ACCOUNT" ]; then\n'
            '    jwt_payload=$(printf \'%s\' "$KEYRING_JSON" | jq -r \'.id_token // .token.id_token // empty\' 2>/dev/null | cut -d. -f2 || true)\n'
            '    if [ -n "$jwt_payload" ]; then\n'
            '        pad=$(( (4 - ${#jwt_payload} % 4) % 4 ))\n'
            '        [ "$pad" -gt 0 ] && jwt_payload="${jwt_payload}$(printf \'%*s\' "$pad" | tr \' \' \'=\')"\n'
            '        ACCOUNT=$(printf \'%s\' "$jwt_payload" | tr \'_-\' \'/+\' | base64 -d 2>/dev/null | jq -r \'.email // empty\' 2>/dev/null || true)\n'
            '    fi\n'
            'fi'
        )
        if old_pattern in content:
            content = content.replace(old_pattern, new_pattern, 1)
            script_file.write_text(content, encoding="utf-8")
            print("Đã patch get-agy-usage hỗ trợ trích xuất Email!")

# Patch AntigravityUsageWidget.qml
if widget_file.exists():
    w_content = widget_file.read_text(encoding="utf-8")
    changed = False
    if "popoutHeight: 520" in w_content:
        w_content = w_content.replace("popoutHeight: 520", "popoutHeight: 580")
        changed = True
    if "User Account Info Card" not in w_content:
        target = "// One card per model group, each with its limit bars."
        card_qml = """// User Account Info Card
                StyledRect {
                    width: parent.width
                    height: accountRow.implicitHeight + Theme.spacingM * 2
                    color: Theme.surfaceContainerHigh
                    visible: root.loggedIn && root.account !== ""

                    Row {
                        id: accountRow
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingM

                        DankIcon {
                            name: "account_circle"
                            size: 26
                            color: root.brandColor
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            width: parent.width - 38

                            StyledText {
                                text: root.account
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.Medium
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                                width: parent.width
                            }

                            StyledText {
                                text: root.plan || "Google Antigravity"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                visible: root.plan !== ""
                            }
                        }
                    }
                }

                // One card per model group, each with its limit bars."""
        if target in w_content:
            w_content = w_content.replace(target, card_qml, 1)
            changed = True
    if changed:
        widget_file.write_text(w_content, encoding="utf-8")
        print("Đã patch AntigravityUsageWidget.qml hiển thị thẻ Email tài khoản!")
EOF

# 4. Kích hoạt và gán widget lên thanh Bar (DankBar) trong settings.json
DMS_SETTINGS="${HOME}/.config/DankMaterialShell/settings.json"
if [[ -f "$DMS_SETTINGS" ]]; then
    log_info "Cập nhật vị trí widget antigravityUsage trên thanh taskbar..."
    tmp=$(mktemp)
    jq '
        if (.barConfigs[0].rightWidgets | index("antigravityUsage")) == null then
            .barConfigs[0].rightWidgets |= (
                if index("memUsage") != null then
                    (.[0:(index("memUsage") + 1)]) + ["antigravityUsage"] + (.[(index("memUsage") + 1):])
                else
                    . + ["antigravityUsage"]
                end
            )
        else
            .
        end
    ' "$DMS_SETTINGS" > "$tmp" && mv "$tmp" "$DMS_SETTINGS"
fi

# 5. Khởi động lại DMS để nạp widget mới
if pgrep -x "dms" >/dev/null 2>&1; then
    log_info "Restarting DankMaterialShell để áp dụng widget..."
    dms ipc call plugins reload antigravityUsage >/dev/null 2>&1 || true
    dms restart >/dev/null 2>&1 || true
fi

log_success "Hoàn tất thiết lập plugin Antigravity Usage:"
echo -e "  - Vị trí: Đã hiển thị trên thanh Bar (cạnh RAM usage)"
echo -e "  - Biểu tượng: Icon tên lửa kèm vòng tròn % hạn mức sử dụng (Gemini & Claude/GPT)"
echo -e "  - Hiển thị Email: Đã tích hợp thẻ hiển thị Email tài khoản và gói thuê bao trong Popup"
