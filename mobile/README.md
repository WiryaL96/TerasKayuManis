# Mobile TerasKayuManis

[Flutter kasir](cashier/README.md) berada pada monorepo yang sama dengan web dan Go.
Alurnya: order masuk → review → claim → input/pembayaran manual pada POS → konfirmasi
handoff. [Panduan pengguna](../docs/panduan-penggunaan.md) menjelaskan penggunaan.

Android memiliki watcher terbatas untuk notifikasi; iOS masih perlu validasi
build/device/signing. [Runner benchmark](cashier/perf_harness/README.md) memakai
fixture terpisah dan tidak mengakses POS/database restoran.
