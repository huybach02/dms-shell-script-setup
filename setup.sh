#!/usr/bin/env bash
# ==============================================================================
# Master Setup Script (CachyOS / Arch Linux)
# - Mặc định chạy toàn bộ các module theo thứ tự
# - Cho phép chạy riêng từng module (theo tên, số thứ tự, hoặc menu chọn)
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODULES_DIR="${SCRIPT_DIR}/modules"

# Nạp thư viện chung
if [[ -f "${SCRIPT_DIR}/common.sh" ]]; then
    source "${SCRIPT_DIR}/common.sh"
else
    echo "Lỗi: Không tìm thấy ${SCRIPT_DIR}/common.sh"
    exit 1
fi

# Lấy danh sách tất cả các module file (.sh)
get_modules() {
    if [[ -d "$MODULES_DIR" ]]; then
        find "$MODULES_DIR" -maxdepth 1 -name "*.sh" -type f | sort
    fi
}

# Liệt kê danh sách module
list_modules() {
    echo -e "${CYAN}=== DANH SÁCH MODULE HIỆN CÓ ===${NC}"
    local mods=($(get_modules))
    if [[ ${#mods[@]} -eq 0 ]]; then
        echo -e "${YELLOW}(Chưa có module nào trong modules/)${NC}"
        return
    fi

    local idx=1
    for mod in "${mods[@]}"; do
        local filename=$(basename "$mod")
        # Đọc dòng mô tả đầu tiên trong file nếu có (dòng comment # Description: ...)
        local desc=$(grep -m 1 "^# Description:" "$mod" | sed 's/^# Description:[[:space:]]*//' || echo "")
        local is_manual=$(grep -m 1 -i "^# ManualOnly:[[:space:]]*true" "$mod" || echo "")
        local tag=""
        if [[ -n "$is_manual" ]]; then
            tag=" ${YELLOW}[Thủ công]${NC}"
        fi

        if [[ -n "$desc" ]]; then
            printf "  ${BOLD}%2d)${NC} %-25s - %s%b\n" "$idx" "$filename" "$desc" "$tag"
        else
            printf "  ${BOLD}%2d)${NC} %-25s%b\n" "$idx" "$filename" "$tag"
        fi
        ((idx++))
    done
    echo ""
}

# Chạy một file module cụ thể
execute_module() {
    local mod_path="$1"
    local mod_name=$(basename "$mod_path")

    if [[ ! -f "$mod_path" ]]; then
        log_error "Không tìm thấy module: $mod_path"
        return 1
    fi

    log_header "ĐANG THỰC THI MODULE: $mod_name"
    chmod +x "$mod_path"
    
    if bash "$mod_path"; then
        log_success "Đã hoàn thành module: $mod_name"
    else
        log_error "Thất bại khi thực thi module: $mod_name"
        return 1
    fi
}

# Chạy tất cả các module
run_all_modules() {
    local mods=($(get_modules))
    if [[ ${#mods[@]} -eq 0 ]]; then
        log_warning "Chưa có module nào trong $MODULES_DIR để chạy."
        return
    fi

    log_header "BẮT ĐẦU CHẠY TOÀN BỘ CÁC BƯỚC SETUP"

    for mod in "${mods[@]}"; do
        if grep -qi "^# ManualOnly:[[:space:]]*true" "$mod"; then
            log_info "Bỏ qua module chỉ chạy thủ công: $(basename "$mod") (chạy riêng: ./setup.sh $(basename "$mod" .sh | cut -d'-' -f1))"
            continue
        fi
        execute_module "$mod"
    done

    log_header "TẤT CẢ CÁC MODULE ĐÃ HOÀN TẤT THÀNH CÔNG!"
}

# Tìm module theo từ khóa hoặc số thứ tự
find_and_run_module() {
    local query="$1"
    local mods=($(get_modules))

    # Trường hợp 1: người dùng nhập số (ví dụ: 1 hoặc 01)
    if [[ "$query" =~ ^[0-9]+$ ]]; then
        local target_index=$((10#$query - 1))
        if [[ $target_index -ge 0 && $target_index -lt ${#mods[@]} ]]; then
            execute_module "${mods[$target_index]}"
            return 0
        fi
    fi

    # Trường hợp 2: tìm theo tên file chính xác hoặc tiền tố
    for mod in "${mods[@]}"; do
        local name=$(basename "$mod")
        if [[ "$name" == "$query" || "$name" == "$query.sh" || "$name" =~ ^0*${query} || "$name" == *"$query"* ]]; then
            execute_module "$mod"
            return 0
        fi
    done

    log_error "Không tìm thấy module phù hợp với: '$query'"
    list_modules
    return 1
}

# Menu chọn tương tác
interactive_menu() {
    local mods=($(get_modules))
    if [[ ${#mods[@]} -eq 0 ]]; then
        log_warning "Chưa có module nào trong $MODULES_DIR."
        return
    fi

    echo -e "${CYAN}=== CHỌN MODULE CẦN CHẠY ===${NC}"
    list_modules
    echo -e "   ${BOLD}a)${NC} Chạy TẤT CẢ các module"
    echo -e "   ${BOLD}q)${NC} Thoát"
    echo ""
    read -rp "Nhập lựa chọn của bạn [1-${#mods[@]} / a / q]: " choice

    case "$choice" in
        a|A)
            cache_sudo
            run_all_modules
            ;;
        q|Q)
            echo "Đã hủy."
            exit 0
            ;;
        *)
            cache_sudo
            find_and_run_module "$choice"
            ;;
    esac
}

show_help() {
    echo -e "${BOLD}HƯỚNG DẪN SỬ DỤNG SETUP SCRIPT:${NC}"
    echo "  ./setup.sh               Mặc định: Chạy toàn bộ các module"
    echo "  ./setup.sh all           Chạy toàn bộ các module"
    echo "  ./setup.sh list          Hiển thị danh sách các module có sẵn"
    echo "  ./setup.sh menu          Mở menu tương tác để chọn module muốn chạy"
    echo "  ./setup.sh <tên_hoặc_số> Chạy riêng một module cụ thể"
    echo ""
    echo -e "${BOLD}Ví dụ:${NC}"
    echo "  ./setup.sh 01             Chạy module bắt đầu bằng 01"
    echo "  ./setup.sh packages       Chạy module có tên chứa 'packages'"
    echo "  ./setup.sh run 01-packages.sh"
    echo "  ./modules/01-packages.sh  (Có thể chạy trực tiếp file module)"
}

main() {
    check_user

    local arg="${1:-all}"

    case "$arg" in
        all|"")
            cache_sudo
            run_all_modules
            ;;
        list)
            list_modules
            ;;
        menu|-i|--interactive)
            interactive_menu
            ;;
        help|--help|-h)
            show_help
            ;;
        run)
            if [[ -z "${2:-}" ]]; then
                log_error "Vui lòng chỉ định tên hoặc số module cần chạy!"
                list_modules
                exit 1
            fi
            cache_sudo
            find_and_run_module "$2"
            ;;
        *)
            cache_sudo
            find_and_run_module "$arg"
            ;;
    esac
}

main "$@"
