#!/bin/bash

# Kiểm tra quyền root
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script bằng quyền root (sudo)"
  exit 1
fi

# ====== Load Config từ file .env ======
if [ -f .env ]; then
  echo "[INIT] Đang nạp cấu hình từ .env..."
  source .env
else
  echo "Không tìm thấy file .env. Thoát."
  exit 1
fi

# ====== Kiểm tra các biến bắt buộc ======
REQUIRED_VARS=("IPA_SERVER" "IPA_DOMAIN" "IPA_REALM" "IPA_FORWARDER" "IPA_DS_PASS")
for var in "${REQUIRED_VARS[@]}"; do
  if [ -z "${!var}" ]; then
    echo "Thiếu biến cấu hình: $var. Vui lòng kiểm tra file .env"
    exit 1
  fi
done
# ====== Nhập mật khẩu admin IPA ======
while true; do
  read -s -p "Nhập mật khẩu IPA admin (IPA_ADMIN_PASS): " IPA_ADMIN_PASS
  echo
  read -s -p "Nhập lại mật khẩu để xác nhận: " IPA_ADMIN_PASS_CONFIRM
  echo

  if [[ "$IPA_ADMIN_PASS" == "$IPA_ADMIN_PASS_CONFIRM" ]]; then
    break
  else
    echo "Mật khẩu không khớp. Vui lòng thử lại."
  fi
done


# Thông số
IP_ADDRESS=$(hostname -I | awk '{print $1}')

# Đặt hostname
echo "Đặt hostname: $IPA_SERVER"
hostnamectl set-hostname "$IPA_SERVER"

# Cập nhật /etc/hosts
echo "Cập nhật /etc/hosts với IP: $IP_ADDRESS"
if ! grep -q "$IPA_SERVER" /etc/hosts; then
  echo "$IP_ADDRESS $IPA_SERVER ipa" >> /etc/hosts
fi

# Cập nhật hệ thống và cài repo FreeIPA
echo "Cài đặt các gói cần thiết và repo FreeIPA..."
dnf update -y
dnf install -y epel-release

# Kích hoạt đúng module của FreeIPA cho CentOS Stream 8
echo "Kích hoạt module idm:DL1 để cài FreeIPA..."
dnf module enable -y idm:DL1


# Cài đặt các gói FreeIPA
echo "Cài đặt FreeIPA Server và DNS plugin..."
dnf install -y ipa-server ipa-server-dns bind-dyndb-ldap

# Kiểm tra lại đã cài thành công chưa
if ! rpm -q ipa-server >/dev/null; then
  echo "Cài đặt ipa-server thất bại. Dừng lại!"
  exit 1
fi

# Mở firewall
echo "Cấu hình firewall..."
firewall-cmd --add-service={freeipa-ldap,freeipa-ldaps,dns,http,https,kerberos,kpasswd} --permanent
firewall-cmd --reload

# Cài FreeIPA Server
echo "Bắt đầu cài đặt FreeIPA..."
ipa-server-install -U \
  --hostname="$IPA_SERVER" \
  --domain="$IPA_DOMAIN" \
  --realm="$IPA_REALM" \
  --setup-dns \
  --forwarder="$IPA_FORWARDER" \
  --no-ntp \
  --ds-password="$IPA_DS_PASS" \
  --admin-password="$IPA_ADMIN_PASS"

# Kiểm tra trạng thái
echo "Trạng thái sau khi cài:"
if command -v ipactl >/dev/null; then
  ipactl status
else
  echo "Không tìm thấy lệnh ipactl. Có thể cần khởi động lại shell hoặc kiểm tra lại cài đặt."
fi

# Thông tin hoàn tất
echo "Cài đặt FreeIPA hoàn tất!"
echo "Truy cập Web UI: https://$IPA_SERVER"
echo "   Username: admin"
echo "   Password: $IPA_ADMIN_PASS"
