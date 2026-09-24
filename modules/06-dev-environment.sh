#!/usr/bin/env bash
# Description: Cài đặt môi trường Dev (PHP 8.5, Composer, Node.js 24 LTS, npm, Symfony CLI)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

cache_sudo

log_info "Bắt đầu cài đặt môi trường phát triển (PHP 8.5, Composer, Node.js 24 LTS, Symfony CLI)..."

# 1. Cài đặt PHP 8.5, các extension và Composer
log_info "Cài đặt PHP 8.5 và Composer..."
PHP_PACKAGES=(
    "php"
    "php-gd"
    "php-sqlite"
    "php-sodium"
    "php-pgsql"
    "composer"
)

for pkg in "${PHP_PACKAGES[@]}"; do
    if pacman -Qi "$pkg" >/dev/null 2>&1; then
        log_info "Gói [${pkg}] đã được cài đặt."
    else
        log_info "Đang cài đặt [${pkg}]..."
        yay -S --needed --noconfirm "$pkg"
    fi
done

# Cấu hình kích hoạt các extension thiết yếu trong /etc/php/php.ini cho Symfony & Composer
log_info "Kích hoạt các extension cần thiết cho Symfony & Composer trong /etc/php/php.ini..."
if [[ -f /etc/php/php.ini ]]; then
    sudo sed -i -E 's/^;(extension=(bcmath|bz2|calendar|curl|exif|fileinfo|gd|gettext|iconv|intl|mbstring|mysqli|openssl|pdo_mysql|pdo_sqlite|sodium|sqlite3|zip))/\1/' /etc/php/php.ini
    sudo sed -i -E 's/^memory_limit[[:space:]]*=.*/memory_limit = 512M/' /etc/php/php.ini
    log_success "Đã cấu hình các extension trong /etc/php/php.ini thành công."
fi

# 2. Cài đặt Node.js 24 LTS (Krypton) và npm
log_info "Cài đặt Node.js 24 LTS và npm..."
NODE_PACKAGES=(
    "nodejs-lts-krypton"
    "npm"
)

for pkg in "${NODE_PACKAGES[@]}"; do
    if pacman -Qi "$pkg" >/dev/null 2>&1; then
        log_info "Gói [${pkg}] đã được cài đặt."
    else
        log_info "Đang cài đặt [${pkg}]..."
        yay -S --needed --noconfirm "$pkg"
    fi
done

# 3. Cài đặt Symfony CLI
log_info "Cài đặt Symfony CLI..."
if command -v symfony >/dev/null 2>&1; then
    log_info "Symfony CLI đã được cài đặt từ trước."
else
    if yay -S --needed --noconfirm symfony-cli-bin 2>/dev/null; then
        log_success "Đã cài đặt symfony-cli-bin từ AUR."
    else
        log_info "Cài đặt Symfony CLI qua script chính thức..."
        curl -sS https://get.symfony.com/cli/installer | bash
        mkdir -p "${HOME}/.local/bin"
        if [[ -f "${HOME}/.symfony5/bin/symfony" ]]; then
            ln -sf "${HOME}/.symfony5/bin/symfony" "${HOME}/.local/bin/symfony"
        fi
        log_success "Đã cài đặt Symfony CLI vào ~/.local/bin/symfony."
    fi
fi

# 4. Cài đặt GitHub CLI (gh) và vô hiệu hóa GNOME Keyring
log_info "Cài đặt GitHub CLI (gh)..."
if pacman -Qi github-cli >/dev/null 2>&1; then
    log_info "GitHub CLI đã được cài đặt từ trước."
else
    log_info "Đang cài đặt github-cli..."
    yay -S --needed --noconfirm github-cli
fi

# Vô hiệu hóa GNOME Keyring trên Hyprland (tránh lỗi treo ngầm do gcr-prompter không hiện popup nhập mật khẩu)
log_info "Kiểm tra và vô hiệu hóa GNOME Keyring daemon..."
systemctl --user stop gnome-keyring-daemon.service gnome-keyring-daemon.socket 2>/dev/null || true
systemctl --user mask gnome-keyring-daemon.service gnome-keyring-daemon.socket 2>/dev/null || true
if pacman -Qi gnome-keyring >/dev/null 2>&1; then
    log_info "Gỡ bỏ gói gnome-keyring không cần thiết..."
    sudo pacman -Rdd --noconfirm gnome-keyring 2>/dev/null || true
fi
sudo rm -f /etc/xdg/autostart/gnome-keyring-*.desktop 2>/dev/null || true

# Đảm bảo ~/.local/bin nằm trong PATH
for rc in "${HOME}/.bashrc" "${HOME}/.zshrc"; do
    if [[ -f "$rc" ]] && ! grep -q 'export PATH=.*\.local/bin' "$rc"; then
        echo -e '\nexport PATH="$HOME/.local/bin:$PATH"' >> "$rc"
    fi
done

log_success "Hoàn tất thiết lập môi trường Dev!"
echo "--- Kiểm tra phiên bản ---"
php -v 2>/dev/null | head -n 1 || true
composer --version 2>/dev/null || true
node -v 2>/dev/null || true
npm -v 2>/dev/null | sed 's/^/npm v/' || true
symfony version 2>/dev/null || true
