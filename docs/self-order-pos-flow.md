# Alur self-order dan aplikasi kasir restoran

Disepakati pemilik pada 4 November 2026. Dokumen ini menggantikan asumsi audit
bahwa web menjadi POS utama atau melacak pengantaran hidangan.

1. Pelanggan memilih menu dari QR bersama dan memperoleh nomor self-order.
2. Pelanggan menunjukkan nomor pesanan di kasir sebelum batas 15 menit.
3. Kasir mencocokkan menu/revisi, lalu menekan **Tangani pesanan ini**. Server
   menetapkan satu penanggung jawab secara atomik; kasir lain melihat namanya.
4. Kasir memeriksa apakah pesanan sudah ada di POS, memasukkan menu manual, lalu
   menyelesaikan pembayaran di aplikasi kasir restoran.
5. Pelanggan mengambil nomor meja di kasir. Nomor meja tidak diminta di checkout
   web. Pengantaran hidangan mengikuti proses restoran/POS.
6. Kasir mencentang bahwa menu telah diinput dan pembayaran selesai di POS,
   mengisi nomor transaksi POS bila tersedia, lalu menekan **Sudah masuk aplikasi
   kasir**. Web mencatat konfirmasi manual, kasir dan waktunya.

## Status

- `pending`: menunggu pelanggan/menu diperiksa; batas 15 menit berlaku.
- `pos_input`: ditangani kasir tertentu. Batas datang ke kasir berhenti dan menu
  dibekukan selama input manual untuk menghindari perubahan bersamaan.
- `forwarded`: kasir menyatakan input dan pembayaran POS selesai; masuk riwayat
  web. Ini bukan verifikasi otomatis ke aplikasi POS.
- `expired`/`cancelled`: periksa POS sebelum membuat pesanan ulang, terutama jika
  koneksi terputus setelah input manual.
- `confirmed`/`completed` dan pembayaran web lama dipertahankan sebagai riwayat.

Web tidak memanggil API POS, tidak membuat baris `payments` saat handoff, dan
tidak menerbitkan struk penjualan baru. Field `payment_status` historis tidak
menyatakan pembayaran POS; UI membaca `pos_handoff`. Tagihan akhir, kembalian,
pajak/service final dan struk resmi mengikuti aplikasi kasir restoran. Tahap ini
tetap mengarahkan pelanggan ke pembayaran tunai di kasir; tidak menambah QRIS.

Laporan utama web berisi jumlah dan **estimasi nilai pesanan diteruskan** menurut
`forwarded_at` dalam WIB. Nilai ini bukan pendapatan POS dan tidak boleh
dijumlahkan lagi dengan laporan POS. Riwayat pembayaran web ditampilkan terpisah
tanpa mengubah pembayaran lama menjadi handoff secara otomatis.

## Konkurensi dan pemulihan

- `POST /api/v1/orders/{id}/claim-pos`: harus sudah direview pada versi sekarang;
  satu pemilik, nama dari profil dan pemeriksaan akun/versi sesi pada server.
- `POST /api/v1/orders/{id}/forward-pos`: hanya penanggung jawab; versi claim,
  pernyataan `entered_in_pos`/`paid_in_pos`, referensi opsional maksimal 80 karakter.
  Pengulangan identik tidak membuat audit ganda.
- Jika hasil request belum pasti, muat ulang dan **periksa POS sebelum input atau
  meminta pembayaran lagi**. Web tidak dapat mencegah duplikasi yang dilakukan
  langsung oleh manusia pada aplikasi pihak lain.
- Admin/superadmin bisa mengambil alih dengan alasan 5–200 karakter setelah
  memeriksa POS. Identitas sebelumnya dan alasan tercatat; kasir lama tidak dapat
  menyelesaikan order yang sudah dialihkan.
- Handoff selesai immutable. Nama tersimpan saat mulai penanganan; perubahan
  nama profil tidak menulis ulang riwayat. Akun nonaktif/token lama ditolak.

## Migrasi dan aktivasi

Terapkan `backend/migrations/0014_pos_handoff.sql` setelah 0013 sebagai pemilik DB,
dalam transaksi dengan `ON_ERROR_STOP`, setelah backup. Migrasi menambah status,
tabel RLS, fungsi dan audit; tidak mengubah order/payment historis, checkout keys,
tarif, akun, atau status penerimaan. Readiness rilis baru menolak schema tanpa
migrasi ini agar installer dapat melakukan rollback kode.

API HTTP `confirm-cash` dan `complete` lama menolak penulisan dengan 410, termasuk
dari UI lama yang masih tercache. SQL pembayaran lama dipertahankan untuk
kompatibilitas operator/riwayat dan pengujian restore; tidak dipanggil UI baru.
Tutup sesi kasir lama dan buka ulang saat pergantian rilis.

Uji minimal dua kasir, request bersamaan, token lama, pengambilalihan admin,
koneksi putus setelah input POS, laporan WIB dan riwayat lama pada staging.
Migrasi database restoran, tarif dan penerimaan tidak diaktifkan otomatis ketika
kode dipush. Persetujuan estimasi katalog tetap diperlukan sebelum go-live.

## Verifikasi

Migration 0014 adalah awal alur POS, bukan versi terakhir schema. Rilis sekarang
membutuhkan seluruh migration sampai 0020. Ikuti [migrasi](migration.md) dan
[production readiness](production-readiness.md). Tes SQL/Go/Playwright menguji
claim bersamaan, token lama, retry dan handoff tanpa membuat pembayaran web baru.
Catatan bukti terdahulu berada di [riwayat](riwayat.md).
