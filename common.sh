#!/usr/bin/env bash
# ==============================================================================
# common.sh - Chứa các hàm và biến dùng chung cho Master Script và các Module
# ==============================================================================

# Định dạng màu sắc terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "\n${CYAN}================================================================${NC}"
    echo -e "${CYAN}${BOLD}>> $1${NC}"
    echo -e "${CYAN}================================================================${NC}"
}

# Đảm bảo không chạy toàn bộ script dưới quyền root (để yay hoạt động bình thường)
check_user() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Vui lòng KHÔNG chạy script trực tiếp bằng root (sudo)!"
        log_info "Hãy chạy với user thường. Script sẽ tự gọi sudo khi cần thao tác hệ thống."
        exit 1
    fi
}

# Cache sudo session chỉ khi thực sự cần và có terminal tương tác
cache_sudo() {
    if sudo -n true 2>/dev/null; then
        # Sudo đã được cấp quyền không cần mật khẩu
        (while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done) 2>/dev/null &
    elif [ -t 0 ]; then
        log_info "Đang yêu cầu quyền sudo..."
        sudo -v
        (while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done) 2>/dev/null &
    fi
}
