#!/bin/bash

set -e

echo "[!] Vui lòng tắt Unikey hoặc bộ gõ tiếng Việt trước khi nhập đường dẫn!"
sleep 2

read -rp "[?] Nhập domain cần cập nhật SSL: " domain
domain="${domain,,}"
if [[ -z "$domain" ]]; then
    echo "[!] Domain không hợp lệ."
    exit 1
fi

echo "[+] Cài đặt mod_ssl..."
if command -v yum &>/dev/null; then
    yum install -y mod_ssl &>/dev/null || true
elif command -v apt &>/dev/null; then
    apt update -y &>/dev/null && apt install -y libapache2-mod-ssl &>/dev/null || true
    a2enmod ssl &>/dev/null || true
    a2enmod rewrite &>/dev/null || true
fi

echo "[+] Tìm file cấu hình Apache chứa domain $domain..."
conf_file=$(grep -ril "$domain" /etc/httpd/conf.d/*.conf /etc/apache2/sites-available/*.conf 2>/dev/null | head -n1)

if [[ -z "$conf_file" ]]; then
    conf_file="/etc/httpd/conf.d/$domain.conf"
    [[ -d /etc/apache2/sites-available ]] && conf_file="/etc/apache2/sites-available/$domain.conf"
    echo "[+] Không tìm thấy. Tạo file cấu hình mới: $conf_file"
    mkdir -p "$(dirname "$conf_file")"
    cat > "$conf_file" <<EOF
<VirtualHost *:443>
    ServerName $domain
    DocumentRoot /var/www/$domain
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/$domain.crt
    SSLCertificateKeyFile /etc/ssl/private/$domain.key
    SSLCertificateChainFile /etc/ssl/certs/$domain.ca-bundle

    <Directory /var/www/$domain>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF

    # Tạo file redirect HTTP → HTTPS
    redirect_conf="${conf_file%.*}_redirect.conf"
    cat > "$redirect_conf" <<EOF
<VirtualHost *:80>
    ServerName $domain
    RewriteEngine On
    RewriteRule ^/(.*)$ https://$domain/\$1 [R=301,L]
</VirtualHost>
EOF

    echo "[+] Đã tạo file redirect HTTP -> HTTPS: $redirect_conf"
    if [[ -x "$(command -v a2ensite)" ]]; then
        a2ensite "$(basename "$redirect_conf")" &>/dev/null || true
    fi
else
    echo "[+] Đang dùng file cấu hình: $conf_file"
fi

crt_path=$(grep -i "SSLCertificateFile" "$conf_file" | awk '{print $2}' | head -n1)
key_path=$(grep -i "SSLCertificateKeyFile" "$conf_file" | awk '{print $2}' | head -n1)
ca_path=$(grep -i "SSLCertificateChainFile" "$conf_file" | awk '{print $2}' | head -n1)

echo "[+] Đường dẫn SSL hiện tại:"
echo "    CRT: $crt_path"
echo "    KEY: $key_path"
echo "    CA : $ca_path"

default_ssl_dir="/etc/ssl/certs"
read -rp "[?] Nhập đường dẫn thư mục chứa file SSL mới (default: $default_ssl_dir): " new_ssl_dir
new_ssl_dir="${new_ssl_dir:-$default_ssl_dir}"
new_ssl_dir="${new_ssl_dir%/}"

echo "[+] Danh sách file SSL trong $new_ssl_dir:"
ls -1 "$new_ssl_dir" | grep -i "$domain" || echo "    (Không tìm thấy file nào liên quan đến $domain)"

new_crt=$(find "$new_ssl_dir" -iname "$domain.crt" 2>/dev/null | head -n1)
new_key=$(find "$new_ssl_dir" -iname "$domain.key" 2>/dev/null | head -n1)
new_ca=$(find "$new_ssl_dir" -iname "$domain.ca*" -o -iname "*ca-bundle*" 2>/dev/null | head -n1)

echo "[+] Kiểm tra chuỗi chứng chỉ mới..."
if [[ -s "$new_crt" && -s "$new_key" ]]; then
    openssl x509 -noout -modulus -in "$new_crt" > /tmp/crt.mod 2>/dev/null
    openssl rsa -noout -modulus -in "$new_key" > /tmp/key.mod 2>/dev/null
    if cmp -s /tmp/crt.mod /tmp/key.mod; then
        echo "[+] CRT và KEY hợp lệ."
    else
        echo "[!] CRT và KEY không khớp!"
        exit 1
    fi
    rm -f /tmp/*.mod
else
    echo "[!] File CRT hoặc KEY không tồn tại hoặc rỗng."
    exit 1
fi

timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="/etc/ssl/backup/${domain}-$timestamp"
mkdir -p "$backup_dir"
[[ -f "$crt_path" ]] && cp "$crt_path" "$backup_dir/"
[[ -f "$key_path" ]] && cp "$key_path" "$backup_dir/"
[[ -f "$ca_path" ]] && cp "$ca_path" "$backup_dir/"
echo "[+] Đã backup SSL cũ vào: $backup_dir"

mkdir -p "$(dirname "$crt_path")" "$(dirname "$key_path")"
if [[ -n "$new_ca" ]]; then
    echo "[+] Gộp CRT và CA vào fullchain..."
    cat "$new_crt" "$new_ca" > "$crt_path"
else
    cp "$new_crt" "$crt_path"
fi
cp "$new_key" "$key_path"
[[ -n "$ca_path" && -n "$new_ca" ]] && cp "$new_ca" "$ca_path"

echo "[+] Đã cập nhật CRT"
echo "[+] Đã cập nhật KEY"
[[ -n "$new_ca" ]] && echo "[+] Đã cập nhật CA"

apache_main_conf="/etc/httpd/conf/httpd.conf"
[[ -f /etc/apache2/apache2.conf ]] && apache_main_conf="/etc/apache2/apache2.conf"
if ! grep -q "^ServerName" "$apache_main_conf"; then
    echo "ServerName localhost" >> "$apache_main_conf"
    echo "[+] Đã thêm ServerName localhost vào $apache_main_conf"
fi

echo "[+] Kiểm tra lại cấu hình Apache..."
if apachectl configtest 2>&1 | tee /tmp/apache_test | grep -qi "Syntax OK"; then
    echo "[+] Cấu hình hợp lệ. Đang khởi động lại Apache..."
    systemctl restart apache2 2>/dev/null || systemctl restart httpd
    echo "[+] Apache khởi động lại thành công."
else
    echo "[!] Cấu hình Apache lỗi. Hủy khởi động lại."
fi

echo "[+] Kiểm tra SSL bằng openssl:"
echo | openssl s_client -connect "$domain:443" 2>/dev/null | openssl x509 -noout -subject -issuer
