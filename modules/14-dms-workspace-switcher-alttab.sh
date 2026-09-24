#!/usr/bin/env bash
# Description: Cấu hình Alt+Tab chuyển Workspace dạng popup snapshot tĩnh, tự động focus khi nhả phím Alt
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

log_info "Bắt đầu thiết lập tính năng Alt+Tab chuyển Workspace popup snapshot tĩnh..."

HYPR_CONFIG_DIR="${HOME}/.config/hypr/config"
INPUTS_FILE="${HYPR_CONFIG_DIR}/inputs.lua"
BINDS_FILE="${HYPR_CONFIG_DIR}/binds.lua"
DMS_SHELL_DIR="${HOME}/.config/DankMaterialShell/shell"
OVERLAYS_DIR="${DMS_SHELL_DIR}/Modules/WorkspaceOverlays"
DMS_IPC_FILE="${DMS_SHELL_DIR}/DMSShellIPC.qml"
OVERVIEW_QML="${OVERLAYS_DIR}/HyprlandOverview.qml"
WIDGET_QML="${OVERLAYS_DIR}/OverviewWidget.qml"
WINDOW_QML="${OVERLAYS_DIR}/OverviewWindow.qml"

# Kiểm tra sự tồn tại của thư mục cấu hình
if [[ ! -d "$HYPR_CONFIG_DIR" ]]; then
    log_error "Không tìm thấy thư mục cấu hình Hyprland: $HYPR_CONFIG_DIR"
    exit 1
fi

if [[ ! -d "$OVERLAYS_DIR" ]]; then
    log_error "Không tìm thấy thư mục DankMaterialShell overlays: $OVERLAYS_DIR"
    log_info "Hãy đảm bảo DankMaterialShell đã được cài đặt trước khi thực thi module này."
    exit 1
fi

# ==============================================================================
# 1. Cấu hình không tự động dịch chuyển con trỏ chuột (inputs.lua)
# ==============================================================================
log_info "1/5. Cấu hình chống warp con trỏ chuột trong inputs.lua..."
python3 - <<'EOF'
import re
from pathlib import Path

inputs_path = Path.home() / ".config" / "hypr" / "config" / "inputs.lua"
if inputs_path.exists():
    content = inputs_path.read_text(encoding="utf-8")
    changed = False

    if "no_warps = true" not in content or "warp_on_change_workspace = 0" not in content:
        if "cursor = {" in content:
            if "no_warps" not in content:
                content = content.replace("cursor = {", "cursor = {\n        no_warps = true,", 1)
                changed = True
            if "warp_on_change_workspace" not in content:
                content = content.replace("cursor = {", "cursor = {\n        warp_on_change_workspace = 0,", 1)
                changed = True
        else:
            cursor_block = """    cursor = {
        no_warps = true,
        warp_on_change_workspace = 0,
    },
"""
            m = re.search(r"(hl\.config\(\{\s*\n)", content)
            if m:
                content = content[:m.end()] + cursor_block + content[m.end():]
                changed = True

    if changed:
        bak = inputs_path.with_suffix(".lua.bak")
        if not bak.exists():
            bak.write_text(inputs_path.read_text(encoding="utf-8"), encoding="utf-8")
        inputs_path.write_text(content, encoding="utf-8")
        print("[+] Đã cấu hình cursor.no_warps = true và cursor.warp_on_change_workspace = 0")
    else:
        print("[INFO] inputs.lua đã có cấu hình chống warp chuột.")
EOF

# ==============================================================================
# 2. Cấu hình phím tắt Alt+Tab và nhả phím Alt trong binds.lua
# ==============================================================================
log_info "2/5. Cấu hình phím tắt Alt+Tab và release bindings trong binds.lua..."
python3 - <<'EOF'
import re
from pathlib import Path

binds_path = Path.home() / ".config" / "hypr" / "config" / "binds.lua"
if binds_path.exists():
    content = binds_path.read_text(encoding="utf-8")
    changed = False

    # A. Đảm bảo dmsCall truyền đúng DMS_SHELL_DIR
    target_dms_call = 'local dmsCall = "env DMS_SHELL_DIR=" .. (os.getenv("DMS_SHELL_DIR") or (os.getenv("HOME") .. "/.config/DankMaterialShell/shell")) .. " dms ipc call "'
    if 'env DMS_SHELL_DIR=' not in content:
        content = re.sub(r'local\s+dmsCall\s*=\s*"dms ipc call "', target_dms_call, content)
        changed = True

    # B. Bổ sung các phím tắt Alt+Tab, Alt+Shift+Tab và bắt sự kiện nhả phím Alt
    if 'cycleOverview' not in content:
        binds_block = """hl.bind("ALT + Tab",           hl.dsp.exec_cmd(dmsCall .. "hypr cycleOverview"))
hl.bind("ALT + SHIFT + Tab",   hl.dsp.exec_cmd(dmsCall .. "hypr cycleOverviewPrev"))
hl.bind("ALT + Alt_L",         hl.dsp.exec_cmd(dmsCall .. "hypr confirmOverview"), { release = true, transparent = true, dont_inhibit = true })
hl.bind("ALT + Alt_R",         hl.dsp.exec_cmd(dmsCall .. "hypr confirmOverview"), { release = true, transparent = true, dont_inhibit = true })
hl.bind("Alt_L",               hl.dsp.exec_cmd(dmsCall .. "hypr confirmOverview"), { release = true, ignore_mods = true, dont_inhibit = true })
hl.bind("Alt_R",               hl.dsp.exec_cmd(dmsCall .. "hypr confirmOverview"), { release = true, ignore_mods = true, dont_inhibit = true })
"""
        # Chèn sau focus down hoặc trước mainMod + Tab
        m = re.search(r'(hl\.bind\(mainMod\s*\.\.\s*"\s*\+\s*Down".*?\n)', content)
        if m:
            content = content[:m.end()] + binds_block + content[m.end():]
            changed = True
        else:
            content += "\n" + binds_block
            changed = True

    # C. Đảm bảo SUPER + Tab chuyển sang window cycle thông thường
    content = re.sub(
        r'hl\.bind\(mainMod\s*\.\.\s*"\s*\+\s*Tab",\s*hl\.dsp\.exec_cmd\(dmsCall\s*\.\.\s*"hypr toggleOverview"\)\)',
        'hl.bind(mainMod .. " + Tab",   hl.dsp.window.cycle_next())',
        content
    )

    if changed:
        bak = binds_path.with_suffix(".lua.bak")
        if not bak.exists():
            bak.write_text(binds_path.read_text(encoding="utf-8"), encoding="utf-8")
        binds_path.write_text(content, encoding="utf-8")
        print("[+] Đã cập nhật phím tắt Alt+Tab và nhả phím Alt trong binds.lua")
    else:
        print("[INFO] binds.lua đã có đầy đủ cấu hình Alt+Tab overview.")
EOF

# ==============================================================================
# 3. Patch IPC Handlers trong DMSShellIPC.qml (hypr cycleOverview & confirmOverview)
# ==============================================================================
log_info "3/5. Cập nhật IPC endpoints trong DMSShellIPC.qml..."
python3 - <<'EOF'
import re
from pathlib import Path

ipc_file = Path.home() / ".config" / "DankMaterialShell" / "shell" / "DMSShellIPC.qml"
if ipc_file.exists():
    content = ipc_file.read_text(encoding="utf-8")
    changed = False

    if "cycleOverview()" not in content:
        cycle_functions = """
        function cycleOverview(): string {
            if (!CompositorService.isHyprland || !root.hyprlandOverviewLoader.item) {
                return "HYPR_NOT_AVAILABLE";
            }
            if (typeof root.hyprlandOverviewLoader.item.cycleNext === "function") {
                root.hyprlandOverviewLoader.item.cycleNext();
            } else {
                root.hyprlandOverviewLoader.item.overviewOpen = true;
            }
            return "OVERVIEW_CYCLE_SUCCESS";
        }

        function cycleOverviewPrev(): string {
            if (!CompositorService.isHyprland || !root.hyprlandOverviewLoader.item) {
                return "HYPR_NOT_AVAILABLE";
            }
            if (typeof root.hyprlandOverviewLoader.item.cyclePrev === "function") {
                root.hyprlandOverviewLoader.item.cyclePrev();
            } else {
                root.hyprlandOverviewLoader.item.overviewOpen = true;
            }
            return "OVERVIEW_CYCLE_SUCCESS";
        }

        function confirmOverview(): string {
            if (!CompositorService.isHyprland || !root.hyprlandOverviewLoader.item) {
                return "HYPR_NOT_AVAILABLE";
            }
            if (typeof root.hyprlandOverviewLoader.item.confirmSelection === "function") {
                root.hyprlandOverviewLoader.item.confirmSelection();
            } else {
                root.hyprlandOverviewLoader.item.overviewOpen = false;
            }
            return "OVERVIEW_CONFIRM_SUCCESS";
        }
"""
        m = re.search(r'(\n\s*target:\s*"hypr"\s*\n\s*\})', content)
        if m:
            content = content[:m.start()] + cycle_functions + content[m.start():]
            changed = True

    if changed:
        bak = ipc_file.with_suffix(".qml.bak")
        if not bak.exists():
            bak.write_text(ipc_file.read_text(encoding="utf-8"), encoding="utf-8")
        ipc_file.write_text(content, encoding="utf-8")
        print("[+] Đã bổ sung cycleOverview, cycleOverviewPrev và confirmOverview vào DMSShellIPC.qml")
    else:
        print("[INFO] DMSShellIPC.qml đã có sẵn IPC endpoints cho Overview cycle.")
EOF

# ==============================================================================
# 4. Patch OverviewWindow.qml (hiển thị snapshot sắc nét 100%, thu nhỏ icon)
# ==============================================================================
log_info "4/5. Cập nhật OverviewWindow.qml..."
python3 - <<'EOF'
import re
from pathlib import Path

window_file = Path.home() / ".config" / "DankMaterialShell" / "shell" / "Modules" / "WorkspaceOverlays" / "OverviewWindow.qml"
if window_file.exists():
    content = window_file.read_text(encoding="utf-8")
    changed = False

    if "iconToWindowRatio: 0.12" not in content:
        content = re.sub(r"property\s+var\s+iconToWindowRatio:\s*0\.25", "property var iconToWindowRatio: 0.12", content)
        content = re.sub(r"property\s+var\s+iconToWindowRatioCompact:\s*0\.45", "property var iconToWindowRatioCompact: 0.20", content)
        changed = True

    if "opacity: 1\n" not in content and "opacity: 1\r\n" not in content:
        content = re.sub(r"opacity:\s*\(monitorObj\?\.id\s*\?\?\s*-1\)\s*==\s*widgetMonitorId\s*\?\s*1\s*:\s*0\.4", "opacity: 1", content)
        changed = True

    if "root.hovered ? 0.95 : 0.45" not in content:
        m = re.search(r"(sourceSize:\s*Qt\.size\(iconSize,\s*iconSize\)\s*\n)", content)
        if m:
            content = content[:m.end()] + "                    opacity: root.hovered ? 0.95 : 0.45\n                    Behavior on opacity { NumberAnimation { duration: 150 } }\n" + content[m.end():]
            changed = True

    if changed:
        bak = window_file.with_suffix(".qml.bak")
        if not bak.exists():
            bak.write_text(window_file.read_text(encoding="utf-8"), encoding="utf-8")
        window_file.write_text(content, encoding="utf-8")
        print("[+] Đã tối ưu OverviewWindow.qml (snapshot screencopy rõ nét, icon ứng dụng nhỏ gọn tinh tế)")
    else:
        print("[INFO] OverviewWindow.qml đã được cấu hình tối ưu trước đó.")
EOF

# ==============================================================================
# 5. Cấu hình OverviewWidget.qml & HyprlandOverview.qml
# ==============================================================================
log_info "5/5. Cấu hình giao diện popup tĩnh và bộ chọn Workspace..."

# Sao lưu các file gốc nếu chưa có bản sao lưu
for qml_path in "$WIDGET_QML" "$OVERVIEW_QML"; do
    if [[ -f "$qml_path" && ! -f "${qml_path}.bak" ]]; then
        cp "$qml_path" "${qml_path}.bak"
    fi
done

# Ghi đè OverviewWidget.qml với giao diện 3 cột, highlight viền 3px, badge tên Workspace
cat <<'EOF' > "$WIDGET_QML"
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Common
import qs.Services
import qs.Widgets

Item {
    id: root
    readonly property var log: Log.scoped("OverviewWidget")
    required property var panelWindow
    required property bool overviewOpen
    property int selectedWorkspaceId: -1
    signal workspaceSelected(int wsId)
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
    readonly property real dpr: CompositorService.getScreenScale(panelWindow.screen)
    readonly property int workspacesShown: SettingsData.overviewRows * SettingsData.overviewColumns

    readonly property var allWorkspaces: Hyprland.workspaces?.values || []
    readonly property var allWorkspaceIds: {
        const workspaces = allWorkspaces;
        if (!workspaces || workspaces.length === 0)
            return [];
        try {
            const ids = workspaces.map(ws => ws?.id).filter(id => id !== null && id !== undefined);
            return ids.sort((a, b) => a - b);
        } catch (e) {
            return [];
        }
    }

    readonly property var thisMonitorWorkspaceIds: {
        const workspaces = allWorkspaces;
        const mon = monitor;
        if (!workspaces || workspaces.length === 0 || !mon)
            return [];
        try {
            const ids = workspaces.filter(ws => ws?.monitor?.name === mon.name).map(ws => ws?.id).filter(id => id !== null && id !== undefined);
            return ids.sort((a, b) => a - b);
        } catch (e) {
            return [];
        }
    }

    readonly property var displayedWorkspaceIds: {
        if (!allWorkspaceIds || allWorkspaceIds.length === 0) {
            return [1, 2, 3];
        }

        try {
            const maxExisting = Math.max(...allWorkspaceIds);
            const result = [];
            for (let i = 1; i <= maxExisting; i++) {
                result.push(i);
            }
            return result;
        } catch (e) {
            return [1, 2, 3];
        }
    }

    readonly property int minWorkspaceId: displayedWorkspaceIds.length > 0 ? displayedWorkspaceIds[0] : 1
    readonly property int maxWorkspaceId: displayedWorkspaceIds.length > 0 ? displayedWorkspaceIds[displayedWorkspaceIds.length - 1] : workspacesShown
    readonly property int displayWorkspaceCount: displayedWorkspaceIds.length

    readonly property int effectiveColumns: 3

    function getWorkspaceMonitorName(workspaceId) {
        if (!allWorkspaces || !workspaceId)
            return "";
        try {
            const ws = allWorkspaces.find(w => w?.id === workspaceId);
            return ws?.monitor?.name ?? "";
        } catch (e) {
            return "";
        }
    }

    function workspaceHasWindows(workspaceId) {
        if (!workspaceId)
            return false;
        try {
            const workspace = allWorkspaces.find(ws => ws?.id === workspaceId);
            if (!workspace)
                return false;
            const toplevels = workspace?.toplevels?.values || [];
            return toplevels.length > 0;
        } catch (e) {
            return false;
        }
    }

    function monitorIpcForWorkspace(workspaceId) {
        const workspace = allWorkspaces?.find(ws => ws?.id === workspaceId);
        return workspace?.monitor?.lastIpcObject ?? monitor?.lastIpcObject ?? null;
    }

    function monitorLogicalSize(ipc) {
        if (!ipc || !ipc.width || !ipc.height)
            return {
                "width": monitorPhysicalWidth,
                "height": monitorPhysicalHeight
            };

        const monScale = ipc.scale > 0 ? ipc.scale : 1;
        const rotated = ((ipc.transform ?? 0) % 2) === 1;
        return {
            "width": (rotated ? ipc.height : ipc.width) / monScale,
            "height": (rotated ? ipc.width : ipc.height) / monScale
        };
    }

    function cellForWorkspace(workspaceId) {
        const cell = gridLayout.cells.find(c => c.id === workspaceId);
        if (cell)
            return cell;
        return {
            "id": workspaceId,
            "x": 0,
            "y": 0,
            "width": workspaceImplicitWidth,
            "height": workspaceImplicitHeight
        };
    }

    function getWorkspaceViewportBounds(workspaceId, cellWidth, cellHeight) {
        const ipc = monitorIpcForWorkspace(workspaceId) ?? {};
        const logical = monitorLogicalSize(ipc);
        const reserved = ipc.reserved || [0, 0, 0, 0];

        const x = (ipc.x ?? 0) + (reserved[0] ?? 0);
        const y = (ipc.y ?? 0) + (reserved[1] ?? 0);
        const width = Math.max(logical.width - (reserved[0] ?? 0) - (reserved[2] ?? 0), 1);
        const height = Math.max(logical.height - (reserved[1] ?? 0) - (reserved[3] ?? 0), 1);

        return {
            "x": x,
            "y": y,
            "scale": Math.min(cellWidth / width, cellHeight / height)
        };
    }

    property bool monitorIsFocused: monitor?.focused ?? false
    property real scale: 0.23
    property color activeBorderColor: Theme.primary

    readonly property real monitorPhysicalWidth: panelWindow.screen ? (panelWindow.screen.width / root.dpr) : (monitor?.width ?? 1920)
    readonly property real monitorPhysicalHeight: panelWindow.screen ? (panelWindow.screen.height / root.dpr) : (monitor?.height ?? 1080)
    property real workspaceImplicitWidth: monitorPhysicalWidth * root.scale
    property real workspaceImplicitHeight: monitorPhysicalHeight * root.scale

    property int workspaceZ: 0
    property int windowZ: 1
    property int monitorLabelZ: 2
    property int windowDraggingZ: 99999
    property real workspaceSpacing: 5

    property int draggingFromWorkspace: -1
    property int draggingTargetWorkspace: -1

    readonly property var gridLayout: {
        const ids = displayedWorkspaceIds;
        const columns = effectiveColumns;
        if (!ids || ids.length === 0 || columns < 1)
            return {
                "cells": [],
                "width": 0,
                "height": 0
            };

        const rows = [];
        for (let i = 0; i < ids.length; i += columns) {
            rows.push(ids.slice(i, i + columns).map(id => {
                const logical = monitorLogicalSize(monitorIpcForWorkspace(id));
                return {
                    "id": id,
                    "width": logical.width * scale,
                    "height": logical.height * scale
                };
            }));
        }

        const rowWidth = row => row.reduce((acc, cell) => acc + cell.width, 0) + workspaceSpacing * (row.length - 1);
        const totalWidth = rows.reduce((acc, row) => Math.max(acc, rowWidth(row)), 0);

        const cells = [];
        let cursorY = 0;
        for (const row of rows) {
            const rowHeight = row.reduce((acc, cell) => Math.max(acc, cell.height), 0);
            let cursorX = (totalWidth - rowWidth(row)) / 2;
            for (const cell of row) {
                cells.push({
                    "id": cell.id,
                    "x": cursorX,
                    "y": cursorY + (rowHeight - cell.height) / 2,
                    "width": cell.width,
                    "height": cell.height
                });
                cursorX += cell.width + workspaceSpacing;
            }
            cursorY += rowHeight + workspaceSpacing;
        }

        return {
            "cells": cells,
            "width": totalWidth,
            "height": cursorY - workspaceSpacing
        };
    }

    implicitWidth: overviewBackground.implicitWidth + Theme.spacingL * 2
    implicitHeight: overviewBackground.implicitHeight + Theme.spacingL * 2

    Component.onCompleted: {
        Hyprland.refreshToplevels();
        Hyprland.refreshWorkspaces();
        Hyprland.refreshMonitors();
    }

    onOverviewOpenChanged: {
        if (overviewOpen) {
            Hyprland.refreshToplevels();
            Hyprland.refreshWorkspaces();
            Hyprland.refreshMonitors();
        }
    }

    Rectangle {
        id: overviewBackground
        property real padding: 10
        anchors.fill: parent
        anchors.margins: Theme.spacingL

        implicitWidth: workspaceGrid.implicitWidth + padding * 2
        implicitHeight: workspaceGrid.implicitHeight + padding * 2
        radius: Theme.cornerRadius
        color: Theme.surfaceContainer
        border.width: 1
        border.color: Theme.withAlpha(Theme.outline, 0.25)

        ElevationShadow {
            anchors.fill: parent
            z: -1
            level: Theme.elevationLevel2
            fallbackOffset: 4
            targetRadius: Theme.cornerRadius
            targetColor: Theme.surfaceContainer
            shadowOpacity: Theme.elevationLevel2 && Theme.elevationLevel2.alpha !== undefined ? Theme.elevationLevel2.alpha : 0.25
            shadowEnabled: Theme.elevationEnabled
        }

        Item {
            id: workspaceGrid

            z: root.workspaceZ
            anchors.centerIn: parent
            implicitWidth: root.gridLayout.width
            implicitHeight: root.gridLayout.height

            Repeater {
                model: root.gridLayout.cells.length

                Rectangle {
                    id: workspace
                    required property int index
                    readonly property var cell: root.gridLayout.cells[index] ?? null
                    property int workspaceValue: cell?.id ?? -1
                    property bool workspaceExists: (root.allWorkspaceIds && workspaceValue > 0) ? root.allWorkspaceIds.includes(workspaceValue) : false
                    property var workspaceObj: (workspaceExists && Hyprland.workspaces?.values) ? Hyprland.workspaces.values.find(ws => ws?.id === workspaceValue) : null
                    property bool isActive: workspaceObj?.active ?? false
                    property bool isOnThisMonitor: (workspaceObj && root.monitor) ? (workspaceObj.monitor?.name === root.monitor.name) : true
                    property bool hasWindows: (workspaceValue > 0) ? root.workspaceHasWindows(workspaceValue) : false
                    property color defaultWorkspaceColor: workspaceExists ? Theme.surfaceContainer : Theme.withAlpha(Theme.surfaceContainer, 0.3)
                    property color hoveredWorkspaceColor: Qt.lighter(defaultWorkspaceColor, 1.1)
                    property color hoveredBorderColor: Theme.surfaceVariant
                    property bool hoveredWhileDragging: false
                    property bool isSelected: (root.selectedWorkspaceId !== -1)
                        ? (workspaceValue === root.selectedWorkspaceId)
                        : (isActive && isOnThisMonitor)
                    property bool shouldShowActiveIndicator: isSelected

                    visible: workspaceValue !== -1

                    x: cell?.x ?? 0
                    y: cell?.y ?? 0
                    width: cell?.width ?? 0
                    height: cell?.height ?? 0
                    color: hoveredWhileDragging ? hoveredWorkspaceColor : (isSelected ? Qt.lighter(defaultWorkspaceColor, 1.25) : defaultWorkspaceColor)
                    radius: Theme.cornerRadius
                    border.width: isSelected ? 3 : 1
                    border.color: isSelected ? root.activeBorderColor : (hoveredWhileDragging ? hoveredBorderColor : Theme.withAlpha(Theme.outline, 0.25))
                    scale: isSelected ? 1.02 : 1.0
                    Behavior on scale {
                        NumberAnimation { duration: 100 }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: workspace.workspaceValue
                        font.pixelSize: Theme.fontSizeXLarge * 6
                        font.weight: Font.DemiBold
                        color: Theme.withAlpha(Theme.surfaceText, workspace.workspaceExists ? 0.2 : 0.1)
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }

                    MouseArea {
                        id: workspaceArea
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton
                        onClicked: {
                            if (root.draggingTargetWorkspace === -1) {
                                root.workspaceSelected(workspace.workspaceValue);
                            }
                        }
                    }

                    DropArea {
                        anchors.fill: parent
                        onEntered: {
                            root.draggingTargetWorkspace = workspace.workspaceValue;
                            if (root.draggingFromWorkspace == root.draggingTargetWorkspace)
                                return;
                            workspace.hoveredWhileDragging = true;
                        }
                        onExited: {
                            workspace.hoveredWhileDragging = false;
                            if (root.draggingTargetWorkspace == workspace.workspaceValue)
                                root.draggingTargetWorkspace = -1;
                        }
                    }
                }
            }
        }

        Item {
            id: windowSpace
            anchors.centerIn: parent
            implicitWidth: workspaceGrid.implicitWidth
            implicitHeight: workspaceGrid.implicitHeight

            Repeater {
                model: ScriptModel {
                    values: {
                        const workspaces = root.allWorkspaces;
                        const minId = root.minWorkspaceId;
                        const maxId = root.maxWorkspaceId;

                        if (!workspaces || workspaces.length === 0)
                            return [];

                        try {
                            const result = [];
                            for (const workspace of workspaces) {
                                const wsId = workspace?.id ?? -1;
                                if (wsId >= minId && wsId <= maxId) {
                                    const toplevels = workspace?.toplevels?.values || [];
                                    for (const toplevel of toplevels) {
                                        result.push(toplevel);
                                    }
                                }
                            }
                            return result;
                        } catch (e) {
                            log.error("OverviewWidget filter error:", e);
                            return [];
                        }
                    }
                }
                delegate: OverviewWindow {
                    id: window
                    required property var modelData

                    overviewOpen: root.overviewOpen
                    readonly property int windowWorkspaceId: modelData?.workspace?.id ?? -1
                    readonly property var workspaceCell: root.cellForWorkspace(windowWorkspaceId)
                    readonly property var workspaceBounds: root.getWorkspaceViewportBounds(windowWorkspaceId, workspaceCell.width, workspaceCell.height)

                    toplevel: modelData
                    scale: root.scale
                    monitorDpr: root.dpr
                    availableWorkspaceWidth: workspaceCell.width
                    availableWorkspaceHeight: workspaceCell.height
                    contentOriginX: workspaceBounds.x
                    contentOriginY: workspaceBounds.y
                    contentScale: workspaceBounds.scale
                    widgetMonitorId: root.monitor.id

                    xOffset: workspaceCell.x
                    yOffset: workspaceCell.y

                    z: atInitPosition ? root.windowZ : root.windowDraggingZ
                    property bool atInitPosition: (initX == x && initY == y)

                    Drag.hotSpot.x: width / 2
                    Drag.hotSpot.y: height / 2

                    MouseArea {
                        id: dragArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: window.hovered = true
                        onExited: window.hovered = false
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        drag.target: parent

                        onPressed: mouse => {
                            root.draggingFromWorkspace = windowData?.workspace.id;
                            window.pressed = true;
                            window.Drag.active = true;
                            window.Drag.source = window;
                            window.Drag.hotSpot.x = mouse.x;
                            window.Drag.hotSpot.y = mouse.y;
                        }

                        onReleased: {
                            const targetWorkspace = root.draggingTargetWorkspace;
                            window.pressed = false;
                            window.Drag.active = false;
                            root.draggingFromWorkspace = -1;
                            root.draggingTargetWorkspace = -1;

                            if (targetWorkspace !== -1 && targetWorkspace !== windowData?.workspace.id) {
                                HyprlandService.moveToWorkspace(targetWorkspace, windowData?.address, false);
                                Qt.callLater(() => {
                                    Hyprland.refreshToplevels();
                                    Hyprland.refreshWorkspaces();
                                    Qt.callLater(() => {
                                        window.x = window.initX;
                                        window.y = window.initY;
                                    });
                                });
                            } else {
                                window.x = window.initX;
                                window.y = window.initY;
                            }
                        }

                        onClicked: event => {
                            if (!windowData || !windowData.address)
                                return;
                            if (event.button === Qt.LeftButton) {
                                root.workspaceSelected(windowData.workspace.id);
                                HyprlandService.focusWindow(windowData.address);
                                event.accepted = true;
                            } else if (event.button === Qt.MiddleButton) {
                                HyprlandService.closeWindow(windowData.address);
                                event.accepted = true;
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: monitorLabelSpace
            anchors.centerIn: parent
            implicitWidth: workspaceGrid.implicitWidth
            implicitHeight: workspaceGrid.implicitHeight
            z: root.monitorLabelZ

            Repeater {
                model: root.gridLayout.cells.length
                delegate: Item {
                    id: labelItem
                    required property int index
                    readonly property var cell: root.gridLayout.cells[index] ?? null
                    property int workspaceValue: cell?.id ?? -1
                    property bool workspaceExists: (root.allWorkspaceIds && workspaceValue > 0) ? root.allWorkspaceIds.includes(workspaceValue) : false
                    property string workspaceMonitorName: (workspaceValue > 0) ? root.getWorkspaceMonitorName(workspaceValue) : ""
                    property bool isSelected: (root.selectedWorkspaceId !== -1) && (root.selectedWorkspaceId === labelItem.workspaceValue)

                    x: cell?.x ?? 0
                    y: cell?.y ?? 0
                    width: cell?.width ?? 0
                    height: cell?.height ?? 0

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingS
                        width: wsNameText.contentWidth + Theme.spacingS * 2
                        height: wsNameText.contentHeight + Theme.spacingXS * 2
                        radius: Theme.cornerRadius
                        color: labelItem.isSelected ? Theme.primary : Theme.surface
                        visible: labelItem.workspaceExists

                        StyledText {
                            id: wsNameText
                            anchors.centerIn: parent
                            text: {
                                const ws = root.allWorkspaces ? root.allWorkspaces.find(w => w?.id === labelItem.workspaceValue) : null;
                                const n = ws?.name;
                                if (n && n !== String(labelItem.workspaceValue)) {
                                    return labelItem.workspaceValue + ": " + n;
                                }
                                return "WS " + labelItem.workspaceValue;
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.SemiBold
                            color: labelItem.isSelected ? Theme.onPrimary : Theme.primary
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Theme.spacingS
                        width: monitorNameText.contentWidth + Theme.spacingS * 2
                        height: monitorNameText.contentHeight + Theme.spacingXS * 2
                        radius: Theme.cornerRadius
                        color: Theme.surface
                        visible: labelItem.workspaceExists && labelItem.workspaceMonitorName !== ""

                        StyledText {
                            id: monitorNameText
                            anchors.centerIn: parent
                            text: labelItem.workspaceMonitorName
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.Medium
                            color: Theme.surfaceText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }
    }
}
EOF
log_success "Đã cập nhật OverviewWidget.qml thành công."

# Ghi đè HyprlandOverview.qml với popup tĩnh căn giữa, bắt release Alt, điều hướng không giật hình
cat <<'EOF' > "$OVERVIEW_QML"
import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Common
import qs.Services

Scope {
    id: overviewScope

    readonly property var log: Log.scoped("HyprlandOverview")
    property bool overviewOpen: false
    property int _selectedWorkspaceId: -1

    onOverviewOpenChanged: {
        log.info("overviewOpen changed to: " + overviewOpen);
        if (!overviewOpen) {
            _selectedWorkspaceId = -1;
        }
    }

    function cycleNext() {
        cycleWorkspace(true);
    }

    function cyclePrev() {
        cycleWorkspace(false);
    }

    function cycleWorkspace(forward) {
        log.info("cycleWorkspace forward=" + forward + " overviewOpen=" + overviewScope.overviewOpen);
        if (forward === undefined)
            forward = true;

        const workspaces = Hyprland.workspaces?.values || [];
        if (!workspaces || workspaces.length === 0)
            return;

        const currentWs = Hyprland.focusedWorkspace;
        const wsIds = workspaces
            .map(ws => ws?.id)
            .filter(id => id !== null && id !== undefined && id > 0)
            .sort((a, b) => a - b);
        if (wsIds.length === 0)
            return;

        if (!overviewScope.overviewOpen) {
            overviewScope.overviewOpen = true;
            const currentId = currentWs?.id ?? wsIds[0];
            const currentIndex = wsIds.indexOf(currentId);
            let targetIndex;
            if (currentIndex === -1) {
                targetIndex = forward ? 0 : wsIds.length - 1;
            } else {
                targetIndex = forward
                    ? (currentIndex + 1) % wsIds.length
                    : (currentIndex - 1 + wsIds.length) % wsIds.length;
            }
            _selectedWorkspaceId = wsIds[targetIndex];
            return;
        }

        const currentId = (_selectedWorkspaceId !== -1 && wsIds.indexOf(_selectedWorkspaceId) !== -1)
            ? _selectedWorkspaceId
            : (currentWs?.id ?? wsIds[0]);
        const currentIndex = wsIds.indexOf(currentId);

        let targetIndex;
        if (!forward) {
            targetIndex = currentIndex - 1;
            if (targetIndex < 0)
                targetIndex = wsIds.length - 1;
        } else {
            targetIndex = currentIndex + 1;
            if (targetIndex >= wsIds.length)
                targetIndex = 0;
        }

        const nextId = wsIds[targetIndex];
        log.info("cycleSelection from " + currentId + " (idx " + currentIndex + ") -> " + nextId + " (idx " + targetIndex + ")");
        _selectedWorkspaceId = nextId;
    }

    function confirmSelection() {
        if (!overviewOpen)
            return;
        const targetWs = _selectedWorkspaceId;
        overviewOpen = false;
        if (targetWs !== -1) {
            HyprlandService.focusWorkspace(targetWs);
        }
    }

    function cancelSelection() {
        _selectedWorkspaceId = -1;
        overviewOpen = false;
    }

    function selectWorkspace(wsId) {
        overviewOpen = false;
        if (wsId !== -1 && wsId !== undefined) {
            HyprlandService.focusWorkspace(wsId);
        }
    }

    Loader {
        id: hyprlandLoader
        active: overviewScope.overviewOpen
        asynchronous: false

        sourceComponent: Variants {
            id: overviewVariants
            model: Quickshell.screens

            PanelWindow {
                id: root
                required property var modelData
                readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
                property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)

                screen: modelData
                visible: overviewScope.overviewOpen && (root.monitorIsFocused || Quickshell.screens.length <= 1)
                color: "transparent"

                WlrLayershell.namespace: "dms:workspace-overview"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusiveZone: -1
                WlrLayershell.keyboardFocus: {
                    if (PopoutManager.screenshotActive)
                        return WlrKeyboardFocus.None;
                    if (!overviewScope.overviewOpen)
                        return WlrKeyboardFocus.None;
                    if (CompositorService.useHyprlandFocusGrab)
                        return WlrKeyboardFocus.OnDemand;
                    return WlrKeyboardFocus.Exclusive;
                }

                anchors {
                    top: true
                    left: true
                    right: true
                    bottom: true
                }

                HyprlandFocusGrab {
                    id: grab
                    windows: [root]
                    active: false
                    property bool hasBeenActivated: false
                    onActiveChanged: {
                        if (active) {
                            hasBeenActivated = true;
                        }
                    }
                    onCleared: () => {
                        if (hasBeenActivated && overviewScope.overviewOpen) {
                            overviewScope.cancelSelection();
                        }
                    }
                }

                Connections {
                    target: overviewScope
                    function onOverviewOpenChanged() {
                        if (overviewScope.overviewOpen) {
                            grab.hasBeenActivated = false;
                            if (CompositorService.useHyprlandFocusGrab)
                                delayedGrabTimer.start();
                        } else {
                            delayedGrabTimer.stop();
                            grab.active = false;
                            grab.hasBeenActivated = false;
                        }
                    }
                }

                Connections {
                    target: root
                    function onMonitorIsFocusedChanged() {
                        if (!CompositorService.useHyprlandFocusGrab)
                            return;
                        if (overviewScope.overviewOpen && root.monitorIsFocused && !grab.active) {
                            grab.hasBeenActivated = false;
                            grab.active = true;
                        } else if (overviewScope.overviewOpen && !root.monitorIsFocused && grab.active) {
                            grab.active = false;
                        }
                    }
                }

                Timer {
                    id: delayedGrabTimer
                    interval: 150
                    repeat: false
                    onTriggered: {
                        if (CompositorService.useHyprlandFocusGrab && overviewScope.overviewOpen && root.monitorIsFocused) {
                            grab.active = true;
                        }
                    }
                }

                Timer {
                    id: closeTimer
                    interval: 160
                    onTriggered: {
                        root.visible = false;
                    }
                }

                Rectangle {
                    id: background
                    anchors.fill: parent
                    color: "black"
                    opacity: overviewScope.overviewOpen ? 0.45 : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 150
                            easing.type: Easing.OutCubic
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: mouse => {
                            const localPos = mapToItem(contentAnchor, mouse.x, mouse.y);
                            if (localPos.x < 0 || localPos.x > contentAnchor.width || localPos.y < 0 || localPos.y > contentAnchor.height) {
                                overviewScope.cancelSelection();
                                closeTimer.restart();
                            }
                        }
                    }
                }

                Item {
                    id: contentAnchor
                    anchors.centerIn: parent
                    width: contentContainer.width
                    height: contentContainer.height

                    Item {
                        id: contentContainer
                        width: childrenRect.width
                        height: childrenRect.height
                        transformOrigin: Item.Center

                        opacity: overviewScope.overviewOpen ? 1 : 0
                        scale: overviewScope.overviewOpen ? 1.0 : 0.96

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }

                        Behavior on scale {
                            NumberAnimation {
                                duration: 150
                                easing.type: Easing.OutCubic
                            }
                        }

                        Loader {
                            id: overviewLoader
                            active: overviewScope.overviewOpen
                            asynchronous: false

                            sourceComponent: OverviewWidget {
                                panelWindow: root
                                overviewOpen: overviewScope.overviewOpen
                                selectedWorkspaceId: overviewScope._selectedWorkspaceId
                                onWorkspaceSelected: wsId => {
                                    overviewScope.selectWorkspace(wsId);
                                    closeTimer.restart();
                                }
                            }
                        }
                    }
                }

                Item {
                    id: focusScope
                    anchors.fill: parent
                    visible: overviewScope.overviewOpen
                    focus: true

                    Keys.onEscapePressed: event => {
                        overviewScope.cancelSelection();
                        event.accepted = true;
                    }

                    Keys.onReturnPressed: event => {
                        overviewScope.confirmSelection();
                        event.accepted = true;
                    }

                    Keys.onSpacePressed: event => {
                        overviewScope.confirmSelection();
                        event.accepted = true;
                    }

                    Keys.onReleased: event => {
                        log.info("Keys.onReleased: key=" + event.key + " modifiers=" + event.modifiers);
                        if (event.key === Qt.Key_Alt || event.key === Qt.Key_AltGr || event.key === Qt.Key_Meta || event.key === Qt.Key_Super_L || event.key === Qt.Key_Super_R) {
                            overviewScope.confirmSelection();
                            event.accepted = true;
                        }
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                overviewScope.cyclePrev();
                            } else {
                                overviewScope.cycleNext();
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                            overviewScope.cyclePrev();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                            overviewScope.cycleNext();
                            event.accepted = true;
                        }
                    }

                    onVisibleChanged: {
                        if (visible) {
                            Qt.callLater(() => focusScope.forceActiveFocus());
                        }
                    }

                    Connections {
                        target: root
                        function onMonitorIsFocusedChanged() {
                            if (root.monitorIsFocused && overviewScope.overviewOpen) {
                                Qt.callLater(() => focusScope.forceActiveFocus());
                            }
                        }
                    }
                }

                onVisibleChanged: {
                    if (visible && overviewScope.overviewOpen) {
                        Qt.callLater(() => focusScope.forceActiveFocus());
                    } else if (!visible) {
                        grab.active = false;
                    }
                }

                Connections {
                    target: overviewScope
                    function onOverviewOpenChanged() {
                        if (overviewScope.overviewOpen) {
                            closeTimer.stop();
                            root.visible = true;
                            Qt.callLater(() => focusScope.forceActiveFocus());
                        } else {
                            closeTimer.restart();
                            grab.active = false;
                        }
                    }
                }
            }
        }
    }
}
EOF
log_success "Đã cập nhật HyprlandOverview.qml thành công."

# ==============================================================================
# 6. Áp dụng cấu hình ngay vào phiên làm việc
# ==============================================================================
if pgrep -x "Hyprland" >/dev/null 2>&1; then
    log_info "Reload cấu hình Hyprland..."
    hyprctl reload >/dev/null 2>&1 || true
fi

if systemctl --user is-active --quiet dms 2>/dev/null || pgrep -x "dms" >/dev/null 2>&1; then
    log_info "Khởi động lại DankMaterialShell để áp dụng giao diện mới..."
    systemctl --user restart dms 2>/dev/null || dms restart >/dev/null 2>&1 || true
fi

log_success "Hoàn tất cấu hình Alt+Tab chuyển Workspace popup snapshot tĩnh:"
echo -e "  - ${BOLD}Alt + Tab${NC}                : Mở popup overview và chuyển tiếp tới workspace kế tiếp"
echo -e "  - ${BOLD}Alt + Shift + Tab${NC}          : Chuyển lùi về workspace trước đó"
echo -e "  - ${BOLD}Nhả phím Alt${NC}              : Tự động xác nhận và chuyển ngay sang workspace đang được highlight"
echo -e "  - ${BOLD}Enter / Space${NC}             : Xác nhận chuyển workspace ngay lập tức"
echo -e "  - ${BOLD}Escape / Click ngoài${NC}       : Đóng popup mà không đổi workspace"
echo -e "  - ${BOLD}Snapshot trực tiếp${NC}        : Screencopy sắc nét thời gian thực từng ứng dụng trong workspace"
echo -e "  - ${BOLD}Chống nhảy chuột${NC}          : Giữ nguyên tọa độ chuột khi đổi workspace (no_warps = true)"
