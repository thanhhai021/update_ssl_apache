# Cập nhật SSL tự động cho Apache trên Linux

Script Bash này giúp **tự động cập nhật chứng chỉ SSL** cho domain sử dụng Apache, hỗ trợ cả hệ điều hành dùng `apt` (Ubuntu, Debian) và `yum`/`dnf` (CentOS, AlmaLinux, RHEL).

---

## 🛠 Chức năng

- Tìm tự động file cấu hình `.conf` chứa domain
- Hiển thị và **backup SSL cũ**
- Gộp CRT + CA bundle thành `fullchain.crt`
- Ghi đè các file `.crt`, `.key`, `.ca-bundle` hiện có
- Kiểm tra tính hợp lệ của chuỗi chứng chỉ trước khi áp dụng
- Kiểm tra `Syntax` cấu hình Apache trước khi restart
- Hỗ trợ cho `mod_ssl` (tự động cài nếu thiếu)
- Hiển thị đường dẫn SSL cũ, đường dẫn file mới
- Cảnh báo khi chưa tắt Unikey (tránh lỗi nhập đường dẫn)

---

## 💻 Cách sử dụng

### 1. Tải script

```bash
wget https://raw.githubusercontent.com/thanhhai021/update_ssl_apache/refs/heads/main/update_SSL_apache.sh
chmod +x update_SSL_apache.sh
