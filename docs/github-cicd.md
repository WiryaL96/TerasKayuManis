# CI/CD pada branch main

## CI aplikasi

`.github/workflows/ci.yml` berjalan pada push/PR:

- Node install/audit, regresi frontend/Auth/catalog/cache, typecheck dan build.
- Browser layout customer/dashboard dengan fixture.
- PostgreSQL disposable, migrasi sampai 0020, SQL security/flow, Go race/vet/build.
- Supabase lokal/Auth nyata dan Playwright staf/serverless staging. Cleanup
  menghapus stack fixture, tidak menyentuh project restoran.

`.github/workflows/mobile.yml` berjalan untuk perubahan mobile/workflow-nya:
Flutter pin, lockfile, format/analyze/unit/widget, APK debug, JVM tests,
kompilasi instrumentation, release unsigned, dan benchmark runner terpisah.
Compile instrumentation bukan bukti uji Keystore pada HP. Lihat
[testing mobile](../mobile/cashier/docs/TESTING_RELEASE.md).

## Deployment

Git push tidak menerapkan SQL atau membuka order. Project frontend Vercel
`teraskayumanis` memakai root repository, `npm ci`, dan `npm run build:vercel`.
Konfigurasi root mengizinkan auto-deploy `main`; Production Branch Tracking
di dashboard Vercel juga harus menunjuk `main`. Native Git deployment tidak
menunggu hasil GitHub Actions. Periksa CI dan [production readiness](production-readiness.md)
sebelum memakai perubahan untuk operasional.

Auto-deploy `main` untuk project Go Vercel tetap nonaktif sambil menyiapkan
backend VPS. Ikuti [rencana hosting hybrid](hosting-vercel-vps.md); mengaktifkan
frontend tidak memindahkan backend atau menerapkan migration.

Jalur VPS lama memasang Nuxt dan Go sekaligus, bukan Go-only. Jalur ini hanya
aktif ketika `TKM_DEPLOY_TARGET=vps`, ref main, bukan PR, dan
environment `teraskayumanis-vps` mengizinkan branch. Runner harus dikelola operator.
Release memuat server/web/REVISION tanpa .env; installer memeriksa SHA, checksum,
path, runtime readiness serta rollback kode. Jangan mengaktifkan runner lama
tanpa memeriksa host, domain, kredensial dan schema tujuan.

## Backup terpisah

`.github/workflows/backup.yml` dijadwalkan 20:00 UTC (03:00 WIB) pada main. Worker
checkout SHA immutable `BACKUP_SOURCE_REF` yang ditinjau. Artifact dienkripsi age
sebelum upload, retensi 30 hari. Success dan restore proof harus diverifikasi
secara terpisah; workflow YAML bukan bukti job benar-benar sukses.
Lihat [backup/restore](../deploy/backup/README.md).
