#!/usr/bin/env bash
# Description: Tự động mount phân vùng Data (NTFS) vào /mnt/Data khi khởi động và tạo symlink tương thích
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_LIB="${SCRIPT_DIR}/../common.sh"
[[ -f "$COMMON_LIB" ]] && source "$COMMON_LIB"

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_user
fi

cache_sudo

TARGET_UUID="8E3A42193A41FEA9"
MOUNT_POINT="/mnt/Data"
RUN_MEDIA_DIR="/run/media/${USER}"
OLD_PATH="${RUN_MEDIA_DIR}/${TARGET_UUID}"
HOME_DATA_SYMLINK="${HOME}/Data"

log_info "Bắt đầu thiết lập tự động mount phân vùng Data (UUID: ${TARGET_UUID})..."

# 1. Kiểm tra sự tồn tại của phân vùng
DEVICE=$(blkid -U "$TARGET_UUID" || true)
if [[ -z "$DEVICE" ]]; then
    log_warning "Không tìm thấy thiết bị nào với UUID=${TARGET_UUID} lúc này."
    log_info "Tiến trình sẽ tiếp tục ghi cấu hình fstab với tùy chọn 'nofail' để mount khi gắn ổ."
else
    log_info "Đã phát hiện thiết bị: ${DEVICE} (UUID: ${TARGET_UUID})"
fi

# 2. Tạo thư mục mount point chuẩn Linux /mnt/Data
if [[ ! -d "$MOUNT_POINT" ]]; then
    log_info "Tạo thư mục mount point: ${MOUNT_POINT}..."
    sudo mkdir -p "$MOUNT_POINT"
fi
sudo chown -R "${USER}:${USER}" "$MOUNT_POINT" 2>/dev/null || true

# 3. Cấu hình /etc/fstab
FSTAB_LINE="UUID=${TARGET_UUID} ${MOUNT_POINT} ntfs3 rw,nosuid,nodev,relatime,uid=1000,gid=1000,iocharset=utf8,nofail,x-systemd.automount 0 0"

if grep -q "$TARGET_UUID" /etc/fstab; then
    log_info "UUID ${TARGET_UUID} đã tồn tại trong /etc/fstab. Đang cập nhật cấu hình tối ưu..."
    sudo sed -i "\|${TARGET_UUID}|c\\${FSTAB_LINE}" /etc/fstab
else
    log_info "Thêm phân vùng vào /etc/fstab..."
    echo -e "\n# Automount Data partition (${MOUNT_POINT})\n${FSTAB_LINE}" | sudo tee -a /etc/fstab >/dev/null
fi

# 4. Tạo cấu hình systemd-tmpfiles để duy trì symlink trong /run/media ngay sau khi boot
# (Do /run là tmpfs trên RAM, tmpfiles.d đảm bảo đường dẫn cũ luôn tồn tại)
TMPFILES_CONF="/etc/tmpfiles.d/data-drive-symlink.conf"
log_info "Thiết lập quy tắc tmpfiles để tự động tạo symlink tương thích trong /run/media..."
sudo mkdir -p /etc/tmpfiles.d
sudo tee "$TMPFILES_CONF" >/dev/null <<EOF
# Tự động tạo cấu trúc symlink tương thích cho phân vùng Data
d /run/media 0755 root root -
d /run/media/${USER} 0700 ${USER} ${USER} -
L+ /run/media/${USER}/${TARGET_UUID} - - - - ${MOUNT_POINT}
EOF

# 5. Nếu phân vùng đang được mount tạm tại /run/media/..., chuyển sang /mnt/Data
if mountpoint -q "$OLD_PATH" 2>/dev/null; then
    log_info "Tháo mount tạm thời tại ${OLD_PATH}..."
    sudo umount "$OLD_PATH" 2>/dev/null || true
fi

# Áp dụng tmpfiles ngay lập tức
sudo systemd-tmpfiles --create "$TMPFILES_CONF" 2>/dev/null || true

# Tạo symlink tiện ích trong thư mục Home (~/Data -> /mnt/Data)
ln -sfn "$MOUNT_POINT" "$HOME_DATA_SYMLINK"

# 6. Nạp lại cấu hình systemd và mount thử nghiệm
log_info "Nạp lại systemd daemon và mount phân vùng..."
sudo systemctl daemon-reload
sudo mount "$MOUNT_POINT" 2>/dev/null || sudo mount -a 2>/dev/null || true

if mountpoint -q "$MOUNT_POINT"; then
    log_success "Đã mount thành công phân vùng vào ${MOUNT_POINT}!"
else
    log_info "Phân vùng đã được thiết lập automount (sẽ tự động kích hoạt ngay khi bạn truy cập)."
fi

log_success "Hoàn tất cấu hình tự động mount:"
echo -e "  - Điểm mount chính: ${BOLD}${MOUNT_POINT}${NC}"
echo -e "  - Symlink tương thích cũ: ${BOLD}${OLD_PATH}${NC} -> ${MOUNT_POINT}"
echo -e "  - Symlink tiện lợi tại Home: ${BOLD}${HOME_DATA_SYMLINK}${NC} -> ${MOUNT_POINT}"
echo -e "  - Tùy chọn an toàn: Tự động kích hoạt khi boot, không gây treo máy nếu rút ổ (nofail, x-systemd.automount)"
