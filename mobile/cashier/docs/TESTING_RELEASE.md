# Testing dan release mobile 0.2.0

Flutter 3.47.4/Dart 3.13.3 sesuai `.fvmrc`, JDK17+ yang kompatibel AGP,
Android SDK36. Dependency memakai lockfile. Jangan menjalankan Flutter build
debug/profile/release/integration secara bersamaan: registrant plugin dibuat
ulang berdasarkan mode. Selalu gunakan perintah Flutter sebelum Gradle native
agar metadata plugin sesuai target.

## Pemeriksaan lokal/CI

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test audit
flutter analyze
flutter test --concurrency=1
flutter build apk --debug --target=lib/main_demo.dart
python audit/native_watch_probe.py
flutter build apk --release --target=lib/main_demo.dart --target-platform=android-arm64
```

Regresi audit masuk suite utama melalui `test/audit_regressions_test.dart`.
Tes Kotlin JVM memeriksa single-flight, stop, dan generation. Tes Keystore nyata:
`android/gradlew :app:connectedDebugAndroidTest` pada perangkat uji (set JAVA_HOME).
Perintah root `python scripts/validate-mobile-db.py` membuat PostgreSQL disposable,
menerapkan migrasi, SQL security/flow dan Go integration, lalu menghapus container
yang dibuatnya. Tidak membaca .env atau database restoran.

## Profiling dan soak perangkat

```sh
cd perf_harness
flutter pub get --enforce-lockfile
flutter drive --profile --driver=test_driver/performance_driver.dart \
  --target=integration_test/performance_test.dart -d <android-device>
python ../scripts/device_soak.py --serial <android-device> --hours 6 \
  --output /private/new-device-soak.jsonl
```

Benchmark fixture 100 order × 50 item mengukur UI/raster p95/p99 dan jank sesuai
refresh rate layar. Harness memakai application ID dan dependency terpisah agar
plugin `integration_test` tidak masuk aplikasi kasir produksi. Benchmark memiliki
lockfile tersendiri; catat juga versi plugin native saat membandingkan hasil.
Target awal <1% jank; 60 Hz berarti budget 16,67 ms per frame,
120 Hz 8,33 ms. Trace dan hasil integration driver berada di build artifact.
Laporkan model/SoC/RAM, Android, mode build dan dataset. Widget test desktop
tidak membuktikan FPS APK. Soak mengumpulkan native memory/battery/thermal,
bukan menghitung FPS; jalankan sambil operator melakukan flow staging/fixture.

Wajib diuji: keyboard landscape, text scale 1/1.5/2, TalkBack, 100 resume/pause,
network lambat/offline/429, cold-start storage, POS attempt timeout/restart,
dua kasir, akun dinonaktifkan, mute/DND, notification denial, Android 15/16
dataSync timeout, dan upgrade APK bertanda tangan sama.

## Staging

`TKM_FLUTTER_LIVE_FIXTURE` menunjuk file privat berisi `environment: staging`,
`apiBase`, `stagingHost`, `supabaseUrl`, `stagingProjectRef`, `publicKey`, `email`,
`password`. Production ref/domain ditolak. Live contract read-only dan skip tanpa
fixture. Mutasi/cleanup diuji oleh Go/SQL disposable dan root staging-rush harness.

## Signing dan distribusi

Copy `android/key.properties.example` menjadi `android/key.properties` (ignored),
isi private keystore yang dimiliki owner. Tidak ada debug-key fallback untuk
release. Tanpa key, build menghasilkan artifact unsigned untuk review saja.
Version saat ini 0.2.0+2; pertahankan signature pada upgrade.

```sh
flutter build apk --release --dart-define-from-file=config/production.json --split-per-abi
python scripts/verify_release.py build/app/outputs/flutter-apk/app-arm64-v8a-release.apk \
  --aapt <android-build-tools/aapt> --apksigner <android-build-tools/apksigner> \
  --certificate-sha256 <approved-production-certificate-digest>
```

Verifier menolak unsigned/debug certificate, debuggable APK, identity tidak sesuai,
atau certificate yang berbeda. Verifikasi config target dan checksum juga wajib;
signature checker tidak dapat membuktikan endpoint operasional di dalam Dart.
Jangan distribusikan entry demo. Backend/migrasi 0020 harus siap sebelum APK baru.

Tidak ada signing/upload/store submission otomatis. iOS memerlukan Mac/Xcode,
team/capabilities, Keychain dan perangkat. Hasil Android tidak membuktikan iOS.
