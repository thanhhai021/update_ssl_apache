#!/bin/bash

domain="$1"
if [[ -z "$domain" ]]; then
    echo "Usage: $0 <domain>"
    exit 1
fi

# Phát hiện OS và thiết lập biến tương ứng
if [[ -f /etc/debian_version ]]; then
    OS_TYPE="debian"
    INSTALL_CMD="apt-get install -y"
    APACHE_SERVICE="apache2"
    APACHE_CONF_DIR="/etc/apache2/sites-available"
    ENABLE_SITE_CMD="a2ensite"
    RELOAD_CMD="systemctl reload apache2"
    APACHECTL="apache2ctl"
else
    OS_TYPE="rhel"
    INSTALL_CMD="dnf install -y || yum install -y"
    APACHE_SERVICE="httpd"
    APACHE_CONF_DIR="/etc/httpd/conf.d"
    ENABLE_SITE_CMD=":"  # Không dùng a2ensite
    RELOAD_CMD="systemctl restart httpd"
    APACHECTL="apachectl"
fi

conf_file="$APACHE_CONF_DIR/$domain.conf"
document_root="/var/www/$domain"

# Cài mod_ssl nếu chưa có
if ! $APACHECTL -M | grep -q ssl_module; then
    echo "[+] Cài đặt mod_ssl..."
    if [[ "$OS_TYPE" == "debian" ]]; then
        $INSTALL_CMD libapache2-mod-ssl
        a2enmod ssl
    else
        $INSTALL_CMD mod_ssl
    fi
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

    # Debian-based needs a2ensite
    $ENABLE_SITE_CMD "$domain.conf" 2>/dev/null || true
fi

# Đường dẫn file SSL
crt_path="/etc/ssl/certs/$domain.crt"
key_path="/etc/ssl/private/$domain.key"
ca_path="/etc/ssl/certs/$domain.ca-bundle"

# Tạo thư mục nếu chưa có
mkdir -p "$(dirname "$crt_path")" "$(dirname "$key_path")"

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
[[ -n "$new_crt" && -s "$new_crt" ]] && cat "$new_crt" > "$crt_path" && echo "[+] Cập nhật CRT xong"
[[ -n "$new_key" && -s "$new_key" ]] && cat "$new_key" > "$key_path" && echo "[+] Cập nhật KEY xong"
[[ -n "$new_ca" && -s "$new_ca" ]] && cat "$new_ca" > "$ca_path" && echo "[+] Cập nhật CA xong"

chmod 600 "$crt_path" "$key_path" "$ca_path"
chown root:root "$crt_path" "$key_path" "$ca_path"

# Đảm bảo có ServerName trong file chính
main_conf="/etc/${APACHE_SERVICE}/conf/httpd.conf"
[[ "$OS_TYPE" == "debian" ]] && main_conf="/etc/apache2/apache2.conf"
if ! grep -q "^ServerName" "$main_conf"; then
    echo "ServerName localhost" >> "$main_conf"
    echo "[+] Đã thêm ServerName localhost vào $main_conf"
fi

# Kiểm tra cấu hình
echo "[+] Kiểm tra cấu hình Apache..."
if $APACHECTL configtest; then
    echo "[+] Cấu hình hợp lệ. Khởi động lại Apache..."
    $RELOAD_CMD && echo "[+] Apache restart thành công." || echo "[!] Apache lỗi khi restart."
else
    echo "[!] Cấu hình lỗi. Không khởi động lại."
fi

# Kiểm tra SSL
echo "[+] Kiểm tra SSL:"
echo | openssl s_client -connect "$domain:443" 2>/dev/null | openssl x509 -noout -subject -issuer
