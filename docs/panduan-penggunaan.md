# Panduan penggunaan TerasKayuManis

Untuk pelanggan, kasir web/mobile, admin dan superadmin. Gunakan alamat aplikasi
yang diberikan pengelola restoran. Aplikasi ini membantu pemesanan; **tagihan akhir,
pembayaran, struk resmi dan pelayanan hidangan mengikuti POS restoran**.

## Akses menurut peran

| Peran | Pekerjaan |
| --- | --- |
| Pelanggan | Memilih menu, checkout, menunjukkan nomor order, melihat konfirmasi |
| Kasir | Review menu, mengambil penanganan, input manual ke POS, konfirmasi selesai input POS |
| Admin | Pekerjaan kasir, katalog, laporan dan mengelola akun kasir |
| Superadmin | Pekerjaan admin, akun admin, pengaturan operasional, aktivitas dan status backup |

Pelanggan tidak membutuhkan akun. Gunakan akun staf pribadi; keluar dari aplikasi
sebelum perangkat diserahkan ke orang lain. Jangan membagikan PIN/password.

## Pelanggan: dari QR sampai kasir

1. Scan QR restoran dengan kamera ponsel. Satu QR membuka menu bersama.
2. Pilih kategori atau cari nama menu. Buka produk, pilih varian yang diminta,
   tambahan, jumlah, dan catatan.
3. Masukkan ke keranjang. Pilihan/catatan dapat diperiksa kembali sebelum checkout.
4. Buka **Keranjang**, tekan **Pesan**, isi nama bila diminta, lalu **Pesan Sekarang**.
5. Halaman **Pesanan Saya** menampilkan nomor order. Tunjukkan kepada kasir dalam
   waktu 15 menit sejak order dibuat; biarkan halaman ini tersimpan di browser.
6. Kasir mencocokkan item dan menyelesaikan proses pada POS restoran.
7. Bayar tunai sesuai arahan kasir, terima struk POS, lalu ambil nomor meja fisik.
8. Halaman order akan menampilkan konfirmasi ketika kasir mencatat handoff selesai.

Tidak perlu memilih meja di web. Estimasi web dapat berbeda dari tagihan akhir POS.
Jangan membayar ulang hanya karena status web belum berubah; tanyakan kepada kasir.

Jika checkout belum pasti, gunakan **Coba ulang pengiriman** pada halaman yang sama.
Jangan langsung membuat order kedua. Jika halaman hilang atau browser ditutup,
hubungi kasir dengan nama/nomor yang masih diketahui sebelum memesan ulang.

## Kasir: masuk dan memeriksa antrean

Web kasir berada pada `/cashier`. Mobile memakai aplikasi **TerasKayuManis Kasir**.
Pada web pilih profil dan masukkan PIN pribadi. Pada mobile pilih **Masuk dengan
PIN kasir**, pilih nama lalu masukkan enam angka; akun password menggunakan
username/email dan kata sandi. Nama akun setelah login harus sesuai orang yang bekerja.

Kasir melihat antrean **Aktif** pada mobile atau **Pesanan Aktif** pada web. Cari
nomor pesanan, nama pelanggan atau nama menu. Pilih nomor yang cocok dan periksa
detail sebelum bertindak. Tombol refresh memperbarui data jika koneksi sempat putus.

| Langkah | Web | Mobile |
| --- | --- | --- |
| Buka pemeriksaan item | **Cek menu / revisi** | **Proses Pemesanan** atau **Ubah tinjauan pesanan** |
| Simpan hasil pemeriksaan | **Menu tersedia dan pelanggan setuju — Simpan** | **Konfirmasi Pemesanan** |
| Mulai penanganan POS | **Tangani pesanan ini** | **Tangani pesanan ini** |
| Catat proses POS selesai | **Sudah masuk aplikasi kasir** | **Sudah masuk aplikasi kasir** |

### Memproses satu pesanan

1. Cocokkan nomor dan nama pelanggan.
2. Buka pemeriksaan item menggunakan tombol pada tabel di atas.
3. Pastikan ketersediaan dengan pelanggan. Revisi jumlah, varian, tambahan atau
   catatan bila perlu. Satu pilihan wajib untuk setiap kelompok varian tersedia.
4. Simpan hasil review. Ini belum berarti pembayaran atau input POS selesai.
5. Tekan **Tangani pesanan ini** sebelum batas waktu habis. Nama Anda menjadi
   penanggung jawab dan hitung mundur berhenti. Item dibekukan untuk input POS.
6. **Periksa apakah pesanan sudah ada di POS**, khususnya setelah koneksi terputus.
   Masukkan item secara manual hanya jika belum ada.
7. Selesaikan pembayaran di POS. Berikan struk dan nomor meja sesuai prosedur restoran.
8. Masukkan referensi/nomor transaksi POS bila tersedia (maksimal 80 karakter).
9. Centang kedua pernyataan: semua menu sudah diinput dan pembayaran sudah selesai
   pada POS. Jangan mencentang sebelum benar-benar dilakukan.
10. Tekan **Sudah masuk aplikasi kasir**, periksa dialog, lalu konfirmasi.
    Pesanan masuk Riwayat.

### Status yang perlu dipahami

| Tampilan/status | Arti dan tindakan |
| --- | --- |
| Menunggu / Perlu ditinjau (`pending`) | Review dan datang ke kasir sebelum 15 menit |
| Siap ditangani | Pending yang sudah direview; lanjutkan claim sebelum expired |
| Ditangani kasir (`pos_input`) | Satu kasir menjadi penanggung jawab input/pembayaran POS |
| Masuk aplikasi kasir (`forwarded`) | Konfirmasi manual selesai input/pembayaran POS tercatat |
| Kedaluwarsa (`expired`) | Batas pending habis; periksa POS sebelum membuat ulang |
| Dibatalkan (`cancelled`) | Tidak dilanjutkan; hubungi pengelola untuk alasan/rekonsiliasi |
| Terkonfirmasi / Selesai lama | Riwayat pembayaran web terdahulu, bukan alur order baru |

Revisi tidak menambah 15 menit. “Siap ditangani” tidak berarti makanan siap.
Konfirmasi aplikasi ini tidak memverifikasi transaksi POS secara otomatis.

### Jika dua kasir membuka order yang sama

Hanya satu orang bisa mengambil penanganan. Jika nama kasir lain tampil, jangan
input ulang. Hubungi kasir tersebut. Admin/superadmin dapat mengambil alih setelah
memeriksa POS, mengisi alasan 5–200 karakter, lalu mengonfirmasi. Penanggung jawab
lama tidak bisa menyelesaikan handoff setelah dialihkan.

### Riwayat dan pesan ulang

Tab **Riwayat** menyimpan forwarded, expired, cancelled dan transaksi lama. Filter
tanggal mobile menggunakan tanggal **pembuatan order dalam WIB**. Laporan admin
handoff menggunakan waktu **konfirmasi masuk POS**, sehingga hitungan hari bisa berbeda.

Untuk expired, web menyediakan **Buat ulang pesanan** dan mobile **Buat draf
pesanan ulang**. Periksa POS dahulu, muat menu terbaru, lalu konfirmasi draft.
Order baru mempunyai nomor dan batas waktu baru; order lama tetap expired.

### Hasil pengiriman belum pasti

| Kejadian | Tindakan |
| --- | --- |
| Timeout setelah input/pembayaran POS | Periksa POS, muat ulang status, jangan input atau meminta pembayaran ulang |
| Banner konfirmasi POS belum pasti pada mobile | Gunakan **Coba lagi pesanan tersimpan**; percobaan memakai referensi yang sama |
| Banner reorder belum pasti | Retry percobaan tersimpan; jangan membuat draft kedua |
| Detail belum terverifikasi | Tekan refresh detail dan tunggu tombol aktif; jangan memakai informasi lama |
| Versi berubah / ditangani orang lain | Muat ulang, cocokkan penanggung jawab dan isi order |

Jika tetap gagal, catat nomor order dan waktu, lalu hubungi admin. Jangan menghapus
data aplikasi atau uninstall ketika masih ada percobaan tersimpan yang belum jelas.

## Admin: katalog

Masuk melalui `/admin/login` dengan username/email dan password. Buka **Kategori**,
**Produk**, atau **Add-on** sesuai pekerjaan.

1. Pada Kategori, gunakan **Tambah**, isi nama, lalu **Simpan**. Tombol naik/turun
   mengatur urutan. Kategori nonaktif menyembunyikan produk di dalamnya.
2. Pada Produk, tekan **Tambah**, isi nama, kategori, harga rupiah, deskripsi dan
   foto bila ada. Atur varian/tambahan dan flag **Tersedia**, **Best Seller**,
   **Baru**, **Rekomendasi** sesuai kebutuhan, lalu simpan.
3. Harga published harus rupiah utuh di atas nol. Untuk harga yang belum siap,
   matikan **Tersedia** dan simpan draft; jangan menebak harga.
4. Add-on dibuat pada menu Add-on lalu dikaitkan pada produk yang relevan.
5. Periksa hasil pada menu customer. Refresh bila katalog masih menampilkan cache lama.

Utamakan menonaktifkan produk yang habis. Penghapusan dapat ditolak bila data masih
dirujuk transaksi/relasi. Pesanan lama tetap memiliki nama/harga snapshot saat transaksi.
Mengubah katalog tidak mengedit order historis atau POS restoran.

## Admin/superadmin: staf

1. Buka **Kelola staf** → **Tambah staf**.
2. Isi nama lengkap, username unik, email unik, serta PIN kasir enam angka atau
   password admin 12–128 karakter beserta konfirmasi. Foto opsional.
3. Superadmin dapat memilih Admin/Kasir. Admin hanya dapat mengelola Kasir.
4. Tekan **Buat akun**, tunggu hasil, lalu periksa status **Aktif** sebelum
   menyerahkan kredensial secara privat.

Gunakan **Atur PIN/password** untuk pemulihan akses, **Nonaktifkan** untuk staf
yang berhenti bekerja, dan **Arsipkan** untuk mengeluarkannya dari daftar aktif.
Arsip mempertahankan riwayat. **Pulihkan akun** mengembalikan status nonaktif;
atur PIN/password baru untuk mengaktifkannya. Akun tidak boleh menonaktifkan dirinya.

Status **Pengaturan belum selesai** berarti langkah Auth belum tuntas. Muat ulang
dan selesaikan pengaturan akun, jangan membuat akun duplikat. Mengubah email/peran
memerlukan kredensial baru; sesi lama dicabut. Superadmin tidak dibuat dari form ini.

## Admin/superadmin: laporan

Buka **Laporan pesanan**, pilih **Pesanan self-order** atau **Riwayat pembayaran
web lama**. Pilih tanggal (maksimal 31 hari) dan kasir, tekan **Tampilkan**.
**Ekspor semua CSV** mengikuti filter yang sudah diterapkan.

Nilai self-order adalah estimasi pesanan diteruskan menurut konfirmasi manual.
Jangan menjumlahkannya dengan revenue POS. Riwayat pembayaran web lama dan
struk historis hanya untuk rekonsiliasi data lama.

## Superadmin: operasional dan aktivitas

Pengaturan hanya untuk superadmin:

1. Buka **Pengaturan operasional**.
2. Periksa nama restoran, tagline, pajak dan service. Keduanya dihitung dari
   subtotal masing-masing; cocokkan estimasi dengan kebijakan restoran.
3. Atur **Nama pelanggan wajib diisi** dan **Terima pesanan baru**.
4. Baca contoh total, centang persetujuan, lalu **Konfirmasi & simpan**.

Minimal satu kasir pribadi aktif diperlukan sebelum penerimaan order dibuka.
Menutup penerimaan tidak menghapus order yang sudah ada. Bagian **Backup &
pemulihan** menampilkan bukti terakhir; minta operator memeriksa job jika data lama
atau gagal. Tombol **Bersihkan foto tak terpakai** hanya untuk unggahan yang tidak
dirujuk setelah masa tunggu, bukan untuk menghapus foto katalog aktif.

Halaman **Log aktivitas** hanya untuk superadmin: filter tanggal/staf/jenis aksi
untuk menelusuri perubahan dan penanggung jawab. Jangan memakai log untuk menyimpan PIN.

## Perangkat mobile dan notifikasi

Izinkan notifikasi, pastikan status pemantauan siap, lalu tekan Home jika perlu
memakai POS di aplikasi lain. Pengaturan **Suara pesanan baru** juga mengikuti
volume/silent/DND perangkat. Jika izin sebelumnya ditolak, gunakan **Periksa izin
notifikasi** atau Setelan Android → Aplikasi → TerasKayuManis Kasir → Notifikasi.

Pemantauan latar mempunyai batas waktu. Android/OEM, hemat baterai, force-stop atau
reboot dapat menghentikannya. Jika perlu, pengelola perangkat menyesuaikan battery
policy setelah uji. Buka kembali aplikasi untuk memperbarui pemantauan dan antrean.
Notifikasi membantu perhatian; **antrean dan status terbaru tetap harus diperiksa**.

Menu **Diagnostik** menyediakan ringkasan koneksi versi aplikasi yang dapat disalin
untuk pengelola. Jangan mengirim screenshot berisi data pribadi pelanggan ke publik.

## Membuka dan menutup shift

Sebelum layanan: login akun yang benar, refresh antrean, periksa katalog/harga,
POS dan koneksi. Uji sintetis hanya pada lingkungan staging yang disediakan pengelola.
Saat penutupan: cocokkan order yang sedang ditangani dengan POS, selesaikan hasil
yang belum pasti, lalu **Keluar**. Serahkan perangkat bersama pada layar login.

Jika layanan internet/aplikasi bermasalah, koordinasikan dengan pengelola dan
lanjutkan prosedur restoran melalui POS. Jangan mencatat konfirmasi selesai untuk
transaksi yang belum benar-benar dilakukan.
