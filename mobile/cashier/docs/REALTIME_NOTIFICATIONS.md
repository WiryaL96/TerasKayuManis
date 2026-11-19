# Sinkronisasi dan notifikasi mobile 0.2.0

Default compile-time `SYNC_MODE=polling`, sesuai Vercel. Set `websocket` hanya
untuk runtime Go persisten dengan Origin/WSS yang dikonfigurasi. Snapshot REST
tetap otoritatif; event tidak mengubah status bisnis.

## Foreground

Polling setiap lima detik memeriksa `admin/sync`: revision, UUID checkout baru
15 menit terakhir (maksimal 1000), dan overflow. Cache enam query mengambil full
list hanya saat revision/query berubah, force refresh, atau rekonsiliasi 60 detik.
Request diserialisasi, timeout dibatalkan, 429/backoff dihormati. Filter history
berdasarkan tanggal dikerjakan server dalam WIB.

Baseline order baru terpisah dari tab/filter/page. Snapshot pertama seed tanpa
bunyi; history tetap menerima alert checkout baru. WSS event hanya memicu resync
sehingga satu order tidak dibunyikan dua kali melalui jalur polling dan WSS.
Satu chime agregat diputar per burst, tidak antre tanpa batas. Preferensi suara
disimpan lokal dan diteruskan ke native. Silent/DND perangkat tetap dihormati.

Server lama yang hanya mengirim `{revision}` memakai polling antrean aktif
terbaru tanpa filter untuk suara foreground, termasuk saat membuka Riwayat,
search, sort atau halaman lain. Snapshot awal tidak berbunyi; ID dan waktu
pembuatan membedakan pesanan baru dari update/reappearance pesanan lama.
Snapshot antrean digunakan ulang bila query cocok; read tambahan tetap mengikuti
revision/force/reconcile dan batas 100 pesanan terbaru. Pesanan yang sudah keluar
dari antrean sebelum poll dapat terlewat. Pemantauan latar tetap membutuhkan
feed/lease server; feed yang kembali tersedia disemai ulang tanpa membunyikan
pesanan lama. Field feed yang hadir tetapi invalid tetap error sinkronisasi.

Toggle suara dapat diaktifkan pada kedua format server. ON memutar contoh bunyi,
OFF menghentikan pemutar, dan pilihan disimpan lokal. Bunyi baru hanya diputar
ketika aplikasi foreground dan toggle ON; volume notifikasi/silent/DND tetap
mengikuti perangkat.

## Background Android

Sebelum pause, aplikasi yang masih terlihat meminta permission dan menyiapkan
lease lewat `POST admin/watch`. Lease hanya mengizinkan `GET/DELETE admin/watch`,
terikat staff/session_version dan expiry 5 jam 30 menit. Tidak ada refresh/access
token Supabase di Kotlin, Intent, preferences, atau log. Hash lease tersimpan DB;
native memakai AES-GCM/Android Keystore. Salinan preferences lama dihapus saat
startup/stop. Satu pemilik rotasi refresh token tetap SDK Flutter.

Native memegang satu poll, menjadwalkan request berikut setelah selesai, memakai
wake lock terbatas hanya selama I/O, deadline HTTP total 16 detik, batas response
128 KiB, no redirects, retry
berjitter, Retry-After, dan penghentian pada 401/403/expiry. Generation fence
mencegah respons lama menulis/berbunyi setelah logout. Queue revoke bounded.

Resume menghentikan native, membawa baseline UUID yang sudah diumumkan, lalu
menyegarkan snapshot dan lease. Logout menghapus data lokal sebelum revoke
best-effort; perangkat offline tidak dapat menjamin revoke server instan, tetapi
lease tidak dapat mengakses detail atau mutasi dan memiliki TTL.

Android 15+ membatasi dataSync background service. `onTimeout` menghentikannya;
UI menunjukkan status/masa pemantauan. FCM tidak diprovision pada pekerjaan ini.
Force-stop, OEM battery policy, reboot, permission ditolak, atau lease habis
dapat menghentikan notifikasi; buka kembali aplikasi untuk memperbarui pemantauan.
Tidak ada janji delivery tepat dua detik atau operasi background tanpa batas.

## Bukti yang diperlukan pada device

- Permission allow/deny/revoke, silent/DND, sound toggle foreground/background.
- 100 pause/resume, pergantian akun, logout offline, proses dibunuh setelah POST.
- Lease expiry, Android 15/16 dataSync timeout, Wi-Fi/data putus dan 429.
- Tidak ada token Supabase atau UUID/nama/order body di log native.
- Keystore: `android/app/src/androidTest/.../WatchVaultTest.kt`.
- Jank benchmark dan battery/thermal soak: [TESTING_RELEASE](TESTING_RELEASE.md).

[Android service timeout](https://developer.android.com/develop/background-work/services/fgs/timeout)
dan [Supabase session semantics](https://supabase.com/docs/guides/auth/sessions).
