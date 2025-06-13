#!/bin/bash

domain="$1"
if [[ -z "$domain" ]]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

conf_dir="/etc/httpd/conf.d"
conf_file="$conf_dir/$domain.conf"
document_root="/var/www/$domain"

# Cài mod_ssl nếu cần
if ! apachectl -M | grep -q ssl_module; then
    echo "[+] Cài đặt mod_ssl..."
    dnf install -y mod_ssl || yum install -y mod_ssl || apt install -y libapache2-mod-ssl
fi

# Tạo file cấu hình nếu chưa có
if [[ ! -f "$conf_file" ]]; then
    echo "[+] Tạo file cấu hình Apache: $conf_file"
    mkdir -p "$document_root"
    echo "<h1>Hello from $domain</h1>" > "$document_root/index.html"

    cat > "$conf_file" <<EOF
<VirtualHost *:80>
    ServerName $domain
    DocumentRoot $document_root

    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^/(.*)$ https://$domain/\$1 [R=301,L]

    <Directory "$document_root">
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:443>
    ServerName $domain
    DocumentRoot $document_root

    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/$domain.crt
    SSLCertificateKeyFile /etc/ssl/private/$domain.key
    SSLCertificateChainFile /etc/ssl/certs/$domain.ca-bundle

    <Directory "$document_root">
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
EOF
else
    echo "[+] Đã tồn tại file cấu hình: $conf_file"
fi

# Tìm đường dẫn file SSL
crt_path=$(grep -i "SSLCertificateFile" "$conf_file" | awk '{print $2}')
key_path=$(grep -i "SSLCertificateKeyFile" "$conf_file" | awk '{print $2}')
ca_path=$(grep -i "SSLCertificateChainFile" "$conf_file" | awk '{print $2}')

# Tạo thư mục và file nếu cần
mkdir -p "$(dirname "$crt_path")" "$(dirname "$key_path")" "$(dirname "$ca_path")"
touch "$crt_path" "$key_path" "$ca_path"

# Backup SSL cũ
timestamp=$(date +%Y%m%d-%H%M%S)
mkdir -p /etc/ssl/backup
[[ -f "$crt_path" ]] && cp "$crt_path" "/etc/ssl/backup/$(basename "$crt_path").bak-$timestamp"
[[ -f "$key_path" ]] && cp "$key_path" "/etc/ssl/backup/$(basename "$key_path").bak-$timestamp"

# Nhập thư mục chứa SSL mới
read -rp "[?] Nhập thư mục chứa SSL mới (VD: /etc/ssl/new): " new_dir
new_dir="${new_dir%/}"

new_crt=$(find "$new_dir" -iname "$domain.crt" 2>/dev/null | head -n1)
new_key=$(find "$new_dir" -iname "$domain.key" 2>/dev/null | head -n1)
new_ca=$(find "$new_dir" -iname "$domain.ca*" -o -iname "*ca-bundle*" 2>/dev/null | head -n1)

# Cập nhật nội dung file SSL
if [[ -n "$new_crt" && -s "$new_crt" ]]; then
    if [[ -n "$new_ca" && -s "$new_ca" ]]; then
        cat "$new_crt" "$new_ca" > "$crt_path"
    else
        cat "$new_crt" > "$crt_path"
    fi
    echo "[+] Đã cập nhật CRT"
else
    echo "[!] Không tìm thấy CRT mới"
fi

if [[ -n "$new_key" && -s "$new_key" ]]; then
    cat "$new_key" > "$key_path"
    echo "[+] Đã cập nhật KEY"
else
    echo "[!] Không tìm thấy KEY mới"
fi

if [[ -n "$new_ca" && -s "$new_ca" ]]; then
    cat "$new_ca" > "$ca_path"
    echo "[+] Đã cập nhật CA"
else
    echo "[!] Không tìm thấy CA-BUNDLE mới"
fi

chmod 600 "$crt_path" "$key_path" "$ca_path"
chown root:root "$crt_path" "$key_path" "$ca_path"

# Đảm bảo có ServerName trong httpd.conf
httpd_conf="/etc/httpd/conf/httpd.conf"
if ! grep -q "^ServerName" "$httpd_conf"; then
    echo "ServerName localhost" >> "$httpd_conf"
    echo "[+] Đã thêm ServerName localhost vào $httpd_conf"
fi

# Kiểm tra và khởi động lại Apache
echo "[+] Kiểm tra cấu hình Apache..."
if apachectl configtest; then
    echo "[+] Cấu hình hợp lệ. Đang khởi động lại Apache..."
    systemctl restart httpd && echo "[+] Apache khởi động lại thành công." || echo "[!] Apache lỗi khi restart!"
else
    echo "[!] Cấu hình Apache lỗi. Không restart."
fi

# Kiểm tra SSL thực tế
echo "[+] Kiểm tra SSL bằng openssl:"
echo | openssl s_client -connect "$domain:443" 2>/dev/null | openssl x509 -noout -subject -issuer
