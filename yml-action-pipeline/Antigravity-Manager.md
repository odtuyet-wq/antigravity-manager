### Tài liệu đính kèm:

- [\[Github.com\] - Antigravity-Manager](https://github.com/lbjlaq/Antigravity-Manager "Antigravity-Manager &#40;https://github.com/lbjlaq/Antigravity-Manager&#41;")
    
- [Hướng dẫn Docker (persist \`/root/.antigravity_tools\`, cách chạy)](https://github.com/lbjlaq/Antigravity-Manager/tree/main/docker)
    
- [S3 Authentication (Access Key/Secret, \*\*cảnh báo: S3 keys bypass RLS\*\*)](https://supabase.com/docs/guides/storage/s3/authentication)
- [S3 Compatibility (S3-compatible endpoint):](https://supabase.com/docs/guides/storage/s3/compatibility) 
- [rclone S3 backend docs (tuỳ chọn, tối ưu sync)](https://rclone.org/s3/)
- [rclone docs tổng (cấu hình + usage)](https://rclone.org/docs/)
- [Compose: Control startup order (đợi service phụ thuộc “healthy” trước khi start service chính)](https://docs.docker.com/compose/how-tos/startup-order/)
- [Compose file reference (schema cấu hình)](https://docs.docker.com/reference/compose-file/)
- [SQLite official: “Use SQLite over a network” (cảnh báo network FS/lock → dễ lỗi/corruption)](https://sqlite.org/useovernet.html)
- [Tham khảo rủi ro mount S3 kiểu filesystem (s3fs stability discussion)](https://stackoverflow.com/questions/10801158/how-stable-is-s3fs-to-mount-an-amazon-s3-bucket-as-a-local-directory)

### Diễn giải: Tạo bộ triển khai **Docker Compose (2 containers)** cho `lbjlaq/Antigravity-Manager` theo mô hình **rclone sync + antigravity**.

### Mục tiêu & nguyên tắc

- **Tách 2 container**:
    
    1.  `rclone-sync`:
        
        - **sync down 1 lần khi start** từ Supabase S3 về volume dữ liệu
            
        - sau đó chạy vòng lặp **sync up định kỳ** (30s/60s/5m tùy ENV)
            
    2.  `antigravity`:
        
        - **chỉ start sau khi sync down xong**
            
        - mount dữ liệu từ volume vào đúng path **`/root/.antigravity_tools`**
            
- **Không dùng `rclone mount` (FUSE)** vì dữ liệu có SQLite → rủi ro lock/corrupt; chỉ dùng **`rclone sync`**.
    
- Dùng **named volume** `antigravity_data` để cả 2 container dùng chung.
    
- **Tất cả cấu hình phải đọc từ `.env`** (không hardcode).
    
- Supabase S3: luôn thêm flag **`--s3-list-version 2`** để tránh lỗi listing theo hướng dẫn Supabase.
    
- Secrets (S3 key/secret, password) **chỉ lấy từ `.env`**.
    

### Files cần xuất ra

1.  `docker-compose.yml`
    
2.  `rclone/rclone.conf` (template dùng biến môi trường nếu có thể, hoặc generate lúc runtime)
    
3.  `scripts/sync-entrypoint.sh` (shell script cho container rclone)
    
4.  `.env.example` (tất cả biến cần thiết + mô tả ngắn)
    

### Hành vi chi tiết cần có

- `rclone-sync` khi chạy:
    
    1.  tạo thư mục `/data/.antigravity_tools`
        
    2.  chạy `rclone sync ${REMOTE}:${REMOTE_PATH} /data/.antigravity_tools ...`
        
    3.  tạo file cờ `/shared/READY`
        
    4.  loop mỗi `${SYNC_INTERVAL_SECONDS}`:
        
        - `rclone sync /data/.antigravity_tools ${REMOTE}:${REMOTE_PATH} ...`
- `antigravity`:
    
    - entrypoint chờ `/shared/READY` tồn tại rồi mới start antigravity
        
    - expose port theo ENV (ví dụ `HOST_PORT:8045`)
        
    - set mật khẩu web quản trị từ ENV (ví dụ `WEB_PASSWORD` hoặc `ABV_WEB_PASSWORD`)
        

### Biến môi trường bắt buộc (đưa trong `.env.example`)

- `ANTIGRAVITY_MANAGER_HOST_PORT=8045`
    
- `` `ANTIGRAVITY_MANAGER_`SYNC_INTERVAL_SECONDS=60 ``
    
- `` `ANTIGRAVITY_MANAGER_REMOTE`supabase `` (tên remote rclone)
    
- `` `ANTIGRAVITY_MANAGER_`REMOTE_PATH=bucket/antigravity/state/prod `` (đường dẫn trên S3)
    
- `ANTIGRAVITY_MANAGER_S3_ENDPOINT=...`
    
- `ANTIGRAVITY_MANAGER_S3_REGION=...`
    
- `ANTIGRAVITY_MANAGER_S3_ACCESS_KEY_ID=...`
    
- `ANTIGRAVITY_MANAGER_S3_SECRET_ACCESS_KEY=...`
    
- `ANTIGRAVITY_MANAGER_WEB_PASSWORD=...` (password quản trị web antigravity)
    
- (tuỳ chọn) `ANTIGRAVITY_MANAGER_RCLONE_LOG_LEVEL=INFO`
    
- (tuỳ chọn) `ANTIGRAVITY_MANAGER_RCLONE_EXTRA_FLAGS=` (để mở rộng tương lai)
    

### Yêu cầu output

- Trả về đầy đủ nội dung 4 files ở trên.
    
- Script bash phải có `set -euo pipefail`, log rõ ràng, retry hợp lý (ví dụ 5 lần) khi sync fail.
    
- Compose phải mount:
    
    - `antigravity_data:/data/.antigravity_tools` cho rclone
        
    - `antigravity_data:/root/.antigravity_tools` cho antigravity
        
    - thêm volume `shared_ready:/shared` hoặc bind để share file READY
        
- Không dùng mount FUSE, không dùng rsync.
    
- Gợi ý lệnh chạy: `cp .env.example .env && docker compose up -d`.