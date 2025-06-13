#!/bin/bash

# Tự động xác định hệ điều hành và gói cần cài
function install_mod_ssl() {
    echo "[+] Cài đặt mod_ssl..."
    if command -v dnf &>/dev/null; then
        dnf install -y mod_ssl
    elif command -v yum &>/dev/null; then
        yum install -y mod_ssl
    elif command -v apt &>/dev/null; then
        apt update && apt install -y apache2 ssl-cert
        a2enmod ssl
    fi
}

# Yêu cầu nhập domain
read -rp "[?] Nhập domain cần cập nhật SSL: " domain
domain="${domain,,}" # Viết thường
[[ -z "$domain" ]] && echo "[!] Domain không hợp lệ!" && exit 1

echo "[+] Tìm file cấu hình Apache chứa domain $domain..."
conf_file=$(grep -ril "$domain" /etc/httpd/conf.d/*.conf /etc/apache2/sites-available/*.conf 2>/dev/null | head -n1)
if [[ -z "$conf_file" ]]; then
    conf_file="/etc/httpd/conf.d/$domain.conf"
    [[ ! -d /etc/httpd/conf.d ]] && conf_file="/etc/apache2/sites-available/$domain.conf"
    echo "[+] Tạo file cấu hình Apache: $conf_file"
    mkdir -p "$(dirname "$conf_file")"
    echo "<VirtualHost *:443>
    ServerName $domain
    DocumentRoot /var/www/$domain
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/$domain.crt
    SSLCertificateKeyFile /etc/ssl/private/$domain.key
    SSLCertificateChainFile /etc/ssl/certs/$domain.ca-bundle
</VirtualHost>" > "$conf_file"
fi
echo "[+] Đang dùng file cấu hình: $conf_file"

# Trích xuất đường dẫn SSL hiện tại
crt_path=$(grep -i "SSLCertificateFile" "$conf_file" | awk '{print $2}' | head -n1)
key_path=$(grep -i "SSLCertificateKeyFile" "$conf_file" | awk '{print $2}' | head -n1)
ca_path=$(grep -i "SSLCertificateChainFile" "$conf_file" | awk '{print $2}' | head -n1)

echo "[+] Đường dẫn SSL hiện tại:"
echo "    CRT: $crt_path"
echo "    KEY: $key_path"
echo "    CA : $ca_path"

# Nhập đường dẫn SSL mới
read -rp "[?] Nhập đường dẫn thư mục chứa file SSL mới (default: /etc/ssl/certs): " new_dir
new_dir="${new_dir:-/etc/ssl/certs}"
new_dir="${new_dir%/}"  # Xoá dấu / cuối nếu có

echo "[+] Danh sách file trong $new_dir:"
find "$new_dir" -type f \( -iname "*.crt" -o -iname "*.key" -o -iname "*.pem" -o -iname "*ca*" -o -iname "*bundle*" \) -exec ls -lh {} +

# Xác định file mới
new_crt=$(find "$new_dir" -iname "$domain.crt" -o -iname "$domain.pem" 2>/dev/null | head -n1)
new_key=$(find "$new_dir" -iname "$domain.key" 2>/dev/null | head -n1)
new_ca=$(find "$new_dir" -iname "*ca*" -o -iname "*bundle*" -o -iname "*.pem" 2>/dev/null | grep -v "$new_crt" | head -n1)

# Kiểm tra hợp lệ của chuỗi chứng chỉ
if [[ -n "$new_crt" && -n "$new_key" ]]; then
    echo "[+] Kiểm tra chuỗi chứng chỉ mới..."
    openssl x509 -noout -modulus -in "$new_crt" | openssl md5 > /tmp/crt.md5
    openssl rsa  -noout -modulus -in "$new_key" | openssl md5 > /tmp/key.md5
    if cmp -s /tmp/crt.md5 /tmp/key.md5; then
        echo "[+] CRT và KEY hợp lệ."
    else
        echo "[!] CRT và KEY không khớp. Thoát."
        exit 1
    fi
fi

# Backup SSL cũ
timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="/etc/ssl/backup/${domain}-$timestamp"
mkdir -p "$backup_dir"
[[ -f "$crt_path" ]] && cp "$crt_path" "$backup_dir/"
[[ -f "$key_path" ]] && cp "$key_path" "$backup_dir/"
[[ -f "$ca_path"  ]] && cp "$ca_path" "$backup_dir/"
echo "[+] Đã backup SSL cũ vào: $backup_dir"

# Ghi CRT
if [[ -n "$new_crt" && -s "$new_crt" ]]; then
    if [[ -n "$new_ca" && -s "$new_ca" ]]; then
        echo "[+] Gộp CRT và CA vào fullchain..."
        cat "$new_crt" "$new_ca" > "$crt_path"
    else
        cp "$new_crt" "$crt_path"
    fi
    echo "[+] Đã cập nhật CRT"
else
    echo "[!] Thiếu file CRT mới, bỏ qua."
fi

# Ghi KEY
[[ -n "$new_key" && -s "$new_key" ]] && cp "$new_key" "$key_path" && echo "[+] Đã cập nhật KEY" || echo "[!] Thiếu KEY mới, bỏ qua."

# Ghi CA nếu cần
[[ -n "$ca_path" && -n "$new_ca" && -s "$new_ca" ]] && cp "$new_ca" "$ca_path" && echo "[+] Đã cập nhật CA" || echo "[!] Bỏ qua CA-BUNDLE."

# Thêm ServerName nếu chưa có
apache_conf="/etc/httpd/conf/httpd.conf"
[[ ! -f "$apache_conf" ]] && apache_conf="/etc/apache2/apache2.conf"
grep -q "^ServerName" "$apache_conf" || echo "ServerName localhost" >> "$apache_conf" && echo "[+] Đã thêm ServerName localhost vào $apache_conf"

# Kiểm tra cấu hình
echo "[+] Kiểm tra lại cấu hình Apache..."
if apachectl configtest 2>&1 | grep -q "Syntax OK"; then
    echo "[+] Cấu hình hợp lệ. Đang khởi động lại Apache..."
    systemctl restart httpd 2>/dev/null || systemctl restart apache2
    echo "[+] Apache khởi động lại thành công."
else
    echo "[!] Cấu hình Apache lỗi. Hủy khởi động lại."
fi

# Kiểm tra SSL thực tế
echo "[+] Kiểm tra SSL bằng openssl:"
echo | openssl s_client -connect "$domain:443" 2>/dev/null | openssl x509 -noout -subject -issuer
