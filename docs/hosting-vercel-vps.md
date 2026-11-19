# Frontend Vercel dan backend Go di VPS

Topologi yang dituju:

```text
Browser / Flutter → Nuxt + Nitro BFF (Vercel) → Go API (VPS) → Supabase
                              └──────────────────────────→ Auth / Storage / RPC
```

Nuxt tetap menjalankan BFF untuk login, katalog, staf, pengaturan dan proxy
`/api/core/*`. VPS menjalankan Go dan reverse proxy HTTPS; database, Auth dan
Storage tetap di Supabase. Acuan migrasi, backup dan penerimaan production tetap
[production readiness](production-readiness.md).

## Kapasitas dan lokasi

VPS **2 vCPU / RAM 2 GB layak sebagai titik awal untuk Go + reverse proxy**,
bukan jaminan kapasitas restoran. Service API yang tersedia membatasi memori
512 MB dan Go memakai maksimum lima koneksi DB. Build dilakukan di CI, bukan
bersamaan dengan pelayanan order pada VPS kecil. Ukur pemakaian CPU/RAM,
antrean koneksi, error, 429 dan p95 sebelum menetapkan kapasitas.

Lokasi Amerika Serikat perlu diuji terhadap region Supabase dan pengguna
Indonesia. Request melewati BFF, Go, lalu database; operasi staf juga memanggil
Supabase Auth dan melakukan beberapa query berurutan. Jarak antarlayanan dapat
menambah latency pada setiap tahap. CDN Vercel membantu aset statis, tetapi
tidak menghilangkan perjalanan request API. Utamakan Go dan fungsi BFF dekat
database; jika Supabase berada di Asia, VPS Asia biasanya lebih sesuai untuk
topologi ini. Region database dan hasil latency nyata belum diverifikasi.
Lihat [panduan region Vercel](https://vercel.com/docs/functions/configuring-functions/region).

## CI/CD main

Auto-deploy Git untuk frontend pada konfigurasi root diaktifkan untuk
`main`; **Production Branch Tracking** pada project frontend Vercel juga harus
menunjuk `main`. Deployment backend Vercel dari `backend/vercel.json` tetap
dinonaktifkan sampai jalur transisi backend siap. Jangan menganggap perubahan
konfigurasi frontend sudah memindahkan backend ke VPS.

Deploy native Git Vercel berjalan terpisah dan **tidak menunggu GitHub Actions
CI selesai**. Kelulusan CI tetap harus diperiksa sebelum perubahan dipakai
operasional; jika deployment wajib menunggu CI, diperlukan jalur deployment
yang secara eksplisit bergantung pada job CI. Lihat [CI/CD main](github-cicd.md).

## Pekerjaan sebelum pindah ke VPS

- **Pisahkan release Go.** Workflow VPS saat ini mengemas `server`, `web` dan
  `REVISION`. `deploy/deploy_release.py` mewajibkan Nuxt, me-restart dua service,
  memeriksa host lama, dan mengasumsikan release awal sudah ada. Buat alur
  Go-only dengan verifikasi checksum/revision, readiness dan rollback; jangan
  langsung mengaktifkan `TKM_DEPLOY_TARGET=vps` untuk topologi ini.
- **Siapkan API HTTPS.** `deploy/Caddyfile` saat ini meneruskan request biasa ke
  Nuxt lokal. Sesuaikan domain dan routing khusus API. Go cukup mendengarkan
  loopback di belakang proxy; sediakan env privat dan role DB runtime terbatas.
- **Pertahankan batas kepercayaan BFF.** Go persisten belum memeriksa
  `X-TKM-Proxy-Key`; pemeriksaan itu hanya ada pada handler serverless. Terapkan
  verifikasi BFF pada API/proxy serta aturan identitas IP sebelum API VPS dibuka.
- **Evaluasi limiter polling.** Handler persisten membatasi setiap kelompok
  request hingga 300/menit untuk seluruh proses. Tracking customer dan polling
  kasir dapat mencapai batas itu meskipun CPU/RAM masih longgar. Uji serta
  sesuaikan kebijakan tanpa menghapus perlindungan penyalahgunaan.
- **Pilih koneksi DB yang cocok.** Mode persisten masih memakai prepared
  statements pgx. Gunakan direct connection bila jaringan mendukung, atau
  session pooler untuk IPv4; jangan menyalin DSN transaction pooler serverless
  tanpa menyesuaikan driver. Ikuti [panduan koneksi Supabase](https://supabase.com/docs/guides/database/connecting-to-postgres)
  dan tetap verifikasi TLS.
- **Pertahankan polling saat transisi.** URL WebSocket browser masih mengikuti
  origin frontend. WSS ke VPS memerlukan konfigurasi URL/origin tersendiri;
  implementasi sekarang juga hanya mendukung satu instance Go aktif.

## Urutan pelaksanaan

1. Provision VPS, domain API, HTTPS, service Go dan penyimpanan env privat.
   Selesaikan perubahan deployment Go-only di atas terlebih dahulu.
2. Pasang commit yang sama pada BFF dan Go staging, dengan Supabase staging
   terisolasi serta schema sampai 0020. Periksa `/health` dan `/ready`.
3. Jalankan alur customer, dua kasir, retry idempoten, pencabutan sesi dan
   rush test melalui BFF staging. `scripts/staging-rush.mjs` menyediakan
   pengujian sintetis terjaga; catat region, p95, error/429 dan resource VPS.
4. Verifikasi backup offsite serta restore nyata, migration yang masih kurang,
   dan monitoring sesuai runbook production.
5. Deploy Go production, lalu arahkan `NUXT_GO_API_URL` Vercel ke origin API
   HTTPS dengan kredensial BFF yang sesuai. Pertahankan polling dan verifikasi
   alur melalui frontend sebelum membuka penerimaan order.
6. Simpan release Go dan deployment Vercel sebelumnya untuk rollback kode.
   Rollback tidak menghapus schema, order atau riwayat transaksi.

Dokumen ini adalah rencana transisi berdasarkan source. Provisioning VPS,
cutover, hosted load test dan kapasitas production belum dinyatakan selesai.
