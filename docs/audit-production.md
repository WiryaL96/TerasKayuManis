# Audit pra-production — 16 November 2026

Baseline `f561075` pada main setelah konsolidasi. Cakupan: source Flutter/native
Android, Go/Nitro/PostgreSQL, alur customer/POS/staf, konfigurasi deployment/backup,
tes dan dokumentasi. Audit source/fixture bukan penetration test atau sertifikasi
kapasitas hosted. Instalasi Xiaomi dibatalkan sesuai instruksi pengguna.

## Temuan yang diperbaiki

| ID | Temuan baseline dan dampak | Perbaikan |
| --- | --- | --- |
| P1-01 | Detail gagal tidak dipulihkan pada revision yang sama; tombol tetap terkunci sampai rekonsiliasi 60 detik/manual | Retry detail yang belum usable pada polling berikutnya tanpa refetch seluruh list |
| P1-02 | Menutup/membuka detail yang sama memakai request layar lama; respons dibuang dan detail baru tidak pernah diisi | Flight dilepas bersama view; callback flight lama tidak menghapus flight baru |
| P1-03 | Respons yang dimulai sebelum pause membuat detail usable lagi saat background | Epoch visibility diperiksa pada sukses/gagal detail; resume meminta state baru |
| P1-04 | Referensi POS berkarakter kontrol dipersist sebelum validasi API, menyebabkan intent selalu gagal saat retry | Validasi sebelum penyimpanan/network |
| P2-01 | Tombol periksa izin tidak memeriksa Android ketika lease cached masih berlaku | Recheck izin eksplisit dan cache guard bergantung izin |
| P2-02 | Native readTimeout hanya per read, sehingga respons menetes bisa menduduki worker terlalu lama | Deadline total 16 detik, disconnect terjadwal, response cap tetap berlaku |
| P2-03 | Timestamp mobile mengikuti timezone HP sedangkan filter history memakai WIB | Waktu tampilan dan default tanggal menggunakan WIB; batas tengah malam diuji |
| SEC-01 | Nuxt/schema 4.6.3 memiliki advisory path `//` dan batas dev-server parent workspace | Nuxt, kit dan schema dinaikkan ke 4.6.4; regresi, typecheck, build dan browser lulus |
| SEC-02 | Dependency arsip Nitro menarik minimatch 10 yang terkena advisory globparts amplification | Override minimatch 11.0.8 untuk readdir-glob, lockfile memakai satu salinan pada root |
| DOC-01 | Dokumen lama masih memerintahkan cash/web payment, kitchen, role/table dan schema legacy | Acuan arsitektur/setup/migrasi/production ditulis ulang; dokumen superseded dihapus |
| DOC-02 | Panduan pengguna belum ada dan label web/mobile berbeda | Panduan per peran berdasarkan UI source, termasuk troubleshooting/POS retry |

Empat tes controller baru gagal pada baseline lalu lulus sesudah perbaikan;
satu tes tambahan memeriksa timestamp WIB melintasi tengah malam dan offset lain.
Lokasi: `mobile/cashier/test/core/preproduction_test.dart`. Kontrak transaksi
server tetap menggunakan expected version/row lock; temuan UI tidak menunjukkan
server dapat dipaksa menerima transaksi ganda.

## Yang sudah ada dan diperiksa kembali

- Customer capability, idempotency payload, pricing server, snapshot harga/nama.
- Supabase user verification + role/status/session_version; RLS/grants runtime.
- Claim tunggal, owner-only forward, audit/history, legacy writes 410.
- Lease notifikasi read-only/TTL/max device, AES-GCM Keystore, generation fence.
- Request/body/response limits, no redirects pada transport mobile, rate budget.
- Katalog atomik, publication constraint, staff archive/revoke dan media cleanup.
- Cache summary/detail, lazy list, isolated countdown dan editor state per baris.
- CI, signing tanpa debug-key fallback, backup/restore script dan safe staging guard.

## Batas dan pekerjaan operator sebelum go-live

| Area | Status/bukti yang masih diperlukan |
| --- | --- |
| Backend production | Probe publik sebelumnya: menu 200, endpoint baru watch 404. Ini bukan pemeriksaan schema penuh. Migration 0020/Go/BFF harus diverifikasi bersama sebelum APK baru |
| Android | Tidak ada instalasi atau benchmark yang dijalankan setelah pembatalan. FPS/jank, Keystore, battery/thermal, notification/OEM, upgrade/soak belum dinyatakan lulus |
| Signing | Belum ada key produksi. APK lama Xiaomi memakai certificate berbeda dari key debug lokal; perlu jalur upgrade yang sah, bukan uninstall otomatis |
| Hosted staging | Kredensial fixture belum tersedia; tes live di-skip, mutasi hanya pada database disposable |
| Backup | Ada bukti historis offsite/restore, tetapi job terbaru dan kapasitas kuota harus diperiksa operator |
| Native storage | Keystore dan commit preferences masih sinkron pada lifecycle tertentu; latency nyata belum diukur di HP |
| Deployment persisten | Batas lane 300/menit per proses dan WSS single-instance; jangan menyamakannya dengan limiter serverless/multi-instance |
| Background notifikasi | Lease 5 jam 30 menit dan batas Android dataSync; bukan FCM, tidak menjamin service setelah force-stop/reboot |
| Observability | Diagnostics lokal bounded tersedia; alert pusat/SLA/monitoring hosted belum dibuktikan |
| iOS | Entitlement tersedia, build/signing/device masih memerlukan Mac/Xcode |

## Verifikasi sesi ini

Pengujian dilakukan pada Windows dengan Node 22.22.3, Flutter 3.47.4/Dart 3.13.3,
JDK 21 dan PostgreSQL 17 disposable. Hasil sesudah perbaikan:

| Pemeriksaan | Hasil |
| --- | --- |
| Dart format / Flutter analyze | Lulus, analyzer tanpa temuan |
| Flutter unit/widget/regresi | 75 lulus; 1 kontrak hosted staging dilewati karena fixture privat belum tersedia |
| Kotlin JVM | 3 lulus, tanpa failure/error |
| Android | Debug, kompilasi instrumentation, profile demo, release ARM64 unsigned dan profile benchmark harness berhasil |
| Database dan Go | Migrasi 0001–0020, guard runtime role, SQL mobile_watch/POS/serverless/order_flow, `go test ./...` dengan DB, dan `go vet ./...` lulus; container dihapus |
| Node regresi | 144 lulus: structure 72, staff/security 45, dashboard 17, bootstrap 2, preview 4, dokumentasi 1, mobile-auth/staging guard 3 |
| Web browser | Chromium: 13 dashboard dan 12 customer lulus pada server fixture lokal |
| Typecheck dan build web | Typecheck, Nuxt preset Node dan paket Vercel berhasil |
| Dependency | `npm ci`, pemeriksaan tree Nuxt/schema/minimatch dan `npm audit --omit=dev --audit-level=high` lulus; hasil scanner masih 7 low dari rantai deepmerge |

Advisory Nuxt `GHSA-r99w-jh2x-3mg9`, schema `GHSA-mjrq-cffv-q4qc`, dan
minimatch `GHSA-g3hv-75wg-m249` tidak lagi muncul pada audit akhir. Deepmerge
4.3.1 masih versi upstream terbaru ketika diperiksa. Mitigasi existing pada
`scripts/patch-deepmerge.mjs` diterapkan saat postinstall dan regresi dangerous-key
untuk input/nested object lulus. Scanner npm menghitung versi paket, sehingga
tetap melaporkan `GHSA-gcqx-w48m-w2h4` beserta dependennya; hasilnya **bukan nol
advisory**. Instalasi yang melewati lifecycle scripts harus menerapkan patch
secara eksplisit dan menjalankan tes keamanan sebelum build.

Build berhasil tidak dianggap sebagai pengukuran FPS, uji perangkat atau
deployment production. Hasil GitHub CI pada commit baru juga memerlukan pemeriksaan
tersendiri. Bukti baseline sebelum audit tersimpan pada [riwayat](riwayat.md).

## Dokumentasi yang dibersihkan

Sebanyak 44 dokumen/hasil JSON bertanggal, roadmap dan task yang sudah digantikan
dihapus dari working tree. Isinya tetap tersedia di Git history. Setup
root/backend/frontend/mobile, kontrak QR/POS, role,
migrasi, backup, API dan testing tetap tersedia. `npm run test:docs` mencegah link
lokal yang putus saat dokumen dipindah/dihapus. [Indeks](README.md) menjadi pintu masuk.
