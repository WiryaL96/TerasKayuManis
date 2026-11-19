# TerasKayuManis Kasir — Flutter

Antarmuka kasir Android untuk review, claim, dan konfirmasi input/pembayaran manual
di POS. Fitur lengkap versi source `0.2.0+2` membutuhkan migrasi database **0020**
serta Go/BFF terbaru. Server dengan sync `{revision}` tetap mendukung login,
polling antrean dan suara pesanan baru saat aplikasi terbuka. UI menjelaskan
keterbatasan pemantauan latar pada server tersebut. Respons
feed yang rusak tetap ditolak. [Panduan penggunaan](../../docs/panduan-penggunaan.md) untuk operator;
[audit pra-production](../../docs/audit-production.md) untuk status verifikasi.

## Setup pengembang

Pin Flutter **3.47.4 / Dart 3.13.3**, JDK17+, Android SDK36. Gunakan SDK yang sama
dengan `.fvmrc` dan CI. Jangan mengganti lockfile menggunakan SDK lain.

```sh
git switch main
# Dari mobile/cashier
flutter --version
flutter doctor -v
flutter pub get --enforce-lockfile
```

Salin `config/preview.example.json` ke `config/preview.json` (gitignored). Contoh
menunjuk alamat produksi sebagai referensi: **ganti seluruh URL dengan staging**
untuk development/test. Isi hanya Supabase publishable/anon key. Email/password,
PIN, service key dan database URL tidak masuk compile-time defines.

```sh
flutter analyze
flutter test --concurrency=1
flutter run --profile --dart-define-from-file=config/preview.json
```

Tanpa konfigurasi valid, app menampilkan petunjuk setup. Config compile-time
memerlukan rebuild; hot reload tidak mengganti defines. Default sync polling
sesuai Vercel; WSS hanya untuk backend persisten yang mendukungnya.

## Dokumen teknis

- [DEVELOPMENT](docs/DEVELOPMENT.md): state, storage dan aturan async.
- [API_CONTRACT](docs/API_CONTRACT.md): auth, endpoint, sync, lease dan retry.
- [REALTIME_NOTIFICATIONS](docs/REALTIME_NOTIFICATIONS.md): lifecycle/notifikasi.
- [TESTING_RELEASE](docs/TESTING_RELEASE.md): build, device, signing dan benchmark.
- [Runner benchmark](perf_harness/README.md): fixture 100 order × 50 item.

## Endpoint dan deployment

Client REST menggunakan `/api/core/` pada domain frontend; Nitro meneruskan ke
Go `/api/v1/`. API staf menggunakan Bearer, bukan akses update tabel Supabase.
Native watcher hanya menerima lease baca terbatas. Refresh token tetap dikelola
Flutter dan disimpan secure storage.

Signing produksi disediakan owner melalui `android/key.properties`; tidak ada
fallback ke debug key pada release. APK unsigned tidak dapat dipasang. Upgrade
memerlukan certificate yang sama dengan APK terpasang; jangan uninstall perangkat
operasional hanya untuk melewati mismatch signature karena data lokal dapat hilang.

Source ini belum membuktikan FPS, battery/OEM, Keystore perangkat, iOS, atau hosted
staging. Runbook utama: [production readiness](../../docs/production-readiness.md).
Tidak ada instalasi, deployment atau transaksi production otomatis dari test.
