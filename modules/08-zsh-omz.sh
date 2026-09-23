#!/usr/bin/env bash
# Description: Cài đặt và cấu hình Oh My Zsh (Theme robbyrussell, autosuggestions, syntax-highlighting) cho Terminal
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

log_info "Bắt đầu thiết lập Oh My Zsh cho Terminal..."

# 1. Kiểm tra các gói cần thiết
REQUIRED_PKGS=()
for pkg in zsh git curl; do
    if ! command -v "$pkg" >/dev/null 2>&1; then
        REQUIRED_PKGS+=("$pkg")
    fi
done

if [[ ${#REQUIRED_PKGS[@]} -gt 0 ]]; then
    log_info "Cài đặt các gói phụ thuộc còn thiếu: ${REQUIRED_PKGS[*]}..."
    cache_sudo
    sudo pacman -S --needed --noconfirm "${REQUIRED_PKGS[@]}"
fi

# 2. Cài đặt Oh My Zsh nếu chưa có
ZSH_DIR="${HOME}/.oh-my-zsh"
if [[ ! -d "$ZSH_DIR" ]]; then
    log_info "Đang clone Oh My Zsh vào ~/.oh-my-zsh..."
    git clone --depth=1 https://github.com/ohmyzsh/ohmyzsh.git "$ZSH_DIR"
else
    log_info "Oh My Zsh đã tồn tại tại ~/.oh-my-zsh"
fi

# 3. Thiết lập Plugins và Themes (ưu tiên symlink từ hệ thống nếu có, fallback git clone)
CUSTOM_PLUGINS_DIR="${ZSH_DIR}/custom/plugins"
CUSTOM_THEMES_DIR="${ZSH_DIR}/custom/themes"
mkdir -p "$CUSTOM_PLUGINS_DIR" "$CUSTOM_THEMES_DIR"

# zsh-autosuggestions
if [[ -d "/usr/share/zsh/plugins/zsh-autosuggestions" ]]; then
    ln -sfn /usr/share/zsh/plugins/zsh-autosuggestions "${CUSTOM_PLUGINS_DIR}/zsh-autosuggestions"
elif [[ ! -d "${CUSTOM_PLUGINS_DIR}/zsh-autosuggestions" ]]; then
    log_info "Đang clone zsh-autosuggestions..."
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions "${CUSTOM_PLUGINS_DIR}/zsh-autosuggestions"
fi

# zsh-syntax-highlighting
if [[ -d "/usr/share/zsh/plugins/zsh-syntax-highlighting" ]]; then
    ln -sfn /usr/share/zsh/plugins/zsh-syntax-highlighting "${CUSTOM_PLUGINS_DIR}/zsh-syntax-highlighting"
elif [[ ! -d "${CUSTOM_PLUGINS_DIR}/zsh-syntax-highlighting" ]]; then
    log_info "Đang clone zsh-syntax-highlighting..."
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "${CUSTOM_PLUGINS_DIR}/zsh-syntax-highlighting"
fi

# powerlevel10k theme
if [[ -d "/usr/share/zsh-theme-powerlevel10k" ]]; then
    ln -sfn /usr/share/zsh-theme-powerlevel10k "${CUSTOM_THEMES_DIR}/powerlevel10k"
elif [[ ! -d "${CUSTOM_THEMES_DIR}/powerlevel10k" ]]; then
    log_info "Đang clone Powerlevel10k theme..."
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${CUSTOM_THEMES_DIR}/powerlevel10k"
fi

# 4. Tạo hoặc cập nhật file cấu hình ~/.zshrc
ZSHRC_FILE="${HOME}/.zshrc"
if [[ -f "$ZSHRC_FILE" && ! -f "${ZSHRC_FILE}.bak" ]]; then
    cp "$ZSHRC_FILE" "${ZSHRC_FILE}.bak"
    log_info "Đã sao lưu ~/.zshrc cũ thành ~/.zshrc.bak"
fi

log_info "Cấu hình file ~/.zshrc với theme robbyrussell và plugins..."
cat <<'EOF' > "$ZSHRC_FILE"
# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Set name of the theme to load
# See https://github.com/ohmyzsh/ohmyzsh/wiki/Themes
# Gợi ý: Có thể đổi thành "powerlevel10k/powerlevel10k" nếu muốn dùng Powerlevel10k
ZSH_THEME="robbyrussell"

# Case-sensitive / Hyphen settings
HYPHEN_INSENSITIVE="true"

# Display red dots whilst waiting for completion.
COMPLETION_WAITING_DOTS="true"

# Which plugins would you like to load?
plugins=(
    git
    zsh-autosuggestions
    zsh-syntax-highlighting
    history-substring-search
    sudo
)

source $ZSH/oh-my-zsh.sh

# User configuration & PATH
export PATH="$HOME/.local/bin:$HOME/.config/composer/vendor/bin:$PATH"

# Default Editor (Sublime Text)
export EDITOR="subl -w"
export VISUAL="subl -w"

# Useful Aliases
alias c="clear"
alias ll="ls -lah --color=auto"
alias la="ls -A --color=auto"
alias l="ls -CF --color=auto"
alias update="sudo pacman -Syu"
EOF

# 5. Cấu hình Kitty và Alacritty để luôn mở zsh làm shell chính
log_info "Cấu hình shell zsh cho Kitty và Alacritty..."
KITTY_CONF="${HOME}/.config/kitty/kitty.conf"
if [[ -f "$KITTY_CONF" ]]; then
    if grep -q "^shell " "$KITTY_CONF"; then
        sed -i 's|^shell .*|shell /usr/bin/zsh|' "$KITTY_CONF"
    else
        echo -e "\nshell /usr/bin/zsh" >> "$KITTY_CONF"
    fi
fi

ALACRITTY_CONF="${HOME}/.config/alacritty/alacritty.toml"
if [[ -f "$ALACRITTY_CONF" ]]; then
    if ! grep -q "\[terminal\.shell\]" "$ALACRITTY_CONF"; then
        sed -i '/^\[env\]/i \[terminal.shell\]\nprogram = "/usr/bin/zsh"\n' "$ALACRITTY_CONF"
    fi
fi

# 6. Đổi default login shell sang zsh nếu người dùng chạy trong terminal tương tác hoặc có sudo
ZSH_PATH=$(which zsh || echo "/usr/bin/zsh")
CURRENT_LOGIN_SHELL=$(getent passwd "$USER" | cut -d: -f7)

if [[ "$CURRENT_LOGIN_SHELL" != "$ZSH_PATH" ]]; then
    if sudo -n true 2>/dev/null; then
        sudo usermod -s "$ZSH_PATH" "$USER" 2>/dev/null || true
        log_success "Đã cập nhật login shell trong /etc/passwd thành $ZSH_PATH"
    else
        log_info "Terminal (Kitty/Alacritty) đã được cấu hình tự động mở zsh trực tiếp."
        log_info "Để đổi login shell toàn hệ thống trong /etc/passwd, bạn có thể chạy lệnh: chsh -s $ZSH_PATH"
    fi
fi

# 7. Kiểm tra tính hợp lệ của cấu hình zsh
log_info "Kiểm tra cú pháp và khả năng khởi động của zsh..."
zsh -i -c 'echo "Oh My Zsh đã tải thành công!"' >/dev/null 2>&1 || {
    log_error "Lỗi cú pháp khi tải zshrc!"
    exit 1
}

log_success "Hoàn tất cài đặt và cấu hình Oh My Zsh:"
echo -e "  - Framework:  Oh My Zsh tại ~/.oh-my-zsh"
echo -e "  - Theme:      robbyrussell (mặc định sạch đẹp, có thể đổi sang powerlevel10k)"
echo -e "  - Plugins:    git, zsh-autosuggestions, zsh-syntax-highlighting, history-substring-search, sudo"
echo -e "  - Terminal:   Đã thiết lập Kitty và Alacritty tự động khởi chạy Zsh"
