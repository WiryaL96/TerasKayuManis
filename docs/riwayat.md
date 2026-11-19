# Riwayat dan bukti terdahulu

Dokumentasi aktif dipangkas pada audit pra-production 16 November 2026. Rancangan
cash/KDS, task prompt, laporan UI sementara, panduan migrasi yang sudah selesai,
dan laporan deployment bertanggal tidak lagi menjadi instruksi aktif. Git tetap
menyimpan isinya; tidak ada riwayat yang ditulis ulang.

Gunakan snapshot **`f561075`** untuk membaca dokumen sebelum pembersihan:

```sh
git show f561075:docs/operations-readiness-2026-11-12.md
git show f561075:docs/web-release-2026-11-12.md
git show f561075:mobile/cashier/docs/REMEDIATION-2026-11-15.md
```

| Bukti historis | Lokasi pada snapshot f561075 | Batas |
| --- | --- | --- |
| Rilis web November, migrasi 0018/0019 | `docs/web-release-2026-11-12.md` | Klaim verifikasi pada waktu tersebut |
| Backup offsite dan restore | `docs/operations-readiness-2026-11-12.md` | Tidak membuktikan backup terbaru sukses |
| HTTP load Linux CI | `docs/staging-ci-rush-2026-11-12.json` | 4.915 request, fixture lokal; bukan kapasitas hosted |
| Audit/perbaikan mobile awal | `mobile/cashier/docs/AUDIT-2026-11-15.md`, `REMEDIATION-2026-11-15.md` | 70 tes Flutter, 3 JVM; FPS belum diukur |
| Konsolidasi branch | `docs/branch-consolidation-2026-11-16.md` | Seluruh riwayat main/mobile/monorepo dipertahankan |
| Audit backend lama | `docs/backend-audit-2026-10-31.md` | Temuan baseline lama, sebagian telah diperbaiki |

Link run yang direkam pada bukti terdahulu:

- [CI beban terisolasi](https://github.com/zDarkx1/TerasKayuManis/actions/runs/43241197137)
- [Backup yang pernah diunduh dan direstore](https://github.com/zDarkx1/TerasKayuManis/actions/runs/43239055630)

Hasil audit source sekarang terdapat di [audit pra-production](audit-production.md).
Status deployment/backup/perangkat harus diperiksa pada lingkungan sebenarnya
sebelum rilis; bukti lama bukan sertifikasi kesiapan saat ini.
