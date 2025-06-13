#!/bin/bash

# Kiểm tra quyền root
if [[ $EUID -ne 0 ]]; then
    echo "[!] Vui lòng chạy script với quyền root."
    exit 1
fi

# Cài đặt mod_ssl nếu chưa có
echo "[+] Cài đặt mod_ssl..."
if command -v dnf >/dev/null 2>&1; then
    dnf install -y mod_ssl >/dev/null 2>&1
elif command -v yum >/dev/null 2>&1; then
    yum install -y mod_ssl >/dev/null 2>&1
elif command -v apt >/dev/null 2>&1; then
    apt update -y && apt install -y apache2 ssl-cert >/dev/null 2>&1
else
    echo "[!] Không tìm được công cụ cài đặt phù hợp (dnf/yum/apt)."
    exit 1
fi

# Nhập domain
read -rp "[?] Nhập domain cần cập nhật SSL: " domain
domain="${domain,,}"  # lowercase

# Tìm file cấu hình .conf
echo "[+] Tìm file cấu hình Apache chứa domain $domain..."
conf_file=$(grep -ril "$domain" /etc/httpd/conf.d/*.conf 2>/dev/null || grep -ril "$domain" /etc/apache2/sites-available/*.conf 2>/dev/null)

if [[ -z "$conf_file" ]]; then
    conf_file="/etc/httpd/conf.d/$domain.conf"
    echo "[+] Tạo file cấu hình mới: $conf_file"
    cat <<EOF > "$conf_file"
<VirtualHost *:443>
    ServerName $domain
    DocumentRoot /var/www/html

    SSLEngine on
    SSLCertificateFile /etc/ssl/$domain/$domain.crt
    SSLCertificateKeyFile /etc/ssl/$domain/$domain.key
    SSLCertificateChainFile /etc/ssl/$domain/$domain.ca-bundle

    <Directory /var/www/html>
        AllowOverride All
    </Directory>
</VirtualHost>
EOF
fi

echo "[+] Đang dùng file cấu hình: $conf_file"
crt_path=$(grep -i "SSLCertificateFile" "$conf_file" | awk '{print $2}')
key_path=$(grep -i "SSLCertificateKeyFile" "$conf_file" | awk '{print $2}')
ca_path=$(grep -i "SSLCertificateChainFile" "$conf_file" | awk '{print $2}')
echo "[+] Đường dẫn SSL hiện tại:"
echo "    CRT: $crt_path"
echo "    KEY: $key_path"
echo "    CA : $ca_path"

# Nhập thư mục SSL mới
default_dir=$(dirname "$crt_path")
read -rp "[?] Nhập đường dẫn thư mục chứa file SSL mới (default: $default_dir): " new_dir
new_dir="${new_dir:-$default_dir}"
new_dir="${new_dir%/}"

# Tìm file SSL mới
new_crt=$(find "$new_dir" -iname "$domain.crt" 2>/dev/null | head -n1)
new_key=$(find "$new_dir" -iname "$domain.key" 2>/dev/null | head -n1)
new_ca=$(find "$new_dir" -iname "$domain.ca*" -o -iname "*ca-bundle*" 2>/dev/null | head -n1)

# Kiểm tra chuỗi chứng chỉ hợp lệ
if [[ -f "$new_crt" && -f "$new_key" ]]; then
    echo "[+] Kiểm tra chuỗi chứng chỉ mới..."
    if ! openssl x509 -noout -modulus -in "$new_crt" | grep -q "$(openssl rsa -noout -modulus -in "$new_key" 2>/dev/null)"; then
        echo "[!] CRT và KEY không khớp! Dừng lại."
        exit 1
    fi
    echo "[+] CRT và KEY hợp lệ."
fi

# Backup SSL cũ
timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="/etc/ssl/backup/$domain-$timestamp"
mkdir -p "$backup_dir"

[[ -f "$crt_path" ]] && cp "$crt_path" "$backup_dir/"
[[ -f "$key_path" ]] && cp "$key_path" "$backup_dir/"
[[ -f "$ca_path" ]]  && cp "$ca_path"  "$backup_dir/"
echo "[+] Đã backup SSL cũ vào: $backup_dir"

# Ghi đè nội dung mới
mkdir -p "$(dirname "$crt_path")"

if [[ -f "$new_crt" ]]; then
    if [[ -f "$new_ca" ]]; then
        echo "[+] Gộp CRT và CA vào fullchain..."
        cat "$new_crt" "$new_ca" > "$crt_path"
    else
        cp "$new_crt" "$crt_path"
    fi
    echo "[+] Đã cập nhật CRT"
fi

if [[ -f "$new_key" ]]; then
    cp "$new_key" "$key_path"
    echo "[+] Đã cập nhật KEY"
fi

if [[ -f "$new_ca" ]]; then
    cp "$new_ca" "$ca_path"
    echo "[+] Đã cập nhật CA"
fi

# Đảm bảo có ServerName
httpd_conf="/etc/httpd/conf/httpd.conf"
apache2_conf="/etc/apache2/apache2.conf"
if [[ -f "$httpd_conf" && ! $(grep -q "^ServerName" "$httpd_conf") ]]; then
    echo "ServerName localhost" >> "$httpd_conf"
    echo "[+] Đã thêm ServerName localhost vào $httpd_conf"
elif [[ -f "$apache2_conf" && ! $(grep -q "^ServerName" "$apache2_conf") ]]; then
    echo "ServerName localhost" >> "$apache2_conf"
    echo "[+] Đã thêm ServerName localhost vào $apache2_conf"
fi

# Kiểm tra cấu hình trước khi restart
echo "[+] Kiểm tra lại cấu hình Apache..."
if apachectl configtest 2>/dev/null | grep -iq "Syntax OK"; then
    echo "[+] Cấu hình hợp lệ. Đang khởi động lại Apache..."
    systemctl restart httpd 2>/dev/null || systemctl restart apache2
    echo "[+] Apache khởi động lại thành công."
else
    echo "[!] Cấu hình Apache lỗi. Hủy khởi động lại."
    exit 1
fi

# Kiểm tra SSL
echo "[+] Kiểm tra SSL bằng openssl:"
echo | openssl s_client -connect "$domain:443" 2>/dev/null | openssl x509 -noout -subject -issuer
