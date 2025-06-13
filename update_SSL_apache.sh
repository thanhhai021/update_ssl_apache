#!/bin/bash

# Tắt gõ tiếng Việt bằng cách cảnh báo người dùng
echo "[!] Vui lòng tắt gõ tiếng Việt khi nhập đường dẫn hoặc domain để tránh lỗi cú pháp."

# Nhập domain
read -rp "[?] Nhập domain cần cập nhật SSL: " domain
domain="${domain,,}"  # chuyển về chữ thường
if [[ -z "$domain" ]]; then
    echo "[!] Domain không được để trống!"
    exit 1
fi

# Cài mod_ssl nếu chưa có
if ! apachectl -M 2>/dev/null | grep -q ssl_module; then
    echo "[+] Cài đặt mod_ssl..."
    if command -v dnf &>/dev/null; then
        dnf install -y mod_ssl
    elif command -v yum &>/dev/null; then
        yum install -y mod_ssl
    elif command -v apt &>/dev/null; then
        apt update && apt install -y ssl-cert libapache2-mod-ssl || a2enmod ssl
    fi
fi

# Tìm file config chứa domain
echo "[+] Tìm file cấu hình Apache chứa domain $domain..."
conf_file=$(grep -ril "$domain" /etc/httpd/conf.d/*.conf /etc/apache2/sites-available/*.conf 2>/dev/null | head -n1)

if [[ -z "$conf_file" ]]; then
    conf_file="/etc/httpd/conf.d/$domain.conf"
    [[ ! -d /etc/httpd/conf.d ]] && conf_file="/etc/apache2/sites-available/$domain.conf"
    echo "[+] Tạo file cấu hình Apache: $conf_file"
    cat <<EOF > "$conf_file"
<VirtualHost *:443>
    ServerName $domain
    DocumentRoot /var/www/html
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/$domain.crt
    SSLCertificateKeyFile /etc/ssl/private/$domain.key
    SSLCertificateChainFile /etc/ssl/certs/$domain.ca-bundle
</VirtualHost>
EOF
fi

echo "[+] Đang dùng file cấu hình: $conf_file"

# Lấy các đường dẫn SSL hiện tại
crt_path=$(grep -i "SSLCertificateFile" "$conf_file" | awk '{print $2}' | head -n1)
key_path=$(grep -i "SSLCertificateKeyFile" "$conf_file" | awk '{print $2}' | head -n1)
ca_path=$(grep -i "SSLCertificateChainFile" "$conf_file" | awk '{print $2}' | head -n1)

echo "[+] Đường dẫn SSL hiện tại:"
echo "    CRT: $crt_path"
echo "    KEY: $key_path"
echo "    CA : $ca_path"

# Nhập đường dẫn thư mục SSL mới
read -rp "[?] Nhập đường dẫn thư mục chứa file SSL mới (default: /etc/ssl/certs): " new_dir
new_dir="${new_dir:-/etc/ssl/certs}"
new_dir="${new_dir%/}"

echo "[+] Danh sách file SSL trong $new_dir:"
ls -lh "$new_dir" | grep -Ei "\.(crt|key|pem|bundle)"

# Xác định file mới
new_crt=$(find "$new_dir" -iname "$domain.crt" 2>/dev/null | head -n1)
new_key=$(find "$new_dir" -iname "$domain.key" 2>/dev/null | head -n1)
new_ca=$(find "$new_dir" -iname "$domain.ca*" -o -iname "*ca-bundle*" 2>/dev/null | head -n1)

# Kiểm tra chuỗi chứng chỉ mới
echo "[+] Kiểm tra chuỗi chứng chỉ mới..."
if openssl x509 -noout -modulus -in "$new_crt" 2>/dev/null | grep -q "$(openssl rsa -noout -modulus -in "$new_key" 2>/dev/null | cut -d'=' -f2)"; then
    echo "[+] CRT và KEY hợp lệ."
else
    echo "[!] CRT và KEY không khớp. Thoát."
    exit 1
fi

# Backup cũ
timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="/etc/ssl/backup/${domain}-$timestamp"
mkdir -p "$backup_dir"
[[ -f "$crt_path" ]] && cp "$crt_path" "$backup_dir/"
[[ -f "$key_path" ]] && cp "$key_path" "$backup_dir/"
[[ -f "$ca_path" ]] && cp "$ca_path" "$backup_dir/"
echo "[+] Đã backup SSL cũ vào: $backup_dir"

# Tạo thư mục nếu chưa có
mkdir -p "$(dirname "$crt_path")" "$(dirname "$key_path")" "$(dirname "$ca_path")"

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
    echo "[!] Thiếu file CRT mới!"
fi

# Ghi KEY
if [[ -n "$new_key" && -s "$new_key" ]]; then
    cp "$new_key" "$key_path"
    echo "[+] Đã cập nhật KEY"
else
    echo "[!] Thiếu file KEY mới!"
fi

# Ghi CA
if [[ -n "$new_ca" && -s "$new_ca" ]]; then
    cp "$new_ca" "$ca_path"
    echo "[+] Đã cập nhật CA"
fi

# Đảm bảo có ServerName
apache_main_conf="/etc/httpd/conf/httpd.conf"
[[ ! -f "$apache_main_conf" ]] && apache_main_conf="/etc/apache2/apache2.conf"
if ! grep -q "^ServerName" "$apache_main_conf"; then
    echo "ServerName localhost" >> "$apache_main_conf"
    echo "[+] Đã thêm ServerName localhost vào $apache_main_conf"
fi

# Kiểm tra cấu hình Apache
echo "[+] Kiểm tra lại cấu hình Apache..."
if command -v apache2ctl &>/dev/null; then
    apache2ctl configtest
    result=$?
elif command -v apachectl &>/dev/null; then
    apachectl configtest
    result=$?
else
    echo "[!] Không tìm thấy lệnh kiểm tra Apache!"
    exit 1
fi

# Nếu OK thì restart
if [[ "$result" -eq 0 ]]; then
    echo "[+] Cấu hình hợp lệ. Đang khởi động lại Apache..."
    systemctl restart apache2 2>/dev/null || systemctl restart httpd
    echo "[+] Apache khởi động lại thành công."
else
    echo "[!] Cấu hình Apache lỗi. Hủy khởi động lại."
fi

# Kiểm tra SSL cuối cùng
echo "[+] Kiểm tra SSL bằng openssl:"
echo | openssl s_client -connect "$domain:443" 2>/dev/null | openssl x509 -noout -subject -issuer
