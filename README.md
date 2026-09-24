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
    ├── 01-monitors.sh            # Thiết lập 2 màn hình (Philips trái, AOC phải, 75Hz)
    ├── 02-workspaces.sh          # Thiết lập workspace cố định trên 2 màn hình
    ├── 03-apps.sh                # Cài đặt ứng dụng cơ bản (Edge, VSCode, Helium, Chromium,...)
    ├── 04-app-rules-autostart.sh # Window rules & tự khởi động ứng dụng
    ├── 05-vietnamese-ime.sh      # Bộ gõ tiếng Việt Fcitx5 (Lotus không gạch chân, Alt+Shift)
    ├── 06-dev-environment.sh     # Dev stack: PHP 8.5, Composer, Node.js 24 LTS, npm, Symfony CLI
    ├── 07-keybinds.sh            # Phím tắt Hyprland & chụp màn hình nhanh (Super+Shift+S)
    ├── 08-zsh-omz.sh             # Oh My Zsh (robbyrussell, autosuggestions, syntax-highlighting)
    ├── 09-dms-plugins.sh         # Plugin DMS Antigravity CLI (quota widget & hiển thị email)
    └── 10-clipboard-image-attach.sh # Đính kèm ảnh clipboard vào terminal AI agent (Ctrl+Shift+V)
```

---

## 📋 Danh sách chi tiết các Module

| STT | Module | Mô tả chi tiết |
|:---:|:---|:---|
| **01** | `01-monitors.sh` | Thiết lập màn hình chính Philips (0x0@75Hz) bên trái, màn hình phụ AOC (1920x0@75Hz) bên phải. |
| **02** | `02-workspaces.sh` | Cố định các workspace vào màn hình: 1 (Edge), 2 (Helium), 3 (VSCode), 4 (Chromium), 5 trên Philips; 8, 9 trên AOC. |
| **03** | `03-apps.sh` | Cài đặt Microsoft Edge, Visual Studio Code, Helium Browser, Chromium, AppImageLauncher, LibreOffice Fresh, Sublime Text & đặt mặc định. |
| **04** | `04-app-rules-autostart.sh` | Cấu hình Hyprland window rules đưa cửa sổ vào đúng workspace chỉ định và khởi động tự động khi đăng nhập. |
| **05** | `05-vietnamese-ime.sh` | Cài đặt Fcitx5 kèm bộ gõ Lotus (không gạch chân), phím tắt chuyển ngôn ngữ `Alt + Left Shift`, chia sẻ trạng thái gõ toàn cục (`ShareInputState=All`), tự động chuyển sang Tiếng Anh khi mở Spotlight search và khôi phục Tiếng Việt khi đóng (`Super + Space` / `Super + Enter`). |
| **06** | `06-dev-environment.sh` | Cài đặt môi trường phát triển: PHP 8.5, Composer, Node.js 24 LTS, npm, Symfony CLI. |
| **07** | `07-keybinds.sh` | Phím tắt chuyển workspace (`Super + 1..9`), chuyển màn hình (`Super + Alt + 1..3`), mở Dolphin (`Super + Shift + F` / `Super + E`) kèm đồng bộ Dark Theme (`qt6ct`) cho Qt/Dolphin, chụp màn hình vùng chọn không cần Enter (`Super + Shift + S`) kèm popup chỉnh sửa với Satty. |
| **08** | `08-zsh-omz.sh` | Cài đặt Zsh, Oh My Zsh, theme robbyrussell, zsh-autosuggestions, zsh-syntax-highlighting và đặt Zsh làm shell mặc định cho Kitty. |
| **09** | `09-dms-plugins.sh` | Cài đặt plugin `dms-antigravity-cli`, cấu hình hiển thị trên taskbar bên phải, patch tự động lấy email, dọn cache và cập nhật % quota tức thì khi chuyển đổi / đăng xuất tài khoản. |
| **10** | `10-clipboard-image-attach.sh` | Tự động đính kèm ảnh từ clipboard vào terminal của các AI agent (`antigravity-cli` / `agy`): bấm `Ctrl + Shift + V` trong Kitty hoặc `Super + Shift + V` toàn hệ thống. |
| **11** | `11-automount-data-drive.sh` | Tự động mount phân vùng Data (NTFS) vào `/mnt/Data` khi boot, tạo symlink `/run/media/...` giữ tương thích và `~/Data` tiện lợi. |

---

## 🚀 Cách sử dụng

### 1. Chạy TOÀN BỘ tất cả các module (Mặc định)
Hệ thống sẽ tự động thực thi lần lượt từ module 01 đến 11:
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
