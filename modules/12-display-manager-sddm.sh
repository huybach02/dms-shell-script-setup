#!/usr/bin/env bash
# Description: Cài đặt và cấu hình SDDM Display Manager với theme đồ họa Catppuccin Mocha nhẹ đẹp (thay thế greetd/tuigreet)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

cache_sudo

THEME_NAME="catppuccin-mocha-mauve"
SDDM_CONF_DIR="/etc/sddm.conf.d"
THEME_CONF="${SDDM_CONF_DIR}/theme.conf"

log_info "Bắt đầu thiết lập Display Manager SDDM (Giao diện đồ họa)..."

# 1. Cài đặt SDDM và các gói phụ thuộc Qt6 cơ bản
PACKAGES=(sddm qt6-5compat qt6-declarative qt6-svg)
TO_INSTALL=()

for pkg in "${PACKAGES[@]}"; do
    if ! pacman -Qq "$pkg" >/dev/null 2>&1; then
        TO_INSTALL+=("$pkg")
    fi
done

if [[ ${#TO_INSTALL[@]} -gt 0 ]]; then
    log_info "Cài đặt các gói thành phần SDDM (${TO_INSTALL[*]})..."
    sudo pacman -S --noconfirm --needed "${TO_INSTALL[@]}"
else
    log_success "Các thành phần SDDM và Qt6 cơ bản đã được cài đặt."
fi

# 2. Cài đặt Catppuccin Mocha Theme (qua yay)
if [[ ! -d "/usr/share/sddm/themes/${THEME_NAME}" ]]; then
    log_info "Đang cài đặt theme catppuccin-sddm-theme-mocha từ AUR..."
    yay -S --noconfirm --needed catppuccin-sddm-theme-mocha
else
    log_success "Theme ${THEME_NAME} đã tồn tại trong /usr/share/sddm/themes/."
fi

# 3. Gỡ bỏ theme Astronaut (nếu còn tồn tại) để dọn sạch dung lượng
if pacman -Qq sddm-astronaut-theme >/dev/null 2>&1; then
    log_info "Phát hiện sddm-astronaut-theme, đang gỡ bỏ để giải phóng dung lượng..."
    sudo pacman -Rns --noconfirm sddm-astronaut-theme 2>/dev/null || true
    rm -rf "${HOME}/.cache/yay/sddm-astronaut-theme" 2>/dev/null || true
fi

# 4. Cấu hình theme cho SDDM
log_info "Thiết lập cấu hình theme cho SDDM trong ${THEME_CONF}..."
sudo mkdir -p "$SDDM_CONF_DIR"
sudo tee "$THEME_CONF" >/dev/null <<EOF
[Theme]
Current=${THEME_NAME}
EOF

# 5. Chuyển đổi service từ greetd sang sddm
if systemctl is-enabled greetd.service >/dev/null 2>&1; then
    log_info "Vô hiệu hóa greetd.service..."
    sudo systemctl disable greetd.service
fi

if ! systemctl is-enabled sddm.service >/dev/null 2>&1; then
    log_info "Kích hoạt sddm.service khi khởi động máy..."
    sudo systemctl enable sddm.service
else
    log_success "sddm.service đã được kích hoạt."
fi

log_success "Hoàn tất thiết lập Display Manager SDDM!"
echo -e "  - Display Manager: ${BOLD}SDDM${NC}"
echo -e "  - Theme: ${BOLD}${THEME_NAME}${NC} (Catppuccin Mocha - Mauve)"
echo -e "  - File cấu hình: ${BOLD}${THEME_CONF}${NC}"
echo -e "  - Kiểm tra xem trước: ${BOLD}sddm-greeter-qt6 --test-mode --theme /usr/share/sddm/themes/${THEME_NAME}${NC}"
