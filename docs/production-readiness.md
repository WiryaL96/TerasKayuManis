# Production readiness dan runbook rilis

Dokumen ini adalah acuan rilis utama. Branch aktif adalah `main`; push ke main
menjalankan CI. Konfigurasi repo mengizinkan auto-deploy frontend Vercel dari
`main` setelah Production Branch Tracking project `teraskayumanis` disetel ke
`main`. Deploy native Vercel berjalan terpisah dan tidak menunggu GitHub CI.
Auto-deploy Go Vercel tetap nonaktif; migrasi database dan perpindahan backend
ke VPS memerlukan tindakan operator terpisah. Lihat [hosting hybrid](hosting-vercel-vps.md).

## Status saat ini

- Web, Go, dan Flutter sudah berada dalam satu monorepo.
- APK mobile versi `0.2.0+2` membutuhkan backend/BFF dan migrasi `0020_mobile_watch`.
- Build release dapat dikompilasi, tetapi signing key produksi belum berada di repository.
- Xiaomi sempat terdeteksi ketika pengecekan instalasi, tetapi instalasi dibatalkan.
  FPS, battery, thermal, ANR, Keystore perangkat dan soak satu shift belum diuji.
- Staging live fixture dan credential production tidak boleh ditulis di Git.

## Sebelum migrasi

1. Pastikan project Supabase, domain, BFF, Go backend, dan repository yang dipilih
   benar. Jangan memakai database production untuk test fixture.
2. Jeda penerimaan order dan selesaikan order aktif sesuai prosedur restoran.
3. Ambil backup database/media terenkripsi dan lakukan restore drill terisolasi.
4. Catat migration yang sudah diterapkan. Jangan menjalankan ulang migration lama.
5. Pastikan owner memiliki akses DDL dan runtime menggunakan role terbatas.

## Migrasi mobile watch

Jalankan `backend/migrations/0020_mobile_watch.sql` sebagai operator database
setelah migration sebelumnya tersedia. Migration ini menambahkan lease baca terbatas,
index order/outbox, dan memperbarui maintenance cleanup. Setelah selesai:

```sql
select to_regprocedure('tkm.issue_watch(uuid,uuid,integer,text)');
select to_regclass('tkm.watch_leases');
```

Keduanya harus tersedia. Reload schema bila Supabase/PostgREST memerlukan. Deploy
Go backend yang memiliki endpoint `admin/watch`, detail staf, summary order, dan
date filter sebelum APK baru digunakan.

## Environment

| Runtime | Konfigurasi |
| --- | --- |
| Frontend/BFF | `NUXT_SITE_URL`, `NUXT_GO_API_URL`, `NUXT_SUPABASE_URL`, `NUXT_SUPABASE_ANON_KEY`, `NUXT_SUPABASE_SERVICE_KEY`, `NUXT_PUBLIC_SUPABASE_URL`, `NUXT_PUBLIC_SUPABASE_ANON_KEY`, `NUXT_CASHIER_PIN_SECRET` |
| Frontend Vercel | `NUXT_SERVERLESS=true`, `NUXT_PUBLIC_SYNC_MODE=polling`, `NUXT_BACKEND_PROXY_SECRET` |
| Go | `APP_ENV=production`, `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `HOST=0.0.0.0` pada container/Vercel |
| Go Vercel | `TKM_PROXY_SECRET`, `CRON_SECRET` minimum 32 karakter, `GOFLAGS=-buildvcs=false`; platform mengisi `VERCEL`/`PORT` |
| Flutter | `API_BASE_URL` berakhiran `/api/core/`, `SUPABASE_URL`, public `SUPABASE_ANON_KEY`, `SYNC_MODE=polling`; WSS/Origin untuk runtime persisten |

Secret proxy frontend/Go harus sama; cron secret terpisah. Secret PIN harus stabil
lintas deploy dan dicadangkan privat karena dump DB tidak cukup untuk memulihkan
kredensial PIN. Mobile tidak membawa password/PIN/service key/database URL.
Site URL harus origin HTTPS canonical yang sama dengan header Origin login.

Satu proyek Supabase untuk DB/Auth/Storage setiap environment. Gunakan transaction
pooler untuk fungsi Go Vercel sesuai mode Exec; session/direct untuk backup dan
operasi DDL yang membutuhkannya. Aktifkan TLS dan verifikasi CA/hostname. Jangan
menyimpan DSN dalam argument CLI/log GitHub. Akun runtime tidak boleh pemilik DB.

Preflight privat (hanya mencetak nama konfigurasi yang salah):

```sh
node --env-file=/private/frontend.env scripts/vercel-preflight.mjs frontend
node --env-file=/private/backend.env scripts/vercel-preflight.mjs backend
```

## Bootstrap dan akun pertama

Superadmin pertama dibuat operator, bukan registrasi publik. Isi `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY` dan `SITE_URL` melalui env privat, lalu dari root:

```sh
node scripts/bootstrap-superadmin.mjs --name 'Nama pemilik' --email 'owner@example.invalid' --project 'PROJECT_REF' --output /private/new-superadmin-link.txt
```

Ganti identitas contoh dengan pemilik yang sebenarnya. Output harus file baru;
script membatasi permission, tidak mencetak link, dan menolak adopsi akun aktif.
Berikan link secara privat kepada pemilik. `--resume-id` hanya untuk UUID yang
sama dan masih menunggu aktivasi. Staf berikutnya dibuat superadmin melalui UI.

## Backup, cron dan pemulihan

Backup harus mencakup schema `public`, `tkm`, `auth`, `storage` serta **file objek
Storage**. Workflow GitHub mengenkripsi age sebelum upload; recipient publik boleh
di runner, identity dekripsi disimpan owner di lokasi terpisah. Verifikasi backup
terakhir, quota/retensi dan hasil restore yang benar-benar diunduh dari offsite.
Ikuti [backup runbook](../deploy/backup/README.md). Paket gratis tidak berarti
kapasitas arsip/media tidak terbatas.

`deploy/supabase-cron.sql` memasang maintenance expiry dan cleanup log cron.
Periksa `cron.job_run_details` setelah aktivasi; cron bukan backup. Backup status
berhasil bukan bukti restore; kedua waktu harus diverifikasi terpisah.

## Urutan deploy

1. Build/test pada commit yang sama untuk frontend, backend, dan mobile.
2. Terapkan migration pada staging disposable.
3. Deploy backend Go staging; cek `/health` dan `/ready`.
4. Deploy Nitro/BFF staging dengan proxy secret yang sama.
5. Jalankan read-only mobile staging contract test dan flow dua kasir.
6. Jalankan APK profile benchmark serta device acceptance.
7. Setelah owner menyetujui hasil, lakukan backup/maintenance production dan
   terapkan migration yang belum ada; verifikasi fungsi serta hak runtime.
8. Deploy backend/BFF production dan periksa `/ready` serta kontrak mobile.
9. Build APK release dengan private signing key; jalankan verifier certificate,
   identity, debuggable, dan checksum. Periksa `versionName`/`versionCode` dengan
   `aapt dump badging` agar versi upgrade benar.
10. Buka penerimaan order setelah katalog/tarif/POS diverifikasi.

Vercel saat ini memiliki project frontend/BFF dan backend Go terpisah. Git
integration tidak otomatis menerapkan migration. Jalur `TKM_DEPLOY_TARGET=vps`
yang lama memasang **Nuxt dan Go sekaligus**, sehingga tidak boleh diaktifkan
untuk frontend Vercel + Go VPS sebelum tersedia deployment API-only yang diuji.

## Acceptance staging dan smoke test production

- `/health` merespons liveness dan `/ready` merespons schema/runtime siap.
- `/api/core/menu` hanya menampilkan katalog yang published.
- Pada staging: customer dapat membuat order pending dengan token privat dan retry idempoten.
- Kasir dapat login, review, claim, dan melihat detail terbaru.
- Handoff POS hanya bisa dilakukan oleh kasir pemilik claim.
- Dua kasir bersamaan menghasilkan satu claim.
- Nonaktifkan akun staging dan pastikan token lama ditolak.
- Lease watch tidak dapat membaca detail/mutasi dan dapat dicabut.
- Laporan memakai WIB dan tidak menyamakan estimasi handoff dengan revenue POS.

Mutasi sintetis dan pengujian nonaktifkan akun dilakukan **di staging**. Smoke
production dimulai dari baca/health/login akun yang disetujui. Konfirmasi POS
production hanya untuk transaksi yang benar-benar dikerjakan; jangan menandai
paid/forwarded palsu untuk membuat demonstrasi terlihat berhasil.

Catat commit frontend/Go, migration, tanggal, perangkat dan hasil check. Pasang
monitor error/429/p95/readiness, quota DB/egress, cron dan backup terakhir dengan
penerima alert operasional. Target uptime harus disepakati, bukan disimpulkan dari
tes lokal. [Audit](audit-production.md) menyebut batas bukti saat ini.

## Rollback

Rollback kode dan rollback schema adalah tindakan terpisah. Pertahankan release
sebelumnya, jangan menghapus migration/table/riwayat. Jika backend baru belum
terpasang, APK baru tidak boleh dipromosikan. Jika terjadi masalah POS, hentikan
penerimaan order web dan lanjutkan prosedur restoran melalui POS.

## Kriteria go-live

Production belum siap bila salah satu dari ini belum dipenuhi: backup/restore,
migration 0020, `/ready`, staging flow, device acceptance, signing APK, owner
approval katalog/tarif, atau monitoring error/429/p95/backup terakhir. Dokumentasikan
nilai yang benar-benar diuji, bukan target yang belum diukur.
