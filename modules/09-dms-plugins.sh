#!/usr/bin/env bash
# Description: Cài đặt và cấu hình plugin DankMaterialShell (Antigravity Usage theo dõi quota, email, tự động làm mới khi đổi tài khoản)
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

# 3. Patch get-agy-usage và AntigravityUsageWidget.qml để hỗ trợ hiển thị Email, tự động dọn cache & cập nhật quota khi chuyển đổi / đăng xuất tài khoản
python3 - <<'EOF'
from pathlib import Path
import re

plugin_dir = Path.home() / ".config" / "DankMaterialShell" / "plugins" / "antigravityUsage"
script_file = plugin_dir / "get-agy-usage"
widget_file = plugin_dir / "AntigravityUsageWidget.qml"

# 1. Patch get-agy-usage
if script_file.exists():
    content = script_file.read_text(encoding="utf-8")
    changed = False

    # A. Xóa sạch cache khi người dùng đã logout (keyring rỗng)
    if '[ -z "$KEYRING_JSON" ] && emit_logged_out' in content:
        content = content.replace(
            '[ -z "$KEYRING_JSON" ] && emit_logged_out',
            'if [ -z "$KEYRING_JSON" ]; then\n'
            '    # Keyring empty -> user is logged out. Invalidate any lingering caches.\n'
            '    rm -f "$TOKEN_CACHE" "$PROJECT_CACHE" "$PLAN_CACHE" "$QUOTA_CACHE" "$CACHE_DIR/account.txt"\n'
            '    emit_logged_out\n'
            'fi',
            1
        )
        changed = True

    # B. Trích xuất email từ id_token trong keyring blob
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
            changed = True

    # C. Theo dõi thay đổi tài khoản và tự động hủy bỏ cache cũ khi phát hiện login tài khoản khác
    if "ACCOUNT_FILE=" not in content:
        target_after = 'EXPIRY_EPOCH=$(expiry_to_epoch "$EXPIRY_RAW")\n'
        account_track = (
            '\n# Invalidate cache if user logged into a different account\n'
            'ACCOUNT_FILE="$CACHE_DIR/account.txt"\n'
            'LAST_ACCOUNT=""\n'
            '[ -f "$ACCOUNT_FILE" ] && LAST_ACCOUNT=$(cat "$ACCOUNT_FILE" 2>/dev/null || true)\n'
            'CURRENT_ACCOUNT_ID="${ACCOUNT:-$(printf \'%s\' "$REFRESH_TOKEN" | md5sum | cut -d\' \' -f1)}"\n\n'
            'if [ -n "$LAST_ACCOUNT" ] && [ "$LAST_ACCOUNT" != "$CURRENT_ACCOUNT_ID" ]; then\n'
            '    # Account changed: clear all cached tokens, project IDs, plans, and quota\n'
            '    rm -f "$TOKEN_CACHE" "$PROJECT_CACHE" "$PLAN_CACHE" "$QUOTA_CACHE"\n'
            'fi\n'
            'printf \'%s\' "$CURRENT_ACCOUNT_ID" > "$ACCOUNT_FILE"\n'
        )
        if target_after in content:
            content = content.replace(target_after, target_after + account_track, 1)
            changed = True

    # D. Gắn account vào token.json và kiểm tra đúng tài khoản khi dùng token cache
    if 'account:$a' not in content:
        old_token_save = 'jq -n --arg t "$at" --argjson e "$EXPIRY_EPOCH" \'{access_token:$t, expiry:$e}\' > "$TOKEN_CACHE" 2>/dev/null || true'
        new_token_save = 'jq -n --arg t "$at" --argjson e "$EXPIRY_EPOCH" --arg a "$CURRENT_ACCOUNT_ID" \'{access_token:$t, expiry:$e, account:$a}\' > "$TOKEN_CACHE" 2>/dev/null || true'
        if old_token_save in content:
            content = content.replace(old_token_save, new_token_save, 1)
            changed = True

    if 'c_acc=' not in content:
        old_token_check = (
            '    if [ -f "$TOKEN_CACHE" ]; then\n'
            '        c_at=$(jq -r \'.access_token // empty\' "$TOKEN_CACHE" 2>/dev/null || true)\n'
            '        c_ex=$(jq -r \'.expiry // 0\' "$TOKEN_CACHE" 2>/dev/null || echo 0)\n'
            '        if [ -n "$c_at" ] && token_valid "$c_ex"; then\n'
            '            ACCESS_TOKEN="$c_at"; EXPIRY_EPOCH="$c_ex"\n'
            '        fi\n'
            '    fi'
        )
        new_token_check = (
            '    # keyring token stale -> try our own refreshed-token cache first if it belongs to this account\n'
            '    if [ -f "$TOKEN_CACHE" ]; then\n'
            '        c_acc=$(jq -r \'.account // empty\' "$TOKEN_CACHE" 2>/dev/null || true)\n'
            '        if [ -z "$c_acc" ] || [ "$c_acc" = "$CURRENT_ACCOUNT_ID" ]; then\n'
            '            c_at=$(jq -r \'.access_token // empty\' "$TOKEN_CACHE" 2>/dev/null || true)\n'
            '            c_ex=$(jq -r \'.expiry // 0\' "$TOKEN_CACHE" 2>/dev/null || echo 0)\n'
            '            if [ -n "$c_at" ] && token_valid "$c_ex"; then\n'
            '                ACCESS_TOKEN="$c_at"; EXPIRY_EPOCH="$c_ex"\n'
            '            fi\n'
            '        fi\n'
            '    fi'
        )
        if old_token_check in content:
            content = content.replace(old_token_check, new_token_check, 1)
            changed = True

    # E. Tự động lấy lại project ID và quota khi project cũ không khớp tài khoản mới
    if "fetch_project_and_plan" not in content:
        old_sec2_3_pattern = re.compile(
            r'# --- 2\. Resolve the cloudaicompanion project.*?(\[ -z "\$PLAN" \] && \[ -f "\$PLAN_CACHE" \] && PLAN=\$\(cat "\$PLAN_CACHE" 2>/dev/null \|\| true\))',
            re.DOTALL
        )
        new_sec2_3 = """# --- 2. Resolve the cloudaicompanion project (needed by the quota call) -----
PROJECT=""
[ -f "$PROJECT_CACHE" ] && PROJECT=$(cat "$PROJECT_CACHE" 2>/dev/null || true)
PLAN=""
LCA=""

fetch_project_and_plan() {
    LCA=$(auth_curl -X POST "$API_BASE:loadCodeAssist" \\
        --data '{"metadata":{"ideType":"ANTIGRAVITY"}}' 2>/dev/null || true)
    PROJECT=$(printf '%s' "$LCA" | jq -r '.cloudaicompanionProject // empty' 2>/dev/null || true)
    [ -n "$PROJECT" ] && printf '%s' "$PROJECT" > "$PROJECT_CACHE"
    PLAN=$(printf '%s' "$LCA" | jq -r '(.paidTier.name // .currentTier.name) // empty' 2>/dev/null || true)
    [ -n "$PLAN" ] && printf '%s' "$PLAN" > "$PLAN_CACHE"
}

if [ -z "$PROJECT" ]; then
    fetch_project_and_plan
fi

# --- 3. Fetch the quota summary (with short-lived cache) --------------------
QUOTA=""
if [ -f "$QUOTA_CACHE" ]; then
    cached_acc=$(jq -r '.account // empty' "$QUOTA_CACHE" 2>/dev/null || true)
    if [ -n "$cached_acc" ] && [ "$cached_acc" != "$CURRENT_ACCOUNT_ID" ]; then
        rm -f "$QUOTA_CACHE"
    else
        cached_at=$(jq -r '.cached_at // 0' "$QUOTA_CACHE" 2>/dev/null || echo 0)
        if [ "$(( $(now) - cached_at ))" -lt "$QUOTA_TTL" ]; then
            QUOTA=$(jq -c '.data // empty' "$QUOTA_CACHE" 2>/dev/null || true)
        fi
    fi
fi

query_quota() {
    [ -z "$PROJECT" ] && return 1
    local resp
    resp=$(auth_curl -X POST "$API_BASE:retrieveUserQuotaSummary" \\
        --data "$(jq -n --arg p "$PROJECT" '{project:$p}')" 2>/dev/null || true)
    if printf '%s' "$resp" | jq -e '.groups' >/dev/null 2>&1; then
        QUOTA=$(printf '%s' "$resp" | jq -c '.')
        jq -n --argjson d "$QUOTA" --argjson t "$(now)" --arg a "$CURRENT_ACCOUNT_ID" '{cached_at:$t, account:$a, data:$d}' > "$QUOTA_CACHE" 2>/dev/null || true
        return 0
    fi
    return 1
}

if [ -z "$QUOTA" ]; then
    if ! query_quota; then
        # Quota fetch failed — cached project might be invalid for this account; refresh and retry once
        rm -f "$PROJECT_CACHE"
        fetch_project_and_plan
        query_quota || true
    fi
    # If still empty, only fall back to cache if it belongs to the CURRENT account
    if [ -z "$QUOTA" ] && [ -f "$QUOTA_CACHE" ]; then
        cached_acc=$(jq -r '.account // empty' "$QUOTA_CACHE" 2>/dev/null || true)
        if [ -z "$cached_acc" ] || [ "$cached_acc" = "$CURRENT_ACCOUNT_ID" ]; then
            QUOTA=$(jq -c '.data // empty' "$QUOTA_CACHE" 2>/dev/null || true)
        fi
    fi
fi
[ -z "$QUOTA" ] && emit_logged_out

if [ -z "$PLAN" ] && [ -f "$PLAN_CACHE" ]; then
    PLAN=$(cat "$PLAN_CACHE" 2>/dev/null || true)
fi"""
        if old_sec2_3_pattern.search(content):
            content = old_sec2_3_pattern.sub(new_sec2_3, content, count=1)
            changed = True
    if "FORCE_REFRESH=" not in content:
        content = content.replace(
            'QUOTA_TTL=120                             # seconds\nGOOGLE_ACCOUNTS="$HOME/.gemini/google_accounts.json"',
            'QUOTA_TTL=60                              # seconds\nGOOGLE_ACCOUNTS="$HOME/.gemini/google_accounts.json"\n\nFORCE_REFRESH=false\nfor arg in "$@"; do\n    case "$arg" in\n        --force|-f) FORCE_REFRESH=true ;;\n    esac\ndone',
            1
        )
        content = content.replace(
            'if [ -f "$QUOTA_CACHE" ]; then',
            'if [ "$FORCE_REFRESH" != "true" ] && [ -f "$QUOTA_CACHE" ]; then',
            1
        )
        changed = True

    if changed:
        script_file.write_text(content, encoding="utf-8")
        print("Đã patch get-agy-usage (hỗ trợ email, kiểm tra & dọn cache khi chuyển đổi/đăng xuất tài khoản, hỗ trợ --force refresh)!")

# 2. Patch AntigravityUsageWidget.qml
if widget_file.exists():
    w_content = widget_file.read_text(encoding="utf-8")
    w_changed = False

    if "popoutHeight: 520" in w_content:
        w_content = w_content.replace("popoutHeight: 520", "popoutHeight: 580")
        w_changed = True

    # Hàm refreshUsage và click chuột phải vào taskbar pill để refresh ngay
    if "function refreshUsage(force)" not in w_content:
        target_fetch = '    property string logoSource: "file://" + PluginService.pluginDirectory + "/antigravityUsage/icon.svg"\n'
        refresh_fn = """
    function refreshUsage(force) {
        if (usageProcess.running)
            return;
        root.isLoading = true;
        if (force === true) {
            usageProcess.command = ["bash", root.scriptPath, "--force"];
        } else {
            usageProcess.command = ["bash", root.scriptPath];
        }
        usageProcess.running = true;
    }

    // Right-click pill on taskbar to force refresh immediately
    pillRightClickAction: function() {
        root.refreshUsage(true);
    }
"""
        if target_fetch in w_content:
            w_content = w_content.replace(target_fetch, target_fetch + refresh_fn, 1)
            w_content = re.sub(
                r'Timer\s*\{\s*interval:\s*root\.refreshInterval\s*running:\s*true\s*repeat:\s*true\s*triggeredOnStart:\s*true\s*onTriggered:\s*\{\s*if\s*\(!usageProcess\.running\)\s*usageProcess\.running\s*=\s*true;\s*\}',
                'Timer {\n        interval: root.refreshInterval\n        running: true\n        repeat: true\n        triggeredOnStart: true\n        onTriggered: {\n            root.refreshUsage(false);\n        }',
                w_content
            )
            w_changed = True

    # Thẻ User Account Info
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
            w_changed = True

    # Dọn dẹp buckets và order khi logout hoặc đổi account
    if 'case "LOGGED_IN":' in w_content and 'if (!loggedIn) {' not in w_content:
        old_switch = """        switch (key) {
        case "LOGGED_IN":
            loggedIn = (val === "true");
            break;
        case "ACCOUNT":
            account = val;
            break;"""
        new_switch = """        switch (key) {
        case "LOGGED_IN":
            loggedIn = (val === "true");
            if (!loggedIn) {
                account = "";
                plan = "";
                buckets = ({});
                bucketOrder = [];
            }
            break;
        case "ACCOUNT":
            if (account !== "" && account !== val) {
                buckets = ({});
                bucketOrder = [];
            }
            account = val;
            break;"""
        if old_switch in w_content:
            w_content = w_content.replace(old_switch, new_switch, 1)
            w_changed = True

    # Tự động làm mới dữ liệu khi mở Popup và thêm nút Refresh trên header
    if "popoutContent: Component {" in w_content and "popoutComp" not in w_content:
        old_popout = """    popoutContent: Component {
        PopoutComponent {
            headerText: root.tr("Antigravity Usage")"""
        new_popout = """    popoutContent: Component {
        PopoutComponent {
            id: popoutComp
            headerText: root.tr("Antigravity Usage")"""
        if old_popout in w_content:
            w_content = w_content.replace(old_popout, new_popout, 1)
            target_close = 'showCloseButton: true\n'
            header_refresh = """
            Connections {
                target: popoutComp.parentPopout
                ignoreUnknownSignals: true
                function onShouldBeVisibleChanged() {
                    if (popoutComp.parentPopout && popoutComp.parentPopout.shouldBeVisible) {
                        root.refreshUsage(true);
                    }
                }
            }

            headerActions: Component {
                Rectangle {
                    width: 32
                    height: 32
                    radius: 16
                    color: refreshArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                    DankIcon {
                        id: refreshIcon
                        anchors.centerIn: parent
                        name: "refresh"
                        size: 20
                        weight: 600
                        smoothTransform: true
                        color: root.isLoading ? Theme.primary : (refreshArea.containsMouse ? Theme.primary : Theme.surfaceText)

                        RotationAnimator on rotation {
                            id: rotAnim
                            running: root.isLoading
                            loops: Animation.Infinite
                            from: 0
                            to: 360
                            duration: 900
                            onRunningChanged: {
                                if (!running)
                                    refreshIcon.rotation = 0;
                            }
                        }
                    }

                    MouseArea {
                        id: refreshArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.refreshUsage(true)
                    }
                }
            }
"""
            if target_close in w_content:
                w_content = w_content.replace(target_close, target_close + header_refresh, 1)
            w_changed = True

    if w_changed:
        widget_file.write_text(w_content, encoding="utf-8")
        print("Đã patch AntigravityUsageWidget.qml (thẻ Email, nút Refresh xoay, dọn state và tự động làm mới khi mở Popup)!")
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
echo -e "  - Đổi tài khoản: Tự động xóa cache và cập nhật % quota tức thì khi đăng xuất / đăng nhập tài khoản khác"
