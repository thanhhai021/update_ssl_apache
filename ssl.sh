#!/bin/bash

set -e

# --- 1. Nhắc nhở người dùng ---
echo "[!] Vui lòng tắt Unikey hoặc bộ gõ tiếng Việt trước khi nhập đường dẫn!"
sleep 2

# --- 2. Nhập domain ---
read -rp "[?] Nhập domain cần cập nhật SSL: " domain
domain="${domain,,}"
if [[ -z "$domain" ]]; then
    echo "[!] Domain không hợp lệ."
    exit 1
fi

# --- 3. Xác định file config Nginx ---
conf_file=$(grep -ril "$domain" /etc/nginx/conf.d/*.conf /etc/nginx/sites-available/*.conf 2>/dev/null | head -n1)

if [[ -z "$conf_file" ]]; then
    conf_file="/etc/nginx/conf.d/$domain.conf"
    [[ -d /etc/nginx/sites-available ]] && conf_file="/etc/nginx/sites-available/$domain.conf"
    echo "[+] Không tìm thấy cấu hình. Tạo file mới: $conf_file"
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
EOF
else
    echo "[+] Đã tìm thấy file cấu hình: $conf_file"
fi

# --- 4. Đọc đường dẫn CRT/KEY từ config ---
crt_path=$(grep -i "ssl_certificate " "$conf_file" | grep -v _key | awk '{print $2}' | tr -d ';' | head -n1)
key_path=$(grep -i "ssl_certificate_key" "$conf_file" | awk '{print $2}' | tr -d ';' | head -n1)

echo "[+] Đường dẫn SSL hiện tại từ config:"
echo "    CRT: $crt_path"
echo "    KEY: $key_path"

# --- 5. Nhập thư mục chứa SSL mới ---
default_ssl_dir="/etc/ssl/certs"
read -rp "[?] Nhập thư mục chứa SSL mới (default: $default_ssl_dir): " new_ssl_dir
new_ssl_dir="${new_ssl_dir:-$default_ssl_dir}"
new_ssl_dir="${new_ssl_dir%/}"

echo "[+] Danh sách file SSL trong $new_ssl_dir chứa '$domain':"
find "$new_ssl_dir" -type f \( -iname "*${domain}*.crt" -o -iname "*${domain}*.cer" -o -iname "*${domain}*.pem" -o -iname "*${domain}*.key" -o -iname "*ca*" \) -exec basename {} \;

new_crt=$(find "$new_ssl_dir" -iname "*${domain}*.crt" -o -iname "*${domain}*.pem" -o -iname "*${domain}*.cer" | head -n1)
new_key=$(find "$new_ssl_dir" -iname "*${domain}*.key" | head -n1)
new_ca=$(find "$new_ssl_dir" -iname "*ca-bundle*" -o -iname "*ca*.crt" -o -iname "*ca*.pem" | head -n1)

# --- 6. Kiểm tra hợp lệ ---
if [[ -s "$new_crt" && -s "$new_key" ]]; then
    openssl x509 -noout -modulus -in "$new_crt" > /tmp/crt.mod 2>/dev/null || true
    openssl rsa -noout -modulus -in "$new_key" > /tmp/key.mod 2>/dev/null || true
    if cmp -s /tmp/crt.mod /tmp/key.mod; then
        echo "[+] CRT và KEY hợp lệ."
    else
        echo "[!] CRT và KEY không khớp!"
        exit 1
    fi
    rm -f /tmp/*.mod
else
    echo "[!] Không tìm thấy CRT hoặc KEY hợp lệ."
    exit 1
fi

# --- 7. Backup ---
timestamp=$(date +%Y%m%d-%H%M%S)
backup_dir="/etc/ssl/backup/${domain}-$timestamp"
mkdir -p "$backup_dir"
[[ -f "$crt_path" ]] && cp "$crt_path" "$backup_dir/"
[[ -f "$key_path" ]] && cp "$key_path" "$backup_dir/"
echo "[+] Đã backup SSL cũ vào: $backup_dir"
echo "    Backup gồm:"
ls -1 "$backup_dir"

# --- 8. Cập nhật file SSL ---
mkdir -p "$(dirname "$crt_path")" "$(dirname "$key_path")"

if [[ -n "$new_ca" ]]; then
    echo "[*] Gộp CRT + CA thành fullchain và ghi vào $crt_path"
    cat "$new_crt" "$new_ca" > "$crt_path"
else
    echo "[*] Không có CA bundle. Dùng riêng CRT"
    cp "$new_crt" "$crt_path"
fi
cp "$new_key" "$key_path"
echo "[+] Đã cập nhật file SSL mới"

# --- 9. Kiểm tra config và reload Nginx ---
echo "[+] Kiểm tra cấu hình nginx..."
if nginx -t 2>&1 | tee /tmp/nginx_test | grep -qi "successful"; then
    echo "[+] Cấu hình OK. Restart nginx..."
    systemctl restart nginx && echo "[+] Nginx đã khởi động lại."
else
    echo "[!] Cấu hình Nginx lỗi. Không khởi động lại."
fi

# --- 10. Kiểm tra kết nối SSL ---
echo "[+] Kiểm tra SSL bằng openssl:"
echo | openssl s_client -connect "$domain:443" -servername "$domain" 2>/dev/null | openssl x509 -noout -subject -issuer

echo "[+] Kiểm tra SSL bằng curl:"
curl -vI --resolve "$domain:443:127.0.0.1" "https://$domain" 2>&1 | grep -Ei 'subject:|issuer:|expire date|SSL certificate|Server:|HTTP/'
