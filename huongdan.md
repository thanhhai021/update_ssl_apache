update_SSL_mutil.sh

Script Bash tự động cập nhật SSL cho domain sử dụng Apache Web Server trên Ubuntu/CentOS.

🧩 Tính năng:

Tự động cập nhật SSL (CRT, KEY, CA-BUNDLE)

Tự kiểm tra cấu hình Apache

Tự bật các module cần thiết (mod_ssl, mod_rewrite)

Reload Apache nếu không có lỗi

Kiểm tra SSL sau khi cập nhật bằng curl

📥 Cách sử dụng

1. Tải script về máy:

curl -O https://raw.githubusercontent.com/thanhhai021/update_ssl_apache/refs/heads/main/update_SSL_mutil.sh

2. Cấp quyền thực thi:

chmod +x update_SSL_mutil.sh

3. Chạy script:

./update_SSL_mutil.sh

📌 Quá trình sử dụng:

Nhập domain cần cập nhật SSL (ví dụ: example.com)

Script sẽ tự tìm file cấu hình Apache tương ứng trong /etc/apache2/sites-available/

Hiện thông tin đường dẫn SSL đang sử dụng

Nhập thư mục chứa SSL mới (VD: /root/newssl/)

Script sẽ liệt kê các file có trong thư mục

Tự động cập nhật các file SSL tương ứng

Kiểm tra cấu hình Apache

Nếu không lỗi → Tự động reload Apache

Kiểm tra lại SSL bằng curl và hiện thông tin:

Subject (CN)

Issuer

Ngày bắt đầu và ngày hết hạn

⚠️ Yêu cầu hệ thống:

Apache2

Hệ điều hành Ubuntu/CentOS

Các module Apache: mod_ssl, mod_rewrite

💡 Gợi ý cải tiến:

Tự động kiểm tra chuỗi chứng chỉ hợp lệ

Kiểm tra file cấu hình .conf có đúng chuẩn không trước khi reload

Backup SSL cũ trước khi ghi đè

Tác giả: Thanh Hải

