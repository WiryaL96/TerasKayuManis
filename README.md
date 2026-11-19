# TerasKayuManis

Monorepo self-order restoran: customer memilih menu di web, kasir memeriksa order
melalui web/Flutter, lalu memasukkan dan menerima pembayaran secara manual di POS
restoran. Web mencatat konfirmasi handoff; tagihan akhir dan struk resmi dari POS.

**Mulai dari [indeks dokumentasi](docs/README.md)** atau
[panduan penggunaan](docs/panduan-penggunaan.md).

## Struktur

| Folder | Isi |
| --- | --- |
| `frontend/` | Nuxt 4, Vue 3, TypeScript, Tailwind; customer/kasir/admin |
| `backend/internal/` | Go API, autentikasi staf, order, laporan, sync/WebSocket |
| `backend/legacy-nuxt/` | Nitro/BFF aktif: katalog, staf, pengaturan, proxy Go |
| `backend/migrations/` | Migrasi SQL berurutan; versi source terbaru 0020 |
| `mobile/cashier/` | Flutter Android, native watcher, tes; scaffold iOS |
| `mobile/cashier/perf_harness/` | Runner benchmark terpisah dengan data sintetis |
| `deploy/` | Caddy/systemd, backup terenkripsi dan restore |
| `scripts/`, `tests/` | Regresi, integrasi dan pemeriksaan operasional |

Branch aktif hanya `main`. Riwayat pekerjaan sebelum konsolidasi ada di Git dan
diringkas di [riwayat dokumentasi](docs/riwayat.md).

## Menjalankan lokal

Gunakan Node sesuai `package.json`, Go sesuai `backend/go.mod`, dan Flutter sesuai
`mobile/cashier/.fvmrc`. Install JavaScript dari root dengan satu lockfile:

```sh
npm ci
```

Salin `frontend/.env.example` dan `backend/.env.example` menjadi `.env` pada folder
masing-masing. Isi konfigurasi proyek development/staging secara privat. Jalankan
di dua terminal dari root:

```sh
npm run dev:backend
npm run dev
```

Frontend biasanya di `http://localhost:3000`; Go di `http://127.0.0.1:8080`.
`NUXT_GO_API_URL` harus menunjuk Go tersebut. `/ready` mengecek koneksi database
dan kontrak schema/hak runtime, bukan hanya proses HTTP hidup.

- [Setup frontend](frontend/README.md)
- [Setup backend dan migrasi](backend/README.md)
- [Setup mobile](mobile/cashier/README.md)
- [Arsitektur implementasi](backend/arsitektur.md)

## Pemeriksaan

```sh
npm run test:structure
npm run test:staff
npm run test:dashboard
npm run test:docs
npm run typecheck
npm run build
python scripts/validate-mobile-db.py
```

Perintah database membuat container disposable; perlu Docker. Tes Go dengan DB
serta browser Auth tidak boleh diarahkan ke database restoran.

## Rilis

Frontend/BFF dan Go dideploy terpisah. Database memakai Supabase PostgreSQL,
Auth dan Storage. Mode Vercel memakai polling; WebSocket tersedia pada Go persisten.
APK 0.2.0 membutuhkan migrasi 0020 dan API/BFF yang sesuai.

Push `main` menjalankan CI dan konfigurasi repo mengizinkan auto-deploy frontend
Vercel. Atur **Production → Branch Tracking → `main`** pada project
`teraskayumanis`; deploy native Vercel tidak menunggu hasil GitHub CI.
Auto-deploy project Go Vercel dari `main` tetap nonaktif. Pemindahan Go ke VPS
memerlukan jalur API-only; jangan aktifkan `TKM_DEPLOY_TARGET=vps` lama yang
memasang Nuxt dan Go sekaligus. Baca [hosting hybrid](docs/hosting-vercel-vps.md). Ikuti
[production readiness](docs/production-readiness.md) untuk migrasi, staging,
backup/restore, signing APK dan rollback. **Source/build yang lulus bukan bukti
bahwa backend live atau perangkat sudah memenuhi seluruh kriteria production.**
