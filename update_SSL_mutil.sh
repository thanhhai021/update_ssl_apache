#!/bin/bash

echo -e "[?] Nhập domain cần cập nhật SSL (VD: example.com): \c"
read domain

# Cài mod_ssl
echo "[+] Cài đặt mod_ssl..."
sudo a2enmod ssl 2>/dev/null

# Bật mod_rewrite nếu chưa có
if ! apache2ctl -M | grep -q rewrite_module; then
    echo "[+] Bật mod_rewrite..."
    sudo a2enmod rewrite
else
    echo "[+] mod_rewrite đã được bật."
fi

config_file="/etc/apache2/sites-available/$domain.conf"

if [ ! -f "$config_file" ]; then
    echo "[!] Không tìm thấy file cấu hình: $config_file"
    exit 1
fi

echo "[+] Đã tìm thấy file cấu hình: $config_file"

# Tìm các dòng chứa SSL
crt_line=$(grep -i "SSLCertificateFile" "$config_file" | awk '{print $2}')
key_line=$(grep -i "SSLCertificateKeyFile" "$config_file" | awk '{print $2}')
ca_line=$(grep -i "SSLCertificateChainFile" "$config_file" | awk '{print $2}')

echo "[+] Đường dẫn SSL đang dùng:"
echo "    - Certificate File     : $crt_line"
echo "    - Private Key File     : $key_line"
echo "    - CA Chain File (nếu có): $ca_line"

# Hỏi đường dẫn mới
echo -e "[?] Nhập thư mục chứa SSL mới (VD: /root/newssl/): \c"
read ssl_path

if [ ! -d "$ssl_path" ]; then
    echo "[!] Thư mục $ssl_path không tồn tại!"
    exit 1
fi

echo "[+] Danh sách file trong $ssl_path:"
ls -lh "$ssl_path"

# Cập nhật SSL
echo "[+] Đang cập nhật SSL..."

[ -n "$crt_line" ] && cp "$ssl_path"/*.crt "$crt_line" && echo "[+] Đã cập nhật CRT (fullchain)"
[ -n "$key_line" ] && cp "$ssl_path"/*.key "$key_line" && echo "[+] Đã cập nhật KEY"
[ -n "$ca_line" ]  && cp "$ssl_path"/*.ca-bundle "$ca_line" && echo "[+] Đã cập nhật CA"

# Kiểm tra cấu hình Apache
echo "[+] Kiểm tra cấu hình Apache..."
if apachectl configtest; then
    echo "[+] Cấu hình hợp lệ. Reload Apache..."
    systemctl reload apache2
else
    echo "[!] Cấu hình Apache lỗi. Hủy reload!"
    exit 1
fi

# Kiểm tra SSL với curl
echo "[+] Kiểm tra SSL bằng curl:"
curl -vkI https://$domain 2>&1 | grep -E "subject:|issuer:"

echo "✅ Hoàn tất cập nhật SSL cho $domain"
