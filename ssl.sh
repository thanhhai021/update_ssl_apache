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

echo "[+] Đang tìm file cấu hình Nginx chứa domain $domain..."
conf_file=$(grep -ril "$domain" /etc/nginx/sites-available/*.conf /etc/nginx/conf.d/*.conf 2>/dev/null | head -n1)

if [[ -z "$conf_file" ]]; then
    conf_file="/etc/nginx/conf.d/$domain.conf"
    echo "[+] Không tìm thấy. Tạo file cấu hình mới: $conf_file"
    mkdir -p "$(dirname "$conf_file")"
    cat > "$conf_file" <<EOF
server {
    listen 443 ssl;
    server_name $domain;

    ssl_certificate     /etc/ssl/certs/$domain.crt;
    ssl_certificate_key /etc/ssl/private/$domain.key;
    ssl_trusted_certificate /etc/ssl/certs/$domain.ca-bundle;

    root /var/www/$domain;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
else
    echo "[+] Đang dùng file cấu hình: $conf_file"
    has443=$(grep -E "listen +443" "$conf_file" || true)
    has80=$(grep -E "listen +80" "$conf_file" || true)
    if [[ -z "$has443" ]]; then
        echo "[+] Thêm block HTTPS vào $conf_file"
        cat >> "$conf_file" <<EOF

server {
    listen 443 ssl;
    server_name $domain;

    ssl_certificate     /etc/ssl/certs/$domain.crt;
    ssl_certificate_key /etc/ssl/private/$domain.key;
    ssl_trusted_certificate /etc/ssl/certs/$domain.ca-bundle;

    root /var/www/$domain;
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
    fi
    if [[ -z "$has80" ]]; then
        echo "[+] Thêm block HTTP chuyển hướng HTTPS vào $conf_file"
        cat >> "$conf_file" <<EOF

server {
    listen 80;
    server_name $domain;
    return 301 https://\$host\$request_uri;
}
EOF
    fi
fi

crt_path=$(grep -i "ssl_certificate " "$conf_file" | grep -v trusted | awk '{print $2}' | tr -d ';' | head -n1)
key_path=$(grep -i "ssl_certificate_key" "$conf_file" | awk '{print $2}' | tr -d ';' | head -n1)
ca_path=$(grep -i "ssl_trusted_certificate" "$conf_file" | awk '{print $2}' | tr -d ';' | head -n1)

echo "[+] Đường dẫn SSL hiện tại trong config:"
echo "    CRT: $crt_path"
echo "    KEY: $key_path"
echo "    CA : $ca_path"

read -rp "[?] Nhập đường dẫn thư mục chứa file SSL mới: " new_ssl_dir
new_ssl_dir="${new_ssl_dir%/}"

echo "[+] File SSL trong thư mục gồm:"
find "$new_ssl_dir" -type f \( -iname "*${domain}*" -o -iname "*.crt" -o -iname "*.cer" -o -iname "*.pem" -o -iname "*.key" -o -iname "*ca*" \) -ls

new_crt=$(find "$new_ssl_dir" -type f -iname "*${domain}*.crt" -o -iname "*${domain}*.pem" -o -iname "*.crt" -o -iname "*.pem" 2>/dev/null | head -n1)
new_key=$(find "$new_ssl_dir" -type f -iname "*${domain}*.key" -o -iname "*.key" 2>/dev/null | head -n1)
new_ca=$(find "$new_ssl_dir" -type f \( -iname "*ca-bundle*" -o -iname "*ca*" \) 2>/dev/null | head -n1)

if [[ -s "$new_crt" && -s "$new_key" ]]; then
    echo "[+] Kiểm tra CRT và KEY mới..."
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
    echo "[!] Không tìm thấy hoặc file CRT/KEY rỗng."
    exit 1
fi

timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="/etc/ssl/backup/${domain}-$timestamp"
mkdir -p "$backup_dir"
[[ -f "$crt_path" ]] && cp "$crt_path" "$backup_dir/"
[[ -f "$key_path" ]] && cp "$key_path" "$backup_dir/"
[[ -f "$ca_path" ]] && cp "$ca_path" "$backup_dir/"
echo "[+] Đã backup SSL cũ vào: $backup_dir"
echo "    Gồm: $(ls -1 "$backup_dir")"

mkdir -p "$(dirname "$crt_path")" "$(dirname "$key_path")"

if [[ -n "$new_ca" ]]; then
    echo "[+] Gộp CRT và CA nếu cần thiết..."
    cat "$new_crt" "$new_ca" > "$crt_path"
else
    cp "$new_crt" "$crt_path"
fi
cp "$new_key" "$key_path"
[[ -n "$ca_path" && -n "$new_ca" ]] && cp "$new_ca" "$ca_path"

echo "[+] Đã cập nhật CRT: $crt_path"
echo "[+] Đã cập nhật KEY: $key_path"
[[ -n "$new_ca" ]] && echo "[+] Đã cập nhật CA : $ca_path"

echo "[+] Kiểm tra cấu hình Nginx..."
if nginx -t 2>&1 | tee /tmp/nginx_test | grep -q 'successful'; then
    echo "[+] Cấu hình hợp lệ. Đang khởi động lại Nginx..."
    systemctl restart nginx
    echo "[+] Nginx khởi động lại thành công."
else
    echo "[!] Cấu hình lỗi. Không khởi động lại."
fi

echo "[+] Kiểm tra SSL bằng openssl và curl:"
echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -subject -issuer
curl -vI --resolve "$domain:443:127.0.0.1" "https://$domain" 2>&1 | grep -Ei 'subject:|issuer:|expire date|SSL certificate|Server:|HTTP/'
