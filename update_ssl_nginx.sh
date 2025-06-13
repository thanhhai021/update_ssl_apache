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

echo "[+] Cài đặt nginx nếu chưa có..."
if ! command -v nginx &>/dev/null; then
    if command -v yum &>/dev/null; then
        yum install -y nginx &>/dev/null || true
    elif command -v apt &>/dev/null; then
        apt update -y &>/dev/null && apt install -y nginx &>/dev/null || true
    fi
fi

conf_file=$(grep -ril "$domain" /etc/nginx/sites-available/*.conf /etc/nginx/conf.d/*.conf 2>/dev/null | head -n1)
if [[ -z "$conf_file" ]]; then
    conf_file="/etc/nginx/conf.d/$domain.conf"
    [[ -d /etc/nginx/sites-available ]] && conf_file="/etc/nginx/sites-available/$domain.conf"
    echo "[+] Không tìm thấy cấu hình. Tạo mới: $conf_file"
    mkdir -p "$(dirname "$conf_file")"
    cat > "$conf_file" <<EOF
server {
    listen 443 ssl;
    server_name $domain;

    ssl_certificate     /etc/ssl/certs/$domain.crt;
    ssl_certificate_key /etc/ssl/private/$domain.key;
    ssl_trusted_certificate /etc/ssl/certs/$domain.ca-bundle;

    root /var/www/$domain;
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF

    redirect_conf="/etc/nginx/conf.d/${domain}_redirect.conf"
    cat > "$redirect_conf" <<EOF
server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}
EOF
    echo "[+] Đã tạo redirect HTTP → HTTPS: $redirect_conf"
else
    echo "[+] Đang dùng file cấu hình: $conf_file"
fi

crt_path=$(grep -i "ssl_certificate " "$conf_file" | awk '{print $2}' | tr -d ';' | head -n1)
key_path=$(grep -i "ssl_certificate_key" "$conf_file" | awk '{print $2}' | tr -d ';' | head -n1)
ca_path=$(grep -i "ssl_trusted_certificate" "$conf_file" | awk '{print $2}' | tr -d ';' | head -n1)

echo "[+] Đường dẫn SSL hiện tại:"
echo "    CRT: $crt_path"
echo "    KEY: $key_path"
echo "    CA : $ca_path"

default_ssl_dir="/etc/ssl/certs"
read -rp "[?] Nhập thư mục chứa file SSL mới (default: $default_ssl_dir): " new_ssl_dir
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

echo "[+] Kiểm tra lại cấu hình Nginx..."
if nginx -t 2>&1 | tee /tmp/nginx_test | grep -qi "successful"; then
    echo "[+] Cấu hình hợp lệ. Đang reload Nginx..."
    systemctl reload nginx
    echo "[+] Nginx reload thành công."
else
    echo "[!] Cấu hình Nginx lỗi. Hủy reload."
fi

echo "[+] Kiểm tra SSL bằng openssl:"
echo | openssl s_client -connect "$domain:443" 2>/dev/null | openssl x509 -noout -subject -issuer
echo "[+] Kiểm tra SSL bằng curl:"
curl -vI --resolve "$domain:443:127.0.0.1" "https://$domain" 2>&1 | grep -Ei 'subject:|issuer:|expire date|SSL certificate|Server:|HTTP/'
