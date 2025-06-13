#!/bin/bash

# === NHẬP DOMAIN TỪ NGƯỜI DÙNG ===
read -rp "[?] Nhập domain cần cập nhật SSL (VD: example.com): " domain
domain="${domain,,}"  # lowercase

if [[ -z "$domain" ]]; then
    echo "[!] Bạn chưa nhập domain!"
    exit 1
fi

# === XÁC ĐỊNH LOẠI OS ===
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
    ENABLE_SITE_CMD=":"  # no a2ensite
    RELOAD_CMD="systemctl restart httpd"
    APACHECTL="apachectl"
fi

# === CÀI mod_ssl NẾU CHƯA CÓ ===
echo "[+] Cài đặt mod_ssl..."
$INSTALL_CMD mod_ssl >/dev/null 2>&1 && echo "[+] mod_ssl đã được cài đặt hoặc đã có."

# === TÌM HOẶC TẠO FILE CẤU HÌNH CHO DOMAIN ===
conf_file=$(grep -ril "$domain" "$APACHE_CONF_DIR"/*.conf 2>/dev/null | head -n1)
document_root="/var/www/$domain"

if [[ -z "$conf_file" ]]; then
    conf_file="$APACHE_CONF_DIR/$domain.conf"
    echo "[+] Không tìm thấy file cấu hình cũ. Tạo mới: $conf_file"
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

    $ENABLE_SITE_CMD "$(basename "$conf_file")" 2>/dev/null || true
else
    echo "[+] Đã tìm thấy file cấu hình: $conf_file"
fi

# === LẤY ĐƯỜNG DẪN SSL HIỆN TẠI ===
crt_path=$(grep -i "SSLCertificateFile" "$conf_file" | awk '{print $2}' | head -n1)
key_path=$(grep -i "SSLCertificateKeyFile" "$conf_file" | awk '{print $2}' | head -n1)
ca_path=$(grep -i "SSLCertificateChainFile" "$conf_file" | awk '{print $2}' | head -n1)

echo "[+] Đường dẫn SSL đang dùng:"
echo "    - Certificate File     : $crt_path"
echo "    - Private Key File     : $key_path"
echo "    - CA Chain File (nếu có): $ca_path"

# === NHẬP THƯ MỤC SSL MỚI ===
read -rp "[?] Nhập thư mục chứa SSL mới (VD: $(dirname "$crt_path")): " new_dir
new_dir="${new_dir%/}"

# === XÁC ĐỊNH FILE MỚI ===
new_crt=$(find "$new_dir" -iname "$domain.crt" 2>/dev/null | head -n1)
new_key=$(find "$new_dir" -iname "$domain.key" 2>/dev/null | head -n1)
new_ca=$(find "$new_dir" -iname "$domain.ca*" -o -iname "*ca-bundle*" 2>/dev/null | head -n1)

# === BACKUP SSL CŨ ===
timestamp=$(date +%Y%m%d-%H%M%S)
mkdir -p /etc/ssl/backup
[[ -f "$crt_path" ]] && cp "$crt_path" "/etc/ssl/backup/$(basename "$crt_path").bak-$timestamp"
[[ -f "$key_path" ]] && cp "$key_path" "/etc/ssl/backup/$(basename "$key_path").bak-$timestamp"
[[ -f "$ca_path" ]] && cp "$ca_path" "/etc/ssl/backup/$(basename "$ca_path").bak-$timestamp"

# === CẬP NHẬT SSL MỚI ===

# Tạo file nếu chưa có
mkdir -p "$(dirname "$crt_path")" "$(dirname "$key_path")" "$(dirname "$ca_path")"

# Ghi CRT
if [[ -n "$new_crt" && -s "$new_crt" ]]; then
    if [[ -n "$new_ca" && -s "$new_ca" ]]; then
        cat "$new_crt" "$new_ca" > "$crt_path"
        echo "[+] Đã cập nhật CRT (fullchain)"
    else
        cp "$new_crt" "$crt_path"
        echo "[+] Đã cập nhật CRT"
    fi
else
    echo "[!] Thiếu file CRT mới."
fi

# Ghi KEY
if [[ -n "$new_key" && -s "$new_key" ]]; then
    cp "$new_key" "$key_path"
    echo "[+] Đã cập nhật KEY"
else
    echo "[!] Thiếu file KEY mới."
fi

# Ghi CA nếu có
if [[ -n "$ca_path" && -n "$new_ca" && -s "$new_ca" ]]; then
    cp "$new_ca" "$ca_path"
    echo "[+] Đã cập nhật CA"
fi

# === ĐẢM BẢO ServerName TRONG httpd.conf (với RHEL) ===
if [[ "$OS_TYPE" == "rhel" ]]; then
    httpd_conf="/etc/httpd/conf/httpd.conf"
    if ! grep -q "^ServerName" "$httpd_conf"; then
        echo "ServerName localhost" >> "$httpd_conf"
        echo "[+] Đã thêm ServerName localhost vào $httpd_conf"
    fi
fi

# === KIỂM TRA CẤU HÌNH & KHỞI ĐỘNG LẠI APACHE ===
echo "[+] Kiểm tra cấu hình Apache..."
if $APACHECTL configtest; then
    echo "[+] Cấu hình hợp lệ. Đang khởi động lại Apache..."
    $RELOAD_CMD && echo "[+] Apache khởi động lại thành công." || echo "[!] Apache lỗi!"
else
    echo "[!] Cấu hình Apache lỗi. Hủy reload!"
fi

# === KIỂM TRA SSL BẰNG openssl ===
echo "[+] Kiểm tra SSL bằng openssl:"
echo | openssl s_client -connect "$domain:443" 2>/dev/null | openssl x509 -noout -subject -issuer
