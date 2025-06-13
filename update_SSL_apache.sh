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
ca_path=$(grep -i "S_
