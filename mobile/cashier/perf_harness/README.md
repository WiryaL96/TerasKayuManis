# Cashier device benchmark runner

This Android app imports the actual cashier UI/controller through a path
dependency. It has a different application ID and local fixtures, no Supabase
keys, auth session, native watcher, or POS connection. Its default launcher is
the 100-order / 50-item stress fixture.

Keeping `integration_test` here prevents test plugin/runner dependencies from
entering normal cashier builds. The harness has its own pinned lockfile; use
Flutter 3.47.4 from the parent `.fvmrc`. Build one Android target at a time.

```sh
flutter pub get --enforce-lockfile
flutter analyze
flutter drive --profile --driver=test_driver/performance_driver.dart \
  --target=integration_test/performance_test.dart -d <physical-device>
```

The runner reports UI/raster p95/p99, the display frame budget, and jank fraction.
Run profile/release on the affected physical phone. A compile or widget test
does not establish frame performance. This fixture runner has debug signing for
device QA and is never the production cashier APK.
