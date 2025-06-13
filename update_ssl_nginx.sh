#!/bin/bash

set -e

echo "[!] Vui lòng tắt Unikey hoặc bộ gõ tiếng Việt trước khi nhập!"
sleep 1

read -rp "[?] Nhập domain cần cập nhật SSL: " domain
domain="${domain,,}"
if [[ -z "$domain" ]]; then
    echo "[!] Domain không hợp lệ."
    exit 1
fi

echo "[+] Tìm file cấu hình Nginx chứa domain $domain..."
conf_file=$(grep -ril "$domain" /etc/nginx/sites-available/*.conf /etc/nginx/conf.d/*.conf 2>/dev/null | head -n1)

if [[ -z "$conf_file" ]]; then
    conf_file="/etc/nginx/sites-available/$domain.conf"
    echo "[+] Không tìm thấy. Tạo mới file: $conf_file"
    mkdir -p "$(dirname "$conf_file")"
    cat > "$conf_file" <<EOF
server {
    listen 443 ssl;
    server_name $domain;

    ssl_certificate     /etc/ssl/certs/$domain.crt;
    ssl_certificate_key /etc/ssl/private/$domain.key;

    root /var/www/$domain;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}

server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}
EOF

    ln -s "$conf_file" /etc/nginx/sites-enabled/ 2>/dev/null || true
else
    echo "[+] Đang dùng file cấu hình: $conf_file"
fi

crt_path=$(grep ssl_certificate "$conf_file" | grep -v '_key' | awk '{print $2}' | tr -d ';')
key_path=$(grep ssl_certificate_key "$conf_file" | awk '{print $2}' | tr -d ';')

echo "[+] Đường dẫn SSL hiện tại:"
echo "    CRT: $crt_path"
echo "    KEY: $key_path"

default_ssl_dir="/etc/ssl/certs"
read -rp "[?] Nhập đường dẫn thư mục chứa file SSL mới (default: $default_ssl_dir): " new_ssl_dir
new_ssl_dir="${new_ssl_dir:-$default_ssl_dir}"
new_ssl_dir="${new_ssl_dir%/}"

echo "[+] Danh sách file SSL trong $new_ssl_dir:"
ls -1 "$new_ssl_dir" | grep -i "$domain" || echo "    (Không tìm thấy file nào liên quan đến $domain)"

new_crt=$(find "$new_ssl_dir" -iname "$domain.crt" 2>/dev/null | head -n1)
new_key=$(find "$new_ssl_dir" -iname "$domain.key" 2>/dev/null | head -n1)

echo "[+] Kiểm tra CRT/KEY mới..."
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
    echo "[!] Thiếu hoặc rỗng file CRT/KEY."
    exit 1
fi

timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="/etc/ssl/backup/${domain}-$timestamp"
mkdir -p "$backup_dir"
[[ -f "$crt_path" ]] && cp "$crt_path" "$backup_dir/"
[[ -f "$key_path" ]] && cp "$key_path" "$backup_dir/"
echo "[+] Đã backup SSL cũ vào: $backup_dir"

mkdir -p "$(dirname "$crt_path")" "$(dirname "$key_path")"
cp "$new_crt" "$crt_path"
cp "$new_key" "$key_path"

echo "[+] Đã cập nhật SSL. Kiểm tra cấu hình Nginx..."
if nginx -t; then
    echo "[+] Cấu hình hợp lệ. Restart Nginx..."
    systemctl restart nginx
    echo "[+] Nginx khởi động lại thành công."
else
    echo "[!] Lỗi cấu hình Nginx. Không restart."
fi

echo "[+] Kiểm tra SSL với curl:"
curl -vI --resolve "$domain:443:127.0.0.1" "https://$domain" 2>&1 | grep -Ei 'subject:|issuer:|expire date|SSL certificate|Server:|HTTP/'
