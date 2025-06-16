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

echo "[+] Tìm file cấu hình Nginx chứa domain $domain..."
conf_file=$(grep -ril "$domain" /etc/nginx/conf.d/*.conf /etc/nginx/sites-available/*.conf 2>/dev/null | head -n1)

if [[ -z "$conf_file" ]]; then
    conf_file="/etc/nginx/conf.d/$domain.conf"
    [[ -d /etc/nginx/sites-available ]] && conf_file="/etc/nginx/sites-available/$domain.conf"
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
    index index.html index.htm;

    location / {
        try_files \$uri \$uri/ =404;
    }
}
EOF
else
    echo "[+] Đang dùng file cấu hình: $conf_file"
fi

crt_path=$(grep -i "ssl_certificate " "$conf_file" | grep -v trusted | awk '{print $2}' | tr -d ';' | head -n1)
key_path=$(grep -i "ssl_certificate_key" "$conf_file" | awk '{print $2}' | tr -d ';' | head -n1)
ca_path=$(grep -i "ssl_trusted_certificate" "$conf_file" | awk '{print $2}' | tr -d ';' | head -n1)

echo "[+] Đường dẫn SSL hiện tại trong file cấu hình:"
echo "    CRT: $crt_path"
echo "    KEY: $key_path"
echo "    CA : $ca_path"

default_ssl_dir="/etc/ssl/certs"
read -rp "[?] Nhập đường dẫn thư mục chứa file SSL mới (default: $default_ssl_dir): " new_ssl_dir
new_ssl_dir="${new_ssl_dir:-$default_ssl_dir}"
new_ssl_dir="${new_ssl_dir%/}"

echo "[+] Danh sách file SSL trong $new_ssl_dir chứa domain $domain:"
ssl_files=($(find "$new_ssl_dir" -type f \( -iname "*.crt" -o -iname "*.key" -o -iname "*.pem" -o -iname "*.cer" -o -iname "*.ca" -o -iname "*.ca-bundle" \) | grep -i "$domain"))
for f in "${ssl_files[@]}"; do
    echo "    - $(basename "$f")"
done

new_crt=$(printf "%s\n" "${ssl_files[@]}" | grep -Ei '\.(crt|pem|cer)$' | head -n1)
new_key=$(printf "%s\n" "${ssl_files[@]}" | grep -Ei '\.key$' | head -n1)
new_ca=$(printf "%s\n" "${ssl_files[@]}" | grep -Ei 'ca|ca-bundle' | head -n1)

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
echo "[+] Backup SSL cũ vào: $backup_dir"
[[ -f "$crt_path" ]] && cp "$crt_path" "$backup_dir/" && echo "    - $(basename "$crt_path")"
[[ -f "$key_path" ]] && cp "$key_path" "$backup_dir/" && echo "    - $(basename "$key_path")"
[[ -f "$ca_path" ]] && cp "$ca_path" "$backup_dir/" && echo "    - $(basename "$ca_path")"

mkdir -p "$(dirname "$crt_path")" "$(dirname "$key_path")"
if [[ -n "$new_ca" ]]; then
    echo "[+] Gộp CRT và CA vào fullchain: $crt_path"
    cat "$new_crt" "$new_ca" > "$crt_path"
else
    echo "[+] Ghi CRT: $crt_path"
    cp "$new_crt" "$crt_path"
fi
cp "$new_key" "$key_path"
[[ -n "$ca_path" && -n "$new_ca" ]] && cp "$new_ca" "$ca_path"

echo "[+] Đã cập nhật SSL cho domain: $domain"

# Tạo cấu hình chuyển hướng HTTP -> HTTPS
redirect_conf_file="/etc/nginx/conf.d/${domain}_redirect.conf"
if [[ ! -f "$redirect_conf_file" ]]; then
    echo "[+] Tạo file chuyển hướng HTTP -> HTTPS: $redirect_conf_file"
    cat > "$redirect_conf_file" <<EOF
server {
    listen 80;
    server_name $domain;

    return 301 https://\$host\$request_uri;
}
EOF
else
    echo "[+] File chuyển hướng HTTP đã tồn tại: $redirect_conf_file"
fi

echo "[+] Kiểm tra cấu hình Nginx..."
if nginx -t 2>&1 | tee /tmp/nginx_test | grep -qi "successful"; then
    echo "[+] Cấu hình hợp lệ. Đang khởi động lại Nginx..."
    systemctl restart nginx && echo "[+] Nginx đã khởi động lại thành công."
else
    echo "[!] Lỗi cấu hình Nginx. Không khởi động lại."
    exit 1
fi

echo "[+] Kiểm tra SSL bằng openssl và curl:"
echo | openssl s_client -connect "$domain:443" 2>/dev/null | openssl x509 -noout -subject -issuer
curl -vI --resolve "$domain:443:127.0.0.1" "https://$domain" 2>&1 | grep -Ei 'subject:|issuer:|expire date|SSL certificate|Server:|HTTP/'
