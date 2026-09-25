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

# Biến lưu PID của tiến trình giữ sudo phiên làm việc
SUDO_KEEPALIVE_PID=""

# Dọn dẹp tiến trình giữ sudo khi script kết thúc
cleanup_sudo_keepalive() {
    if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
        kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
        SUDO_KEEPALIVE_PID=""
    fi
}

# Cache sudo session và tự động refresh liên tục trong nền (chỉ hỏi pass 1 lần duy nhất)
cache_sudo() {
    # Nếu đã có tiến trình keepalive đang chạy cho script hiện tại, không spawn thêm
    if [[ -n "$SUDO_KEEPALIVE_PID" ]] && kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null; then
        return 0
    fi

    # Kiểm tra xem sudo đã được cấp quyền chưa (đã có timestamp hợp lệ)
    if sudo -n true 2>/dev/null; then
        # Duy trì sudo timestamp mỗi 50 giây trong nền cho tới khi process cha ($$) kết thúc
        (while true; do sudo -n -v 2>/dev/null || exit; sleep 50; kill -0 "$$" 2>/dev/null || exit; done) &
        SUDO_KEEPALIVE_PID=$!
        trap cleanup_sudo_keepalive EXIT INT TERM
        return 0
    fi

    # Nếu chưa có sudo và đang chạy trong terminal tương tác
    if [ -t 0 ] || [ -c /dev/tty ]; then
        log_info "Yêu cầu quyền Administrator (sudo) cho toàn bộ quá trình chạy script..."
        log_info "Bạn chỉ cần nhập mật khẩu 1 lần duy nhất:"
        if ! sudo -v; then
            log_error "Mật khẩu sudo không chính xác hoặc đã bị hủy!"
            exit 1
        fi

        # Giữ sudo session sống liên tục bằng background loop mỗi 50 giây
        (while true; do sudo -n -v 2>/dev/null || exit; sleep 50; kill -0 "$$" 2>/dev/null || exit; done) &
        SUDO_KEEPALIVE_PID=$!
        trap cleanup_sudo_keepalive EXIT INT TERM
        log_success "Đã kích hoạt phiên làm việc sudo. Các bước tiếp theo sẽ tự động chạy không cần hỏi lại."
    fi
}

