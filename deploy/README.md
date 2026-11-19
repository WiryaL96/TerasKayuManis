# Deployment

[Production readiness](../docs/production-readiness.md) adalah runbook utama
untuk Vercel frontend/BFF + Go. Folder ini juga memuat jalur VPS opsional:

- `Caddyfile` / `Caddyfile.full`: HTTPS, proxy Nuxt/Go dan WSS.
- `systemd/`: service user terpisah, resource limit, env privat.
- `deploy_release.py`: installer immutable release, verifikasi dan rollback.
- `render_env.py`: allowlist renderer environment server.
- `supabase-cron.sql`: maintenance/expiry; bukan backup.
- [backup/](backup/README.md): ekspor database dan media, enkripsi dan restore.

CI deploy VPS hanya jika `TKM_DEPLOY_TARGET=vps` dan environment runner mengizinkan
`main`. Data rilis/host lama dapat dilihat di [riwayat](../docs/riwayat.md).
Jangan mengganti service/DNS, menerapkan SQL, atau menyalakan order hanya karena
build berhasil. Verifikasi schema dengan `/ready` dan jalankan staging dahulu.
