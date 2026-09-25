#!/usr/bin/env bash
# Description: Cài đặt Flutter SDK, Temurin JDK 17, Android SDK, Emulator & đồng bộ toolbar cạnh phải trên Hyprland
# ManualOnly: true
set -eo pipefail


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

log_info "Bắt đầu thiết lập môi trường phát triển Flutter & Android..."

# 1. Kiểm tra và cài đặt các tiện ích hệ thống cần thiết
log_info "Kiểm tra các gói phụ thuộc hệ thống..."
CORE_DEPS=("git" "curl" "unzip" "tar")
MISSING_CORE=()
for dep in "${CORE_DEPS[@]}"; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        MISSING_CORE+=("$dep")
    fi
done

if [[ ${#MISSING_CORE[@]} -gt 0 ]]; then
    log_info "Cài đặt các gói cốt lõi còn thiếu: ${MISSING_CORE[*]}..."
    cache_sudo
    sudo pacman -S --needed --noconfirm "${MISSING_CORE[@]}"
else
    log_info "Các gói phụ thuộc cốt lõi (git, curl, unzip, tar) đã sẵn sàng."
fi

# Tùy chọn: các gói hỗ trợ biên dịch Linux Desktop
DESKTOP_DEPS=("pkg-config" "clang" "cmake" "ninja" "gtk3")
MISSING_DESKTOP=()
for dep in "${DESKTOP_DEPS[@]}"; do
    if ! pacman -Qi "$dep" >/dev/null 2>&1 && ! command -v "$dep" >/dev/null 2>&1; then
        MISSING_DESKTOP+=("$dep")
    fi
done

if [[ ${#MISSING_DESKTOP[@]} -gt 0 ]]; then
    if sudo -n true 2>/dev/null || [ -t 0 ]; then
        log_info "Cài đặt các gói hỗ trợ Linux Desktop: ${MISSING_DESKTOP[*]}..."
        cache_sudo
        if sudo -n true 2>/dev/null; then
            sudo pacman -S --needed --noconfirm "${MISSING_DESKTOP[@]}" || log_warning "Không thể cài đặt gói Linux Desktop, bỏ qua."
        fi
    else
        log_info "Bỏ qua cài đặt các gói Linux desktop (${MISSING_DESKTOP[*]}) trong phiên tự động."
    fi
fi


# 2. Cài đặt Eclipse Temurin OpenJDK 17 vào ~/.jdks/temurin-17
JDK_DIR="${HOME}/.jdks/temurin-17"
if [[ -x "${JDK_DIR}/bin/java" ]]; then
    log_info "Java JDK 17 đã tồn tại tại ${JDK_DIR}."
else
    log_info "Đang tải và cài đặt Eclipse Temurin OpenJDK 17..."
    mkdir -p "${JDK_DIR}"
    TAR_TMP="/tmp/temurin-17.tar.gz"
    curl -fsSL "https://api.adoptium.net/v3/binary/latest/17/ga/linux/x64/jdk/hotspot/normal/eclipse" -o "$TAR_TMP"
    tar -xzf "$TAR_TMP" -C "$JDK_DIR" --strip-components=1
    rm -f "$TAR_TMP"
    log_success "Đã cài đặt JDK 17 thành công."
fi

# Xuất biến môi trường tạm thời cho phiên chạy script hiện tại
export JAVA_HOME="${JDK_DIR}"
export ANDROID_HOME="${HOME}/Android/Sdk"
export ANDROID_SDK_ROOT="${HOME}/Android/Sdk"
export CHROME_EXECUTABLE="/usr/bin/chromium"
export PATH="${JAVA_HOME}/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${ANDROID_HOME}/emulator:${HOME}/development/flutter/bin:${PATH}"


# 3. Cài đặt Android SDK Command-line Tools vào ~/Android/Sdk
CMDLINE_DIR="${ANDROID_HOME}/cmdline-tools/latest"
if [[ -x "${CMDLINE_DIR}/bin/sdkmanager" ]]; then
    log_info "Android Command-line Tools đã có sẵn tại ${CMDLINE_DIR}."
else
    log_info "Đang tải Android Command-line Tools..."
    mkdir -p "${ANDROID_HOME}/cmdline-tools"
    
    # Tìm kiếm phiên bản cmdline-tools mới nhất từ trang chủ Google Android
    CMDLINE_ZIP_NAME=$(curl -fsSL https://developer.android.com/studio#command-tools | grep -o 'commandlinetools-linux-[0-9_]*latest\.zip' | head -n 1 || echo "")
    if [[ -z "$CMDLINE_ZIP_NAME" ]]; then
        CMDLINE_ZIP_NAME="commandlinetools-linux-15859902_latest.zip"
    fi
    
    ZIP_TMP="/tmp/cmdline-tools.zip"
    EXTRACT_TMP="/tmp/cmdline-tools-extracted"
    rm -rf "$EXTRACT_TMP" "$ZIP_TMP"
    
    curl -fsSL "https://dl.google.com/android/repository/${CMDLINE_ZIP_NAME}" -o "$ZIP_TMP"
    unzip -q "$ZIP_TMP" -d "$EXTRACT_TMP"
    rm -rf "$CMDLINE_DIR"
    mv "${EXTRACT_TMP}/cmdline-tools" "$CMDLINE_DIR"
    rm -f "$ZIP_TMP"
    rm -rf "$EXTRACT_TMP"
    log_success "Đã cài đặt Android Command-line Tools vào ${CMDLINE_DIR}."
fi

# Chấp nhận giấy phép Android SDK và cài đặt các thành phần thiết yếu
log_info "Cài đặt các gói Android SDK cần thiết (platform-tools, build-tools, platforms, emulator)..."
yes | "${CMDLINE_DIR}/bin/sdkmanager" --licenses >/dev/null 2>&1 || true

REQUIRED_SDK_PKGS=(
    "platform-tools"
    "build-tools;36.0.0"
    "platforms;android-36"
    "emulator"
)

for pkg in "${REQUIRED_SDK_PKGS[@]}"; do
    pkg_dir=$(echo "$pkg" | tr ';' '/')
    if [[ -d "${ANDROID_HOME}/${pkg_dir}" ]]; then
        log_info "SDK package [${pkg}] đã được cài đặt."
    else
        log_info "Đang tải SDK package [${pkg}]..."
        "${CMDLINE_DIR}/bin/sdkmanager" "$pkg"
    fi
done

# 4. Cài đặt Android System Image và khởi tạo Máy ảo (AVD Emulator)
SYS_IMG="system-images;android-34;google_apis;x86_64"
AVD_NAME="flutter_emulator"

log_info "Kiểm tra Android Emulator (${AVD_NAME})..."
if [[ -d "${ANDROID_HOME}/system-images/android-34/google_apis/x86_64" ]]; then
    log_info "System image [${SYS_IMG}] đã được cài đặt."
else
    log_info "Đang tải System Image [${SYS_IMG}]..."
    yes | "${CMDLINE_DIR}/bin/sdkmanager" "$SYS_IMG"
fi

if "${CMDLINE_DIR}/bin/avdmanager" list avd 2>/dev/null | grep -q "Name: ${AVD_NAME}"; then
    log_info "Máy ảo Android [${AVD_NAME}] đã tồn tại."
else
    log_info "Đang tạo máy ảo Android [${AVD_NAME}] (Pixel 7)..."
    echo "no" | "${CMDLINE_DIR}/bin/avdmanager" create avd -n "$AVD_NAME" -k "$SYS_IMG" --device "pixel_7" --force
    log_success "Đã tạo thành công máy ảo [${AVD_NAME}]."
fi

# 5. Cài đặt Flutter SDK vào ~/development/flutter
FLUTTER_DIR="${HOME}/development/flutter"
if [[ -x "${FLUTTER_DIR}/bin/flutter" ]]; then
    log_info "Flutter SDK đã có sẵn tại ${FLUTTER_DIR}."
else
    log_info "Đang clone Flutter SDK (nhánh stable) vào ${FLUTTER_DIR}..."
    mkdir -p "${HOME}/development"
    git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_DIR"
    log_success "Đã tải Flutter SDK thành công."
fi

# Cấu hình đường dẫn cho Flutter
log_info "Cấu hình Android SDK và JDK cho Flutter..."
"${FLUTTER_DIR}/bin/flutter" config --android-sdk "$ANDROID_HOME" >/dev/null 2>&1 || true
"${FLUTTER_DIR}/bin/flutter" config --jdk-dir "$JAVA_HOME" >/dev/null 2>&1 || true
yes | "${FLUTTER_DIR}/bin/flutter" doctor --android-licenses >/dev/null 2>&1 || true

# 6. Cài đặt tiện ích mở rộng Flutter & Dart cho VS Code (nếu có VS Code)
if command -v code >/dev/null 2>&1; then
    log_info "Cài đặt extension Flutter & Dart cho Visual Studio Code..."
    code --install-extension dart-code.dart-code --force >/dev/null 2>&1 || true
    code --install-extension dart-code.flutter --force >/dev/null 2>&1 || true
    log_success "Đã kích hoạt extension Dart & Flutter trên VS Code."
fi

# 7. Cấu hình biến môi trường và PATH vào các Shell (Fish, Zsh, Bash)
log_info "Cập nhật biến môi trường vào các shell..."

# --- Fish Shell ---
FISH_CONFIG="${HOME}/.config/fish/config.fish"
if [[ -f "$FISH_CONFIG" ]]; then
    if ! grep -q "JAVA_HOME.*temurin-17" "$FISH_CONFIG"; then
        cat <<'EOF' >> "$FISH_CONFIG"

# Java JDK 17 (Temurin)
set -gx JAVA_HOME "$HOME/.jdks/temurin-17"
fish_add_path "$JAVA_HOME/bin"

# Android SDK
set -gx ANDROID_HOME "$HOME/Android/Sdk"
set -gx ANDROID_SDK_ROOT "$HOME/Android/Sdk"
fish_add_path "$ANDROID_HOME/cmdline-tools/latest/bin"
fish_add_path "$ANDROID_HOME/platform-tools"
fish_add_path "$ANDROID_HOME/emulator"

# Flutter SDK
fish_add_path "$HOME/development/flutter/bin"

# Web Development (Chromium)
set -gx CHROME_EXECUTABLE "/usr/bin/chromium"
EOF
        log_success "Đã cập nhật cấu hình cho Fish Shell (~/.config/fish/config.fish)."
    fi
fi

# --- Zsh Shell ---
ZSH_CONFIG="${HOME}/.zshrc"
if [[ -f "$ZSH_CONFIG" ]]; then
    if ! grep -q "JAVA_HOME.*temurin-17" "$ZSH_CONFIG"; then
        cat <<'EOF' >> "$ZSH_CONFIG"

# Java JDK 17 (Temurin)
export JAVA_HOME="$HOME/.jdks/temurin-17"
export PATH="$JAVA_HOME/bin:$PATH"

# Android SDK
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

# Flutter SDK
export PATH="$HOME/development/flutter/bin:$PATH"

# Web Development (Chromium)
export CHROME_EXECUTABLE="/usr/bin/chromium"
EOF
        log_success "Đã cập nhật cấu hình cho Zsh Shell (~/.zshrc)."
    fi
fi

# --- Bash Shell ---
BASH_CONFIG="${HOME}/.bashrc"
if [[ -f "$BASH_CONFIG" ]]; then
    if ! grep -q "JAVA_HOME.*temurin-17" "$BASH_CONFIG"; then
        cat <<'EOF' >> "$BASH_CONFIG"

# Java JDK 17 (Temurin)
export JAVA_HOME="$HOME/.jdks/temurin-17"
export PATH="$JAVA_HOME/bin:$PATH"

# Android SDK
export ANDROID_HOME="$HOME/Android/Sdk"
export ANDROID_SDK_ROOT="$HOME/Android/Sdk"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"

# Flutter SDK
export PATH="$HOME/development/flutter/bin:$PATH"

# Web Development (Chromium)
export CHROME_EXECUTABLE="/usr/bin/chromium"
EOF
        log_success "Đã cập nhật cấu hình cho Bash Shell (~/.bashrc)."
    fi
fi

# 8. Cấu hình tự động đồng bộ thanh công cụ (Toolbar) bám sát cạnh phải máy ảo Android trên Hyprland
log_info "Cấu hình thanh công cụ Android Emulator luôn bám sát cạnh phải trên Hyprland..."

# Tạo daemon script: ~/.local/bin/hypr-emulator-toolbar-sync.py
mkdir -p "${HOME}/.local/bin"
cat << 'EOF' > "${HOME}/.local/bin/hypr-emulator-toolbar-sync.py"
#!/usr/bin/env python3
"""
hypr-emulator-toolbar-sync.py
Đảm bảo thanh công cụ (Toolbar) của Android Emulator luôn luôn bám sát cạnh phải của màn hình máy ảo
ngay cả khi di chuyển trên màn hình hoặc chuyển sang workspace khác trên Hyprland.
"""

import os
import sys
import time
import fcntl
import json
import socket
import select

LOCK_FILE = f"/tmp/hypr-emulator-toolbar-sync-{os.getuid()}.lock"


def get_hyprland_sockets():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not sig:
        hypr_base = os.path.join(runtime_dir, "hypr")
        if os.path.isdir(hypr_base):
            dirs = [d for d in os.listdir(hypr_base) if os.path.isdir(os.path.join(hypr_base, d))]
            if dirs:
                sig = dirs[0]
    if not sig:
        return None, None
    s1 = os.path.join(runtime_dir, "hypr", sig, ".socket.sock")
    s2 = os.path.join(runtime_dir, "hypr", sig, ".socket2.sock")
    return s1, s2


def send_dispatch(sock_path, raw_cmd):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.5)
        s.connect(sock_path)
        escaped = raw_cmd.replace('"', '\\"')
        payload = f'/dispatch hl.dsp.exec_raw("{escaped}")\n'.encode("utf-8")
        s.sendall(payload)
        resp = s.recv(1024)
        s.close()
        return resp
    except Exception:
        return None


def get_clients(sock_path):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.5)
        s.connect(sock_path)
        s.sendall(b"j/clients")
        buf = b""
        while True:
            d = s.recv(4096)
            if not d:
                break
            buf += d
        s.close()
        return json.loads(buf)
    except Exception:
        return []


def sync_toolbar(sock1):
    clients = get_clients(sock1)
    if not clients:
        return False

    emulators_by_pid = {}
    for c in clients:
        cls = c.get("class", "")
        if cls.lower() == "emulator":
            pid = c.get("pid")
            if pid not in emulators_by_pid:
                emulators_by_pid[pid] = {"main": None, "toolbar": None}
            title = c.get("title", "")
            width = c.get("size", [0, 0])[0]
            if title.startswith("Android Emulator") or width >= 150:
                emulators_by_pid[pid]["main"] = c
            elif title == "Emulator" or width < 120:
                emulators_by_pid[pid]["toolbar"] = c

    has_any_emulator = False
    for pid, pair in emulators_by_pid.items():
        main = pair["main"]
        toolbar = pair["toolbar"]
        if main and toolbar:
            has_any_emulator = True
            mx, my = main["at"]
            mw, mh = main["size"]
            m_ws = main["workspace"]["id"]

            tx, ty = toolbar["at"]
            t_ws = toolbar["workspace"]["id"]

            target_x = mx + mw
            target_y = my

            # 1. Đồng bộ Workspace nếu máy ảo chuyển workspace
            if t_ws != m_ws:
                send_dispatch(sock1, f"movetoworkspacesilent {m_ws},address:{toolbar['address']}")

            # 2. Đồng bộ vị trí bám sát cạnh phải nếu có xê dịch
            if abs(tx - target_x) > 1 or abs(ty - target_y) > 1:
                send_dispatch(sock1, f"movewindowpixel exact {target_x} {target_y},address:{toolbar['address']}")

    return has_any_emulator


def main():
    try:
        lock_fd = open(LOCK_FILE, "w")
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except Exception:
        sys.exit(0)

    sock1, sock2 = get_hyprland_sockets()
    if not sock1 or not os.path.exists(sock1):
        sys.exit(1)

    s2 = None
    try:
        s2 = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s2.connect(sock2)
        s2.setblocking(False)
    except Exception:
        s2 = None

    try:
        while True:
            has_emu = sync_toolbar(sock1)
            timeout = 0.03 if has_emu else 1.0

            if s2:
                try:
                    r, _, _ = select.select([s2], [], [], timeout)
                    if r:
                        while True:
                            chunk = s2.recv(4096)
                            if not chunk or len(chunk) < 4096:
                                break
                        sync_toolbar(sock1)
                except Exception:
                    time.sleep(timeout)
            else:
                time.sleep(timeout)

    except KeyboardInterrupt:
        pass
    finally:
        if s2:
            s2.close()


if __name__ == "__main__":
    main()
EOF
chmod +x "${HOME}/.local/bin/hypr-emulator-toolbar-sync.py"
log_success "Đã tạo daemon đồng bộ toolbar tại ~/.local/bin/hypr-emulator-toolbar-sync.py"

# Cấu hình Window Rules trong Hyprland (windowrules.lua)
HYPR_RULES="${HOME}/.config/hypr/config/windowrules.lua"
if [[ -f "$HYPR_RULES" ]]; then
    if ! grep -q 'class = "^(\[Ee\]mulator)\$"' "$HYPR_RULES"; then
        python3 - <<'PYEOF'
import os
path = os.path.expanduser("~/.config/hypr/config/windowrules.lua")
with open(path, "r") as f:
    c = f.read()
rule = '-- Android Emulator & Toolbar\nhl.window_rule({ match = { class = "^([Ee]mulator)$" }, float = true, center = true, monitor = PRIMARY_MONITOR })\nhl.window_rule({ match = { class = "^([Ee]mulator)$", title = "^(Emulator)$" }, no_initial_focus = true })\n\n'
if "-- Apps" in c:
    c = c.replace("-- Apps", rule + "-- Apps")
else:
    c = c + "\n" + rule
with open(path, "w") as f:
    f.write(c)
PYEOF
        log_success "Đã thêm Window Rule floating cho Android Emulator vào windowrules.lua"
    fi
fi

# Cấu hình Autostart trong Hyprland (autostart.lua)
AUTOSTART_LUA="${HOME}/.config/hypr/config/autostart.lua"
if [[ -f "$AUTOSTART_LUA" ]]; then
    if ! grep -q "hypr-emulator-toolbar-sync.py" "$AUTOSTART_LUA"; then
        sed -i '/hl.exec_cmd("chromium")/a \    hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/hypr-emulator-toolbar-sync.py")' "$AUTOSTART_LUA"
        log_success "Đã đăng ký hypr-emulator-toolbar-sync.py vào autostart.lua"
    fi
fi

# Thiết lập Systemd User Service để quản lý daemon tự khởi động & tự phục hồi
mkdir -p "${HOME}/.config/systemd/user"
cat << 'EOF' > "${HOME}/.config/systemd/user/hypr-emulator-toolbar-sync.service"
[Unit]
Description=Android Emulator Toolbar Sync for Hyprland
PartOf=graphical-session.target
After=graphical-session.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 %h/.local/bin/hypr-emulator-toolbar-sync.py
Restart=always
RestartSec=2

[Install]
WantedBy=graphical-session.target
EOF

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable --now hypr-emulator-toolbar-sync.service 2>/dev/null || true
if pgrep -x "Hyprland" >/dev/null 2>&1; then
    hyprctl reload >/dev/null 2>&1 || true
fi
log_success "Đã kích hoạt dịch vụ hypr-emulator-toolbar-sync.service"

# 9. Kiểm tra tổng kết trạng thái
log_header "KIỂM TRA TRẠNG THÁI FLUTTER (flutter doctor)"
"${FLUTTER_DIR}/bin/flutter" doctor -v || true

log_success "Hoàn tất cài đặt môi trường Flutter & Android!"
echo -e "  - Flutter SDK:        ${FLUTTER_DIR}"
echo -e "  - Java JDK:           ${JDK_DIR} (OpenJDK 17)"
echo -e "  - Android SDK:        ${ANDROID_HOME}"
echo -e "  - Android Emulator:   ${AVD_NAME} (khởi chạy: flutter emulators --launch ${AVD_NAME})"
echo -e "  - Emulator Toolbar:   Đã kích hoạt tự động bám cạnh phải máy ảo & đồng bộ Workspace"
echo -e "  - Web Runner:         Chromium (/usr/bin/chromium)"
echo -e "  - VS Code:            Đã cài đặt extension Flutter & Dart"

