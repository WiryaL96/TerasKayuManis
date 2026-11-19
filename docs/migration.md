# Migrasi database

Schema aktif berada di `backend/migrations/`, diterapkan berurutan sebagai pemilik
database. Go menggunakan role aplikasi terpisah `tkm_runtime`. DDL bukan bagian
startup atau build. `backend/supabase/migrations/0001_init.sql` adalah schema
legacy dengan aturan lain; jangan diterapkan bersama schema target.

| Nomor | Perubahan utama |
| --- | --- |
| 0001–0002 | Order cash historis, idempotency, pricing, review dan expiry |
| 0003–0004 | Hak runtime terbatas, publikasi outbox |
| 0005 | QR bersama tanpa table_id wajib; referensi historis dipertahankan |
| 0006–0010 | Snapshot nama kasir, operasional, gate harga/order, foto, audit |
| 0011–0013 | Tiga role, akun langsung, PIN kasir dan foto privat |
| 0014 | Claim/forward manual ke POS; transaksi web lama tetap riwayat |
| 0015–0016 | Sync clock, budget lintas instance, maintenance, dashboard |
| 0017–0019 | Katalog atomik, arsip staf, lifecycle media |
| 0020 | Lease notifikasi baca terbatas, index dan cleanup |

## Database baru

Gunakan Supabase development/staging yang kosong. Tinjau seluruh migration dan
konfigurasi Auth/Storage. Jalankan tiap file satu transaksi dengan `ON_ERROR_STOP`;
buat login runtime dan password secara privat, bukan dari migration. Bootstrap
superadmin melalui operator sesuai [runbook](production-readiness.md).

## Database existing

Backup dan restore drill dahulu. Inventarisir fungsi/tabel/constraint serta catatan
migration operator; jangan menyimpulkan migration sudah terpasang dari keberadaan
satu kolom saja. Terapkan **hanya** file yang belum diterapkan, pada maintenance.
Migration 0003 sengaja menolak role existing yang belum diperiksa; jangan melewati
guard atau menambah hak runtime agar script lolos.

Contoh instalasi yang sudah diverifikasi sampai 0019:

```sh
psql -X -v ON_ERROR_STOP=1 --single-transaction -f backend/migrations/0020_mobile_watch.sql
```

Host/user/password/database disediakan privat. Verifikasi fungsi, ACL/RLS, dan
readiness, lalu `NOTIFY pgrst, 'reload schema';` bila fungsi publik berubah.

## Pengujian dan rollback

`python scripts/validate-mobile-db.py` membuat PostgreSQL disposable serta menjalankan
migration/SQL/Go. CI menjalankan lebih banyak regresi termasuk Auth nyata lokal.
Semua fixture harus pada DB terisolasi. Jangan mengeksekusi `backend/tests/*.sql`
di restoran; beberapa tes menguji kegagalan ACL/role secara sengaja.

Rollback aplikasi mempertahankan schema aditif. Jangan menghapus order, payment,
outbox/key checkout, atau audit untuk menyesuaikan kode lama. Khusus mobile 0.2.0,
rilis backend/BFF dengan 0020 terlebih dahulu. Downgrade aplikasi yang mewajibkan
meja atau pembayaran web tidak kompatibel dengan alur POS/tableless terbaru.
