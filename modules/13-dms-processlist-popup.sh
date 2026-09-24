#!/usr/bin/env bash
# Description: Tùy biến popup Processes của DankMaterialShell (thêm biểu đồ Disk dung lượng ổ đĩa & nút X đóng popup)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

log_info "Bắt đầu thiết lập tùy biến popup Processes cho DankMaterialShell..."

TARGET_FILE="${HOME}/.config/DankMaterialShell/shell/Modules/ProcessList/ProcessListPopout.qml"

if [[ ! -f "$TARGET_FILE" ]]; then
    log_error "Không tìm thấy file: $TARGET_FILE"
    log_info "Đảm bảo DankMaterialShell đã được cài đặt và cấu hình giao diện trước khi chạy module này."
    exit 1
fi

log_info "Kiểm tra và áp dụng bản vá cho ProcessListPopout.qml..."

python3 - <<'EOF'
import sys
import re
from pathlib import Path

target_file = Path.home() / ".config" / "DankMaterialShell" / "shell" / "Modules" / "ProcessList" / "ProcessListPopout.qml"
if not target_file.exists():
    print(f"Error: {target_file} not found", file=sys.stderr)
    sys.exit(1)

content = target_file.read_text(encoding="utf-8")
changed = False

# 1. Bổ sung DgopService diskmounts Ref
if '"diskmounts"' not in content:
    ref_block = """
    Ref {
        service: DgopService
        modules: ["diskmounts"]
        active: processListPopout.shouldBeVisible
    }
"""
    m = re.search(r"(\n\s*ProcessContextMenu\s*\{)", content)
    if m:
        content = content[:m.start()] + ref_block + content[m.start():]
        changed = True
        print("[+] Đã thêm DgopService modules [diskmounts]")

# 2. Bổ sung nút đóng [X] bên cạnh searchField trong Header
if "closePopoutButton" not in content:
    close_btn = """
                    DankActionButton {
                        id: closePopoutButton
                        Layout.alignment: Qt.AlignVCenter
                        iconName: "close"
                        iconSize: Theme.iconSize - 4
                        iconColor: Theme.surfaceText
                        tooltipText: I18n.tr("Close")
                        onClicked: processListPopout.hide()
                    }"""
    m = re.search(r"(id:\s*searchField[\s\S]*?keyForwardTargets:\s*\[processListContent\]\s*\n\s*\})", content)
    if m:
        content = content[:m.end()] + "\n" + close_btn + content[m.end():]
        changed = True
        print("[+] Đã thêm nút đóng [X] (closePopoutButton)")

# 3. Bổ sung thuộc tính tính toán Disk dung lượng ổ đĩa vào statsContainer
if "diskUsagePercent" not in content:
    gauge_size_str = "readonly property real gaugeSize: Theme.fontSizeMedium * 6.5"
    disk_props = """
                    readonly property var availableMounts: {
                        if (!DgopService.diskMounts || DgopService.diskMounts.length === 0)
                            return [];
                        return DgopService.diskMounts.filter(m => {
                            if (!m || !m.mount || !m.size)
                                return false;
                            if (m.mount.startsWith("/sys") || m.mount.startsWith("/dev") || m.mount.startsWith("/run") || m.mount.startsWith("/proc"))
                                return false;
                            if (m.fstype === "efivarfs")
                                return false;
                            return true;
                        });
                    }

                    property int diskMountIndex: 0

                    readonly property var selectedDiskMount: {
                        if (availableMounts.length === 0) {
                            if (!DgopService.diskMounts || DgopService.diskMounts.length === 0)
                                return null;
                            return DgopService.diskMounts.find(m => m.mount === "/") || DgopService.diskMounts[0];
                        }
                        const idx = Math.min(diskMountIndex, availableMounts.length - 1);
                        return availableMounts[idx] || availableMounts[0];
                    }

                    readonly property real diskUsagePercent: {
                        if (!selectedDiskMount?.percent)
                            return 0;
                        return parseFloat(selectedDiskMount.percent.replace("%", "")) || 0;
                    }"""
    if gauge_size_str in content:
        content = content.replace(gauge_size_str, gauge_size_str + "\n" + disk_props, 1)
        changed = True
        print("[+] Đã thêm thuộc tính Disk usage vào statsContainer")

# 4. Bổ sung biểu đồ tròn Disk (CircleGauge) vào gaugesRow cạnh Memory
if 'sublabel: I18n.tr("Disk")' not in content:
    disk_gauge = """
                        CircleGauge {
                            width: statsContainer.gaugeSize
                            height: statsContainer.gaugeSize
                            value: statsContainer.diskUsagePercent / 100
                            label: statsContainer.selectedDiskMount ? statsContainer.selectedDiskMount.used : "--"
                            sublabel: I18n.tr("Disk")
                            detail: statsContainer.selectedDiskMount ? ("/" + statsContainer.selectedDiskMount.size) : ""
                            accentColor: statsContainer.diskUsagePercent > 90 ? Theme.error : (statsContainer.diskUsagePercent > 75 ? Theme.warning : (Theme.tertiary || Theme.info || Theme.primary))

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: statsContainer.availableMounts.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (statsContainer.availableMounts.length > 1) {
                                        statsContainer.diskMountIndex = (statsContainer.diskMountIndex + 1) % statsContainer.availableMounts.length;
                                    }
                                }
                            }
                        }"""
    m = re.search(r"(CircleGauge\s*\{[^}]*sublabel:\s*I18n\.tr\(\"Memory\"\)[^}]*\})", content)
    if m:
        content = content[:m.end()] + "\n" + disk_gauge + content[m.end():]
        changed = True
        print("[+] Đã thêm CircleGauge Disk vào gaugesRow")

if changed:
    bak_file = target_file.with_suffix(".qml.bak")
    if not bak_file.exists():
        bak_file.write_text(target_file.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"[+] Đã tạo bản sao lưu tại {bak_file}")
    target_file.write_text(content, encoding="utf-8")
    print("[SUCCESS] Đã cập nhật thành công ProcessListPopout.qml")
else:
    print("[INFO] ProcessListPopout.qml đã có đầy đủ tùy biến Disk và nút đóng X, không cần sửa đổi.")
EOF

# Tải lại cấu hình DMS nếu đang chạy
if systemctl --user is-active --quiet dms 2>/dev/null || pgrep -x "dms" >/dev/null 2>&1; then
    log_info "Khởi động lại DankMaterialShell để áp dụng giao diện mới..."
    systemctl --user restart dms 2>/dev/null || dms restart >/dev/null 2>&1 || true
fi

log_success "Hoàn tất thiết lập tùy biến popup Processes:"
echo -e "  - Biểu đồ Disk: Hiển thị dung lượng ổ đĩa đã dùng / tổng dung lượng phân vùng root (/)"
echo -e "  - Click chuyển ổ đĩa: Bấm vào biểu đồ tròn Disk để chuyển đổi giữa các ổ đĩa mount nếu có"
echo -e "  - Nút đóng X: Nằm bên phải ô tìm kiếm giúp đóng popup tức thì"
