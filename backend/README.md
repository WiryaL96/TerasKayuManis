# Backend Go dan Nitro

Go menangani menu publik, checkout, review, claim/forward POS, detail/riwayat,
laporan, receipt historis, dan sync. Banyak aturan atomik berada pada fungsi
PostgreSQL `tkm.*`; lihat [arsitektur](arsitektur.md).

`legacy-nuxt/` tetap aktif melalui `frontend/nuxt.config.ts`: BFF, Auth UI, CRUD
katalog/staf/pengaturan dan agregasi dashboard. API order Nitro lama mengembalikan
410 agar hanya satu jalur menulis transaksi order.

## Development

Go mengikuti versi `go.mod`. Dari root repository:

```sh
npm run dev:backend
```

Perintah tersebut membaca `backend/.env`. Jika menjalankan binary/go secara
langsung, isi environment proses lebih dahulu; binary tidak mencari `.env`.
Konfigurasi contoh ada di [.env.example](.env.example). Gunakan database uji,
Supabase URL/anon key dari proyek yang sama, serta role aplikasi `tkm_runtime`.

`GET /health` menunjukkan liveness; `GET /ready` mengecek DB dan schema/hak
tertentu sampai migrasi 0020. Tanpa DB atau schema yang cocok, readiness 503.
Readiness bukan tes login, Storage, POS, backup, atau perangkat.

Pool maksimum lima koneksi pada proses persisten; Vercel maksimum dua, mode Exec,
timeout koneksi dua detik. HTTP REST dibatasi delapan detik. TLS diterminasi proxy.
Production memerlukan DATABASE_URL; secret/database error tidak dikirim ke client.

## Database

Ikuti [panduan migrasi](../docs/migration.md). `migrations/0001_cash_only.sql`
adalah basis schema target. `supabase/migrations/0001_init.sql` adalah peninggalan
legacy, **bukan** bagian urutan install baru. Jangan mencampur kedua schema.
Migration runner otomatis production belum disediakan; operator memakai transaksi
dan `ON_ERROR_STOP` dengan daftar migration yang belum diterapkan.

## Tes

```sh
go test ./...
go vet ./...
```

Tanpa TEST_DATABASE_URL, sebagian integration tests skip. Untuk bukti DB nyata,
jalankan dari root `python scripts/validate-mobile-db.py`; runner mengelola DB
Docker disposable beserta cleanup. CI Linux menjalankan `go test -race ./...`.

WebSocket pada satu proses persisten dijelaskan di [REALTIME](REALTIME.md).
[Runbook production](../docs/production-readiness.md) memuat urutan deploy dan rollback.
