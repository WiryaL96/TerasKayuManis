# Frontend Nuxt

Nuxt 4/Vue 3/TypeScript/Tailwind CSS, menggunakan composable `useState` dan cache
query yang scoped akun. Customer memakai layout responsif; admin/kasir dirender
di client. Nitro source berada di `../backend/legacy-nuxt` melalui `serverDir`.

Install/jalankan dari root repository:

```sh
npm ci
npm run dev
```

Isi `frontend/.env` dari [.env.example](.env.example) menggunakan proyek uji.
Jalankan Go terpisah dengan `npm run dev:backend`. Set `NUXT_GO_API_URL` ke Go;
request order/menu melalui `/api/core/*`. Supabase service key hanya server.

| URL | Fungsi |
| --- | --- |
| `/`, `/menu`, `/menu/{id}` | Landing, katalog, detail |
| `/cart`, `/checkout` | Keranjang dan checkout idempotent |
| `/order/{id}` | Tracking dengan capability customer |
| `/cashier` | Login dan antrean/review/claim/forward POS |
| `/admin/login`, `/admin` | Login dan dashboard staf |
| `/admin/products`, `/admin/categories`, `/admin/addons` | Katalog |
| `/admin/staff`, `/admin/reports` | Akun staf dan laporan |
| `/admin/settings`, `/admin/activity` | Hanya superadmin |

`/admin/kitchen` dan `/admin/tables` mengalihkan ke dashboard. Tidak ada KDS atau
QR meja aktif. [Panduan penggunaan](../docs/panduan-penggunaan.md) menjelaskan
alur sesuai tombol, [production readiness](../docs/production-readiness.md)
menjelaskan deploy dua project Vercel.

Tes: `npm run typecheck`, `npm run test:structure`, `npm run test:staff`,
`npm run test:dashboard`, browser customer/dashboard, lalu `npm run build`.
Browser mock memeriksa UI; `test:staff:integration` memerlukan stack Supabase
disposable nyata seperti CI dan bukan database restoran.
