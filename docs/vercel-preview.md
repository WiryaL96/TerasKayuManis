# Demo UI terisolasi

Preview demo hanya untuk presentasi tanpa database/akun restoran. Nuxt mengaktifkan
mode ini **hanya** saat `VERCEL_ENV=preview` dan `TKM_PREVIEW_DEMO=1` pada build.
Production tidak mengaktifkannya. Gunakan `NUXT_PUBLIC_SYNC_MODE=polling`.

Demo menggunakan simulasi lokal di browser. API server ditolak 503; tidak ada
request Supabase, pembayaran atau transaksi POS nyata. Jangan memasang secret
backend/database pada deployment demo. State tiap browser terpisah, bukan uji
konkurensi atau kapasitas production. Maksimal 200 order simulasi lalu reset.

| Peran simulasi | Akses contoh |
| --- | --- |
| Superadmin | `owner.demo` / `preview123` |
| Admin | `admin.demo` / `preview123` |
| Kasir | Pilih nama contoh / PIN `123456` |

Kredensial tersebut hanya milik simulator. Jangan masukkan data pelanggan atau
kredensial staf nyata. Demo menunjukkan menu → checkout → review → claim →
konfirmasi POS sintetis dan laporan pada browser yang sama. Foto/account/backup
nyata tidak disiapkan oleh simulator. Tarif contoh tidak menentukan tarif restoran.

`npm run test:preview` memeriksa guard dan perilaku simulator. Browser fixture:
build dengan flag preview di atas dan preset Node, lalu `npm run test:preview:browser`.
Untuk staging operasional gunakan backend/Auth/database uji terpisah, sesuai
[production readiness](production-readiness.md), tanpa flag demo.
