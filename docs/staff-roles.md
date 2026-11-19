# Tiga peran staf

Peran operasional yang berlaku hanya `superadmin`, `admin`, dan `cashier`
(label UI **Kasir**). Semua staf memakai akun pribadi dengan nama dan email.
Tidak ada registrasi publik atau pilihan identitas kasir saat pembayaran.

| Kemampuan | Superadmin | Admin | Kasir |
| --- | --- | --- | --- |
| Review, claim/forward POS, dan baca struk web historis | Ya | Ya | Ya |
| Katalog dan laporan | Ya | Ya | Tidak |
| Membuat, menonaktifkan, memulihkan akun kasir | Ya | Ya | Tidak |
| Membuat, menonaktifkan, memulihkan akun admin | Ya | Tidak | Tidak |
| Log aktivitas semua staf | Ya | Tidak | Tidak |
| Pengaturan, persetujuan tarif, status backup | Ya | Tidak | Tidak |
| Membuat atau menaikkan akun menjadi superadmin melalui web | Tidak | Tidak | Tidak |

Admin/superadmin login melalui `/admin/login`, kasir melalui `/cashier`.
Pembatasan diterapkan pada middleware UI, API Nuxt/Go dan fungsi transaksi SQL.
Menyembunyikan navigasi bukan satu-satunya pengamanan. Status aktif dan versi
sesi diperiksa kembali; menonaktifkan akun mencabut sesi refresh dan menolak
token lama. Akun tidak dapat menonaktifkan dirinya melalui pengelolaan staf.

## Pembuatan dan pemulihan

Superadmin memilih Admin/Kasir pada halaman Staf. Admin hanya dapat membuat
kasir. Form wajib berisi nama, username unik (3–32 karakter), email unik dan
PIN 6 angka untuk kasir atau password 12–128 karakter untuk admin, beserta
konfirmasi. Akun langsung `active` setelah
password berhasil disimpan di Supabase Auth. Tidak ada email atau tautan aktivasi
untuk akun staf. Login menerima username tanpa membedakan huruf besar/kecil atau
email; akun lama yang belum punya username tetap dapat login dengan email.

Atur password dan aktifkan kembali dilakukan langsung melalui form Staf.
Operasi ini mencabut sesi lama, menaikkan versi sesi dan mencatat pelaku di Log
aktivitas superadmin. Password tidak masuk audit, respons API atau cache.
`invited` hanya menandai pengaturan yang belum selesai; akun tersebut belum boleh
bekerja. Bila jaringan gagal, muat ulang daftar dan selesaikan dengan Atur password.
Dengan migrasi `0018`, superadmin dapat mengubah peran admin/kasir pada Edit akun;
admin tetap hanya dapat mengelola kasir. Perubahan memerlukan kredensial baru,
mencabut sesi, dan menunggu sinkronisasi Auth sebelum akun aktif. Jika edit belum
selesai, buka Edit akun dan simpan kembali; jangan membuat akun duplikat.

Superadmin pertama dibuat operator melalui `scripts/bootstrap-superadmin.mjs`
sesuai [runbook](production-readiness.md). Bootstrap dibatasi pada akun pertama;
tautan ulang hanya untuk UUID superadmin yang sama dan masih `invited`.
Pemulihan superadmin yang sudah aktif memerlukan prosedur operator privat dan
verifikasi pemilik, bukan akun admin atau halaman registrasi.

## Migrasi instalasi lama

Terapkan `0011_three_staff_roles.sql` setelah `0010`, dalam satu transaksi sebagai
pemilik database, sesudah backup dan di luar jam buka. Migrasi menjeda pesanan baru.

- `owner` menjadi `superadmin`; `manager` menjadi `admin`. Sesi lama dicabut,
  versi sesi naik, dan akun harus diaktivasi kembali. Akun yang sudah nonaktif
  tetap nonaktif.
- `kitchen` lama menjadi kasir **nonaktif** untuk pemeriksaan operator.
- `admin` lama tetap admin, tidak otomatis menjadi superadmin.
- Lebih dari satu owner lama atau role tidak dikenal membuat migrasi berhenti
  untuk diperiksa operator. Jangan menebak siapa pemiliknya.
- Snapshot nama/peran pada struk dan audit historis tidak ditulis ulang. Migrasi
  role menghasilkan catatan audit tersendiri.

Untuk owner yang dimigrasikan, operator memeriksa nama/email asli dan kecocokan
identitas Auth sebelum menjalankan bootstrap dengan `--resume-id`. Jika belum
ada superadmin, gunakan bootstrap baru. Akun aktif lain tidak boleh diadopsi.
Aktivasi ulang admin yang dimigrasikan dilakukan superadmin melalui Staf.

Jalankan SQL `three_roles_migration.sql` dan `three_staff_roles.sql`, tes Go,
serta tes integrasi Auth/Playwright sebelum deploy. Tes menggunakan database
disposable; kelulusannya tidak berarti migrasi production sudah diterapkan.

## Migrasi akun langsung

Terapkan `0012_direct_staff_accounts.sql` setelah `0011` dan backup. Migrasi
menambah username nullable dan RPC pengaturan password yang hanya dapat dipanggil
server. Password/status akun lama dan transaksi historis tidak diubah. Jalankan
`backend/tests/direct_staff.sql` hanya pada database disposable. Endpoint tautan
staf lama mengembalikan HTTP 410; bootstrap superadmin tetap prosedur operator.

## Akses kasir dengan PIN

Migrasi `0013_cashier_pin.sql` menambah PIN per kasir dan foto profil. Pada form
Staf, Kasir memakai PIN 6 angka beserta konfirmasi; Admin tetap memakai password.
Nama, username dan email tetap menyimpan identitas akun. Pengaturan PIN mencabut
sesi lama, dan pengaturan password lewat API kompatibilitas mematikan mode PIN.
Akun lama tetap dapat login seperti sebelumnya sampai admin mengatur PIN.

`/cashier` memakai dropdown nama kasir, pratinjau foto akun terpilih, kolom PIN
biasa, serta pergantian kasir melalui
Keluar. Sesuai pilihan owner, daftar nama dan foto kasir aktif dapat dibuka dari
perangkat mana saja. Email, username, PIN dan data internal tidak dikirim dalam
daftar publik ini. Foto tanpa berkas memakai inisial, bukan foto orang contoh.
Foto disimpan pada bucket privat `staff-photos`; API hanya menyajikan foto kasir
aktif yang memiliki PIN. Unggahan diperiksa, dibatasi 2 MB, dan dikodekan ulang
menjadi WebP maksimal 512 piksel tanpa metadata.

Server membutuhkan `NUXT_CASHIER_PIN_SECRET` privat, acak, stabil, minimal 32
karakter. Simpan bersama backup konfigurasi privat. Jangan menaruh nilainya di
Git atau chat. PIN diubah menjadi kredensial Auth dengan HMAC berlabel dan UUID
akun; Auth menyimpan hash kredensial tersebut. PIN asli tidak disimpan di profil,
cache, audit atau respons API. Hilangnya/pergantian secret membutuhkan pengaturan
ulang PIN; jangan menghasilkan secret baru setiap aplikasi restart.

Setiap akun mendapat maksimal 5 percobaan sebelum pembatasan 15 menit. Budget
berada di PostgreSQL sehingga pergantian IP, perangkat atau restart frontend
tidak menghapusnya. Login berhasil atau pengaturan PIN oleh admin mereset budget.
Verifikasi status, versi sesi dan identitas akun tetap berlaku pada penanganan order.
Tes SQL `cashier_pin.sql` hanya untuk database disposable.

## Edit, arsip dan pemulihan (migrasi 0018–0019)

Edit akun mengubah nama, username, email dan peran sesuai kewenangan. Kasir wajib
PIN baru enam angka; admin wajib password baru minimal 12 karakter. Akun yang
sebelumnya nonaktif tetap nonaktif setelah edit selesai. Tidak ada peningkatan
menjadi superadmin melalui form atau API.

Arsipkan memakai `DELETE /api/admin/staff/{id}` sebagai penghapusan logis: sesi
langsung dicabut dan referensi transaksi tetap disimpan. Filter Arsip menampilkan
akun tersebut. Pulihkan akun mengembalikannya dalam status nonaktif; atur PIN atau
password untuk mengaktifkan lagi. Username/email arsip tetap dicadangkan agar
identitas historis tidak diambil orang lain.

Setelah login PIN berhasil, browser menerima cookie perangkat bertanda tangan,
HttpOnly, SameSite Strict, dan Secure pada HTTPS, berlaku 30 hari. Percobaan dari
perangkat asing tidak menghabiskan budget browser yang sudah dikenal. Browser
terpercaya tetap dibatasi lima percobaan per 15 menit. Versi sesi mengikat cookie;
reset PIN/perubahan akun membatalkan kepercayaan lama. Perangkat baru tetap dapat
login dari mana saja, tetapi dapat terkena batas akun jika ada serangan pada saat
login pertama. Admin dapat mereset PIN untuk pemulihan. PIN enam digit tetap perlu
pemantauan dan perlindungan jaringan; cookie bukan pembebasan rate limit.

Foto tak terpakai minimal 24 jam dibersihkan dalam batch maksimal 20, saat ada
unggahan berikutnya atau lewat tombol superadmin pada Pengaturan. Foto dengan
referensi produk/profil dilindungi oleh trigger dan lock database. Tombstone
menolak form lama yang mencoba melampirkan file yang sudah dihapus. Ini pembersihan
bertahap saat aplikasi digunakan, bukan cron cloud yang diklaim sudah terpasang.
