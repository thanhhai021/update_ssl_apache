Script Cập Nhật SSL Cho Apache Tự Động

Script giúp tự động cập nhật chứng chỉ SSL (CRT, KEY, CA) cho Apache, hỗ trợ cả CentOS/RHEL và Ubuntu/Debian.

📅 Cài wget nếu chưa có

📅 Tải script

wget https://raw.githubusercontent.com/thanhhai021/update_ssl_apache/refs/heads/main/update_SSL_apache.sh

✅ Cấp quyền thực thi

chmod +x update_SSL_apache.sh

🚀 Cách sử dụng

./update_SSL_apache.sh

Sau đó làm theo các bước hướng dẫn:

Nhập domain cần cập nhật SSL (ví dụ: example.com)

Script sẽ tự động:

Tìm file .conf cấu hình Apache đang sử dụng cho domain đó

Hiển thị đường dẫn các file SSL đang dùng hiện tại

Nhập đường dẫn chứa SSL mới (ví dụ: /root/newssl/)

Script sẽ liệt kê các file có trong thư mục

Tự động kiểm tra CRT và KEY có khớp nhau không

Tự động backup SSL cũ trước khi ghi đè

Tự động ghép CRT và CA thành fullchain nếu cần

Kiểm tra lại cấu hình Apache (apachectl configtest)

Nếu cấu hình hợp lệ, Apache sẽ được khởi động lại

📋 Lưu ý

Tắt Unikey hoặc bộ gõ tiếng Việt trước khi nhập đường dẫn để tránh lỗi dấu (/)

Script tương thích với:

Ubuntu/Debian (sử dụng apt)

CentOS/RHEL (sử dụng yum hoặc dnf)

Nếu chứng chỉ SSL là self-signed hoặc CA không phổ biến, khi test bằng curl có thể thấy cảnh báo, nhưng không ảnh hưởng nếu bạn biết rõ nguồn gốc chứng chỉ.

🔍 Kiểm tra sau khi cập nhật SSL

curl -kvI https://yourdomain.com:443

📁 File cấu hình Apache

Script sẽ tìm file chứa dòng ServerName yourdomain.com trong các thư mục:

Ubuntu/Debian: /etc/apache2/sites-available/

CentOS/RHEL: /etc/httpd/conf.d/
