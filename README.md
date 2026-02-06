# Antigravity Manager - Docker Deployment (Linux)

Docker Compose setup cho [Antigravity Manager](https://github.com/lbjlaq/Antigravity-Manager) với `rclone sync` tự động đến Supabase S3.

## Kiến trúc

```text
┌─────────────────────┐         ┌──────────────────────┐
│  rclone-sync        │         │   antigravity        │
│                     │         │                      │
│  1) Sync DOWN       │────┐    │  - Web UI (port 8045)│
│  2) Create READY    │    │    │  - SQLite database   │
│  3) Loop sync UP    │    └───→│  - Start sau READY   │
└─────────────────────┘         └──────────────────────┘
         │                               │
         └───────── antigravity_data ────┘
              (shared Docker volume)
```

Nguyên tắc chính:
- Không dùng `rclone mount` (FUSE) với SQLite.
- Chỉ dùng `rclone sync`.
- Tất cả cấu hình đọc từ `.env`.

## Yêu cầu môi trường

- Linux host/runner
- Docker Engine + Docker Compose v2
- `sh`, `make` (khuyến nghị)

## Quick Start

```bash
git clone <your-repo-url>
cd odtuyet-wq-antigravity-manager

cp .env.example .env
chmod +x scripts/*.sh

# chỉnh thông tin S3 + password web
vi .env

docker compose --env-file .env up -d
docker compose --env-file .env logs -f
```

Web UI: `http://localhost:8045` (hoặc port bạn đặt trong `.env`).

## Cấu hình

Biến chính trong `.env`:

| Biến | Mô tả |
| --- | --- |
| `ANTIGRAVITY_MANAGER_HOST_PORT` | Port web UI |
| `ANTIGRAVITY_MANAGER_WEB_PASSWORD` | Password đăng nhập |
| `ANTIGRAVITY_MANAGER_REMOTE` | Tên remote rclone (vd: `supabase`) |
| `ANTIGRAVITY_MANAGER_REMOTE_PATH` | Đường dẫn bucket/path trên S3 |
| `ANTIGRAVITY_MANAGER_SYNC_INTERVAL_SECONDS` | Chu kỳ sync up |
| `ANTIGRAVITY_MANAGER_SYNC_MAX_RETRIES` | Số lần retry khi sync lỗi |
| `ANTIGRAVITY_MANAGER_SYNC_RETRY_DELAY_SECONDS` | Delay giữa các lần retry |
| `ANTIGRAVITY_MANAGER_S3_ENDPOINT` | Supabase S3 endpoint |
| `ANTIGRAVITY_MANAGER_S3_REGION` | Region S3 (`auto` nếu chưa chắc) |
| `ANTIGRAVITY_MANAGER_S3_ACCESS_KEY_ID` | Access key |
| `ANTIGRAVITY_MANAGER_S3_SECRET_ACCESS_KEY` | Secret key |

## Makefile (Linux)

```bash
make help            # danh sách lệnh
make setup           # tạo .env + chmod scripts
make compose-config  # validate compose config
make ci-validate     # check dùng cho CI (GH Actions/Azure)
make up
make logs
make backup
make restore
make sync-manual
make test-s3
```

## Chạy trên GitHub Actions / Azure Pipelines (Linux)

Trong job Linux (`ubuntu-latest` / `ubuntu-*`), dùng flow tối thiểu:

```bash
cp .env.example .env
chmod +x scripts/*.sh
sh scripts/ci-validate.sh
docker compose --env-file .env config
```

Lưu ý secrets:
- Không commit `.env`.
- Nạp `ANTIGRAVITY_MANAGER_*` từ secret store của pipeline.

Template sẵn có:
- GitHub Actions: `.github/workflows/linux-validate.yml`
- Azure Pipelines: `azure-pipelines.yml`

## Troubleshooting nhanh

```bash
docker compose --env-file .env ps
docker compose --env-file .env logs rclone-sync
docker compose --env-file .env logs antigravity
```

```bash
make check-ready
make test-s3
make sync-manual
```

## Cấu trúc thư mục

```text
odtuyet-wq-antigravity-manager/
├── docker-compose.yml
├── .env.example
├── .gitignore
├── Makefile
├── README.md
├── scripts/
│   ├── sync-entrypoint.sh
│   ├── antigravity-entrypoint.sh
│   └── ci-validate.sh
└── yml-action-pipeline/
```
