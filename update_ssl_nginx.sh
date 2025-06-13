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

# Xác định thư mục cấu hình
if [[ -d /etc/nginx/sites-available ]]; then
    conf_dir="/etc/nginx/sites-available"
    enabled_dir="/etc/nginx/sites-enabled"
    conf_file="$conf_dir/$domain.conf"
    redirect_file="$conf_dir/${domain}_redirect.conf"
    ln -sf "$conf_file" "$enabled_dir/" || true
    ln -sf "$redirect_file" "$enabled_dir/" || true
    # Xóa nếu tồn tại ở conf.d
    rm -f "/etc/nginx/conf.d/$domain.conf" "/etc/nginx/conf.d/${domain}_redirect.conf"
else
    conf_dir="/etc/nginx/conf.d"
    conf_file="$conf_dir/$domain.conf"
    redirect_file="$conf_dir/${domain}_redirect.conf"
fi

mkdir -p "$conf_dir"

# Tạo file chính nếu chưa có
if [[ ! -f "$conf_file" ]]; then
    echo "[+] Tạo file cấu hình chính: $conf_file"
    mkdir -p "/var/www/$domain"
    cat > "$conf_file" <<EOF
server {
    listen 443 ssl;
    server_name $domain;

    ssl_certificate /etc/ssl/certs/$domain.crt;
    ssl_certificate_key /etc/ssl/private/$domain.key;
    ssl_trusted_certificate /etc/ssl/certs/$domain.ca-bundle;

    root /var/www/$domain;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
else
    echo "[+] File cấu hình chính đã tồn tại: $conf_file"
fi

# Tạo file redirect nếu chưa có
if [[ ! -f "$redirect_file" ]]; then
    echo "[+] Tạo file redirect HTTP -> HTTPS: $redirect_file"
    cat > "$redirect_file" <<EOF
server {
    listen 80;
    server_name $domain;

    return 301 https://\$host\$request_uri;
}
EOF
else
    echo "[+] File redirect đã tồn tại: $redirect_file"
fi

# Kiểm tra đường dẫn file SSL hiện tại
crt_path=$(grep -i "ssl_certificate " "$conf_file" | awk '{print $2}' | tr -d ";")
key_path=$(grep -i "ssl_certificate_key " "$conf_file" | awk '{print $2}' | tr -d ";")
ca_path=$(grep -i "ssl_trusted_certificate " "$conf_file" | awk '{print $2}' | tr -d ";")

echo "[+] Đường dẫn SSL hiện tại:\n    CRT: $crt_path\n    KEY: $key_path\n    CA : $ca_path"

read -rp "[?] Nhập đường dẫn chứa SSL mới (default: /etc/ssl/certs): " new_ssl_dir
new_ssl_dir="${new_ssl_dir:-/etc/ssl/certs}"
new_ssl_dir="${new_ssl_dir%/}"

new_crt=$(find "$new_ssl_dir" -iname "$domain.crt" | head -n1)
new_key=$(find "$new_ssl_dir" -iname "$domain.key" | head -n1)
new_ca=$(find "$new_ssl_dir" -iname "$domain.ca*" -o -iname "*ca-bundle*" | head -n1)

if [[ -s "$new_crt" && -s "$new_key" ]]; then
    openssl x509 -noout -modulus -in "$new_crt" > /tmp/crt.mod
    openssl rsa -noout -modulus -in "$new_key" > /tmp/key.mod
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

# Backup nếu cần
timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="/etc/ssl/backup/${domain}-$timestamp"
mkdir -p "$backup_dir"
[[ -f "$crt_path" ]] && cp "$crt_path" "$backup_dir/"
[[ -f "$key_path" ]] && cp "$key_path" "$backup_dir/"
[[ -f "$ca_path" ]] && cp "$ca_path" "$backup_dir/"
echo "[+] Đã backup SSL cũ tại: $backup_dir"

# Cập nhật file SSL
mkdir -p "$(dirname "$crt_path")" "$(dirname "$key_path")"
if [[ -n "$new_ca" ]]; then
    cat "$new_crt" "$new_ca" > "$crt_path"
else
    cp "$new_crt" "$crt_path"
fi
cp "$new_key" "$key_path"
[[ -n "$new_ca" && -n "$ca_path" ]] && cp "$new_ca" "$ca_path"

echo "[+] Đã cập nhật SSL"

# Reload nginx nếu config hợp lệ
if nginx -t; then
    echo "[+] Reload Nginx..."
    systemctl reload nginx
    echo "[+] Thành công."
else
    echo "[!] Lỗi cấu hình Nginx. Không reload."
fi

# Kiểm tra SSL bằng curl
sleep 1
echo "[+] Kiểm tra SSL qua curl"
curl -vkI --resolve "$domain:443:127.0.0.1" "https://$domain" 2>&1 | grep -Ei 'subject:|issuer:|expire date|SSL certificate|Server:|HTTP/'
