# DankMaterialShell (DMS) & CachyOS Setup Scripts

Hệ thống script tự động hóa toàn diện thiết lập môi trường desktop & lập trình cho **CachyOS / Arch Linux (Hyprland + DankMaterialShell)**.

---

## 📁 Cấu trúc thư mục

```text
setup-scripts/
├── setup.sh              # Master runner (chạy toàn bộ hoặc module riêng lẻ)
├── common.sh             # Thư viện hàm dùng chung (log, cache sudo, check user)
├── README.md             # Hướng dẫn sử dụng
└── modules/              # Các module cài đặt theo từng chức năng độc lập
    ├── 01-monitors.sh            # Thiết lập 2 màn hình (Philips trái, AOC phải, 75Hz) & Dock bên trái AOC
    ├── 02-workspaces.sh          # Thiết lập workspace cố định trên 2 màn hình
    ├── 03-apps.sh                # Cài đặt ứng dụng cơ bản (Edge, VSCode, Helium, Chromium,...)
    ├── 04-app-rules-autostart.sh # Window rules & tự khởi động ứng dụng
    ├── 05-vietnamese-ime.sh      # Bộ gõ tiếng Việt Fcitx5 (Lotus không gạch chân, Alt+Shift)
    ├── 06-dev-environment.sh     # Dev stack: PHP 8.5, Composer, Node.js 24 LTS, npm, Symfony CLI
    ├── 07-keybinds.sh            # Phím tắt Hyprland & chụp màn hình nhanh (Super+Shift+S)
    ├── 08-zsh-omz.sh             # Oh My Zsh (robbyrussell, autosuggestions, syntax-highlighting)
    ├── 09-dms-plugins.sh         # Plugin DMS Antigravity CLI (quota widget & hiển thị email)
    ├── 10-clipboard-image-attach.sh # Đính kèm ảnh clipboard vào terminal AI agent (Ctrl+Shift+V)
    ├── 11-automount-data-drive.sh   # Tự động mount phân vùng Data (NTFS) vào /mnt/Data
    ├── 12-display-manager-sddm.sh   # SDDM GUI Display Manager & theme Catppuccin Mocha
    ├── 13-dms-processlist-popup.sh  # Tùy biến popup Processes (biểu đồ Disk & nút X đóng popup)
    ├── 14-dms-workspace-switcher-alttab.sh # Popup Alt+Tab chuyển workspace dạng snapshot tĩnh, nhả Alt tự focus
    ├── 15-flutter-android-dev.sh    # [Thủ công] Môi trường Flutter, JDK 17, Android SDK & Emulator
    └── 16-cloudflare-warp.sh        # Cloudflare WARP 1.1.1.1, chống DNS leak & widget Control Center DMS
```

---

## 📋 Danh sách chi tiết các Module

| STT | Module | Mô tả chi tiết |
|:---:|:---|:---|
| **01** | `01-monitors.sh` | Thiết lập màn hình chính Philips (0x0@75Hz) bên trái, màn hình phụ AOC (1920x0@75Hz) bên phải & cấu hình thanh Dock DankMaterialShell hiển thị bên trái màn hình AOC. |
| **02** | `02-workspaces.sh` | Cố định các workspace vào màn hình: 1 (Edge), 3 (VSCode), 5, 6, 7 trên Philips; 2 (Helium), 4 (Chromium), 8, 9 trên AOC. |
| **03** | `03-apps.sh` | Cài đặt Microsoft Edge, Visual Studio Code, Helium Browser, Chromium, AppImageLauncher, LibreOffice Fresh, Sublime Text & đặt mặc định. |
| **04** | `04-app-rules-autostart.sh` | Cấu hình Hyprland window rules đưa cửa sổ vào đúng workspace chỉ định và khởi động tự động khi đăng nhập. |
| **05** | `05-vietnamese-ime.sh` | Cài đặt Fcitx5 kèm bộ gõ Lotus (không gạch chân), phím tắt chuyển ngôn ngữ `Alt + Left Shift`, chia sẻ trạng thái gõ toàn cục (`ShareInputState=All`), tự động chuyển sang Tiếng Anh khi mở Spotlight search và khôi phục Tiếng Việt khi đóng (`Super + Space` / `Super + Enter`). |
| **06** | `06-dev-environment.sh` | Cài đặt môi trường phát triển: PHP 8.5, Composer, Node.js 24 LTS, npm, Symfony CLI. |
| **07** | `07-keybinds.sh` | Phím tắt chuyển đổi Floating/Tiling (`Super + Shift + T`), chuyển workspace (`Super + 1..9`), chuyển màn hình (`Super + Alt + 1..3`), mở Dolphin (`Super + Shift + F` / `Super + E`) kèm đồng bộ Dark Theme (`qt6ct`) cho Qt/Dolphin, chụp màn hình vùng chọn không cần Enter (`Super + Shift + S`) kèm popup chỉnh sửa với Satty. |
| **08** | `08-zsh-omz.sh` | Cài đặt Zsh, Oh My Zsh, theme robbyrussell, zsh-autosuggestions, zsh-syntax-highlighting và đặt Zsh làm shell mặc định cho Kitty. |
| **09** | `09-dms-plugins.sh` | Cài đặt plugin `dms-antigravity-cli`, cấu hình hiển thị trên taskbar bên phải, patch hiển thị % quota session 5h trên bar, tự động lấy email, dọn cache và cập nhật % quota tức thì khi chuyển đổi / đăng xuất tài khoản. |
| **10** | `10-clipboard-image-attach.sh` | Tự động đính kèm ảnh từ clipboard vào terminal của các AI agent (`antigravity-cli` / `agy`): bấm `Ctrl + Shift + V` trong Kitty hoặc `Super + Shift + V` toàn hệ thống. |
| **11** | `11-automount-data-drive.sh` | Tự động mount phân vùng Data (NTFS) vào `/mnt/Data` khi boot, tạo symlink `/run/media/...` giữ tương thích và `~/Data` tiện lợi. |
| **12** | `12-display-manager-sddm.sh` | Cài đặt và cấu hình SDDM Display Manager với theme đồ họa Catppuccin Mocha nhẹ đẹp (thay thế greetd/tuigreet), tự động chuyển đổi service hệ thống. |
| **13** | `13-dms-processlist-popup.sh` | Tùy biến popup Processes của DankMaterialShell: tích hợp biểu đồ tròn theo dõi dung lượng ổ đĩa (Disk usage) cạnh CPU/RAM (click chuyển đổi ổ đĩa) và bổ sung nút 'X' đóng nhanh popup cạnh thanh tìm kiếm. |
| **14** | `14-dms-workspace-switcher-alttab.sh` | Chuyển đổi Workspace dạng popup modal giữa màn hình (`Alt + Tab`), duyệt xoay vòng các workspace với snapshot screencopy trực tiếp sắc nét thời gian thực, tự động focus chuyển workspace khi nhả phím `Alt` (hoặc nhấn `Enter`/`Space`), hỗ trợ `Alt + Shift + Tab` duyệt lùi, và chống nhảy con trỏ chuột khi đổi workspace (`no_warps = true`, `warp_on_change_workspace = 0`). |
| **15** | `15-flutter-android-dev.sh` | *(Chạy thủ công)* Cài đặt môi trường Flutter, Eclipse Temurin JDK 17, Android SDK cmdline-tools, Android Emulator (Pixel 7 AVD), cơ chế tự động đồng bộ thanh công cụ (Toolbar) luôn bám sát cạnh phải máy ảo & đồng bộ Workspace trên Hyprland, Chromium Web runner, VS Code extensions (Flutter & Dart), và biến môi trường cho Fish/Zsh/Bash. *(Mặc định được bỏ qua khi chạy `all`, chỉ chạy khi gọi riêng).* |
| **16** | `16-cloudflare-warp.sh` | Cài đặt Cloudflare WARP (`warp-cli`), kích hoạt daemon `warp-svc`, đăng ký thiết bị tự động, cấu hình chống rò rỉ DNS (DNS Leak) qua NetworkManager/systemd-resolved, và tích hợp widget nút bật/tắt nhanh trên bảng Control Center của DankMaterialShell. |

---

## 🚀 Cách sử dụng

### 1. Chạy TOÀN BỘ tất cả các module (Mặc định)
Hệ thống sẽ tự động thực thi lần lượt các module hệ thống (tự động bỏ qua các module chạy thủ công như module 15):
```bash
cd ~/setup-scripts
./setup.sh
# hoặc: ./setup.sh all
```

### 2. Xem danh sách các module có sẵn
```bash
./setup.sh list
```

### 3. Chạy RIÊNG một module cụ thể
- **Theo số thứ tự:**
  ```bash
  ./setup.sh 07
  ```
- **Theo tên / từ khóa:**
  ```bash
  ./setup.sh keybinds
  # hoặc:
  ./setup.sh run 07-keybinds.sh
  ```
- **Qua menu tương tác:**
  ```bash
  ./setup.sh menu
  ```
- **Chạy trực tiếp file module:**
  ```bash
  ./modules/07-keybinds.sh
  ```
