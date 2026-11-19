# Backup database dan media

## Jalur budget: artifact private GitHub terenkripsi

Workflow `.github/workflows/backup.yml` memakai `artifact_backup.py`. Database
dan objek Storage diekspor melalui snapshot yang sama, dikemas, lalu dienkripsi
dengan **age X25519 sebelum upload**. Hanya public recipient di runner; identity
dekripsi tidak dikirim ke GitHub. Tidak ada dump/manifest/media mentah di artifact.
Retensi artifact 30 hari; jadwal 03.00 WIB dapat terlambat mengikuti antrean GitHub.
Keberhasilan baru dicatat ke dashboard setelah server GitHub menerima artifact.
Kegagalan mempertahankan waktu keberhasilan dan bukti restore sebelumnya.

Aktivasi memerlukan:

- Workflow tersedia pada branch default `main`, yang sejak konsolidasi 16 November
  juga memuat source aplikasi terbaru. Auto-deploy Vercel `main` tetap dinonaktifkan.
  Worker backup tetap checkout SHA immutable `BACKUP_SOURCE_REF` yang telah diuji;
  penggabungan branch tidak otomatis mengganti versi worker atau menjalankan backup.
- Repository variable `BACKUP_SOURCE_REF` adalah SHA kode backup yang sudah diuji,
  bukan nama branch yang dapat bergerak. `BACKUP_AGE_RECIPIENT` hanya public key.
- Secret `BACKUP_DATABASE_URL`, `BACKUP_SUPABASE_URL`, dan
  `BACKUP_SUPABASE_SERVICE_ROLE_KEY`. Kredensial tidak pernah dimasukkan ke log.
- Login DB backup dengan SELECT saja, default transaksi read-only dan tanpa izin
  INSERT/UPDATE/DELETE. Akses role untuk schema Auth terkelola harus disetujui
  operator; jangan otomatis memperluas role ketika pemeriksaan izin gagal.
- TLS DB memakai `verify-full` dengan CA Supabase resmi. `supabase-root.crt`
  berasal dari `https://supabase-downloads.s3-ap-southeast-1.amazonaws.com/prod/ssl/prod-ca-2021.crt`,
  SHA256 `700723581420dd1ac98fd7e9ac529f0ef210eadcaf87fc868a3ad7d114c2f3b7`,
  berlaku sampai 26 April 2031. Perbarui melalui sumber resmi sebelum kedaluwarsa.

Kuota gratis dibatasi secara sengaja: maksimal 2 MiB per archive, 80 MiB artifact
backup aktif dan 450 MiB seluruh artifact repository. Preflight menolak ekspor
baru ketika tidak cukup ruang; artifact CI lain tidak dihapus. Batas ini khusus
instalasi kecil, bukan solusi penyimpanan katalog besar. Kuota Actions/storage
akun di repository lain tetap perlu dipantau. Naikkan penyimpanan ke bucket
privat khusus sebelum media tumbuh melampaui batas; jangan menghapus media
restoran agar job backup menjadi hijau.

Kunci pemulihan harus disalin owner ke penyimpanan aman terpisah dari laptop.
Tanpa identity age, artifact terenkripsi tidak bisa dipulihkan. Uji restore nyata
dari artifact yang sudah diunduh sebelum mengisi `restore_verified_at` di production:

```sh
python deploy/backup/artifact_backup.py restore --archive /private/backup.age \
  --identity /private/identity.txt --project PROJECT_REF \
  --media-dir /private/new-empty-restored-media
```

`RESTORE_DATABASE_URL` wajib baru, localhost, dan bernama `tkm_restore_*`.
Restore memverifikasi checksum, jumlah baris, ledger, akun Auth dan inventaris
Storage, kemudian menonaktifkan order dan sesi login pada clone. Hasil lokal
tidak boleh disamakan dengan verifikasi artifact offsite.

## Jalur S3 untuk kapasitas lebih besar

`backup.py` mengambil snapshot database yang sama untuk `pg_dump`, inventaris
Storage dan jumlah baris/ledger. Dump mencakup schema `public`, `tkm`, `auth`,
`storage`. File Storage disalin terpisah melalui API terautentikasi; nama file lokal
dan S3 di-hash agar path asli tidak menjadi path filesystem. Manifest beserta
checksum diunggah paling akhir. Perubahan/hilangnya media selama backup membuat
run gagal. File parsial tetap terkena lifecycle.

## Provisioning (akun AWS restoran)

1. Deploy `s3-stack.yaml` melalui CloudFormation di akun restoran dengan bucket
   unik. Template memblokir semua akses publik, menolak HTTP dan unggahan tanpa
   AES256, dan lifecycle 30 hari. Setiap run memakai prefix unik tanpa menimpa
   backup sebelumnya; gunakan bucket baru tanpa versioning agar objek kedaluwarsa
   tidak tertahan sebagai versi noncurrent. Bucket dipertahankan saat stack dihapus.
2. Pasangkan instance profile hasil stack ke EC2 restoran. Jangan mengganti IAM
   role existing tanpa menggabungkan izin yang masih diperlukan. Role hanya
   memvalidasi konfigurasi bucket serta Put/Get pada `backups/*`; tidak mendapat
   DeleteObject, ListAllMyBuckets atau akses bucket lain. Batasi akses restore ke
   operator yang ditunjuk. Gunakan IMDSv2 pada EC2.
3. Buat login DB backup terpisah melalui operator database: read-only untuk
   `public`, `tkm`, `auth`, `storage`, akses sequence dan kemampuan dump tanpa
   terhalang RLS (`BYPASSRLS` khusus backup bila diperlukan). Jangan memberi hak
   tulis/DDL. Gunakan session pooler/direct DB dan TLS verify-full, bukan
   transaction pooler. Kredensial hanya di EnvironmentFile `0600`.
4. Pasang Python venv, dependency `requirements.txt` dan PostgreSQL client dengan
   major yang sama/lebih baru dari server. Simpan script/venv di `/opt/tkm-backup`
   milik root, tak dapat ditulis runner/web. Buat user sistem `tkm-backup` dan
   izinkan group `tkm-web` membaca status. Salin `backup.env.example` ke
   `/etc/teraskayumanis/backup.env`, root:root `0600`, isi secara privat.
5. Pasang unit `tkm-backup.service`/`.timer`, `systemctl daemon-reload`, lalu
   `systemctl start tkm-backup.service` untuk run pertama. Setelah berhasil dan
   restore teruji, `systemctl enable --now tkm-backup.timer`. Periksa
   `systemctl list-timers tkm-backup.timer`; jadwal **03.00 Asia/Jakarta**,
   Persistent=true mengejar jadwal yang terlewat saat host mati.
6. `/var/lib/teraskayumanis-backups/status.json` ditulis atomik `0640` oleh user
   backup/group web, direktori `0750`. Owner/admin melihat waktu backup berhasil,
   hasil terakhir dan bukti restore melalui Pengaturan. Kegagalan mempertahankan
   waktu sukses terakhir dan mengembalikan exit code nonzero. Tidak ada link,
   password, secret SDK atau error sensitif di journald/status publik.

## Restore drill terisolasi

Gunakan host uji terpisah. Database target harus baru/kosong, di `127.0.0.1`,
`localhost`, atau `::1`, dengan nama `tkm_restore_*`. Jangan gunakan port forward
ke production. Pastikan dependency extensions/type Supabase sumber tersedia pada
lingkungan uji jika dump Auth/Storage production memerlukannya. Sesi/Auth link
hasil clone dicabut dan order baru dinonaktifkan pada schema yang mendukungnya.

Siapkan `RESTORE_DATABASE_URL` secara privat dan akses baca S3, lalu:

```sh
python restore_drill.py --prefix backups/TIMESTAMP-ID/ \
  --project PROJECT_REF_SUMBER --media-dir /private/new-empty-restored-media
```

Target tidak pernah ditimpa. Schema `public` default yang kosong dihapus tanpa
CASCADE agar dapat dibuat kembali; objek existing membuatnya gagal. Seluruh hash
dump/media, jumlah baris orders/payments/items/profiles, jumlah ledger serta
hubungan total/kembalian diperiksa. Media tersimpan dengan nama hash; manifest
memetakan hash ke bucket/path/content type asli untuk pemulihan Storage ke proyek
terisolasi. Simpan manifest privat dan uji pemetaan/akses media pada staging.
Untuk aktivasi hasil recovery, provision ulang ACL login aplikasi secara terkontrol
dan gunakan revision kode yang tercatat; dump memakai no-owner/no-acl.

`RESTORE_STATUS_PATH` boleh diarahkan ke status owner **hanya setelah drill nyata
ini benar-benar berhasil**. Bukti tes sintetis tidak boleh ditulis ke status
production. Restore tidak mengaktifkan pemesanan atau mengganti DNS.

## Pengujian lokal / CI

```sh
python -m unittest deploy.backup.test_backup
# Dari root repo; DB localhost harus disposable bernama tkm_operations atau
# teraskayumanis_test, dengan semua migrasi dan PostgreSQL tools di PATH.
BACKUP_TEST_DATABASE_URL=PRIVATE_LOCAL_TEST_DSN \
  python -m unittest deploy.backup.test_restore_integration
```

Integration benar-benar menjalankan pg_dump/pg_restore ke database lain,
memulihkan media dan menolak media korup. Transport S3 dan download Storage adalah
fixture sintetis; pengujian tidak menghubungi Supabase/AWS production.

Rujukan: [backup Supabase tidak mencakup objek Storage](https://supabase.com/docs/guides/platform/backups),
[S3 Lifecycle](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lifecycle-mgmt.html).
