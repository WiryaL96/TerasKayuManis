# Dokumentasi TerasKayuManis

Dokumen yang menjadi acuan untuk branch `main` dikelompokkan menurut kebutuhan.
[Riwayat dokumentasi](riwayat.md) menjelaskan cara membaca bukti rilis/audit lama
melalui Git ketika diperlukan.

## Untuk pengguna dan operator

- [Panduan penggunaan](panduan-penggunaan.md): customer, kasir web/mobile, admin,
  superadmin, dan troubleshooting sehari-hari.
- [Alur self-order dan POS](self-order-pos-flow.md): aturan bisnis yang berlaku.
- [QR bersama](shared-qr-checkout.md): kontrak QR tanpa identitas meja.
- [Peran staf](staff-roles.md): kewenangan dan pengelolaan akun.

## Untuk production

- [Production readiness](production-readiness.md): checklist sebelum migrasi,
  deployment, staging, backup, signing, rollback, dan acceptance.
- [Migrasi](migration.md): urutan schema dan perbedaan database baru/existing.
- [GitHub CI/CD](github-cicd.md): CI dan jalur VPS opsional.
- [Frontend Vercel + Go VPS](hosting-vercel-vps.md): kapasitas, region dan syarat transisi.
- [Backup dan restore](../deploy/backup/README.md): backup terenkripsi dan drill.
- [Audit pra-production](audit-production.md): temuan, perbaikan dan batas verifikasi.
- [Riwayat](riwayat.md): cara membaca bukti deployment, backup dan pengujian lama.

## Untuk pengembang

- [Arsitektur backend](../backend/arsitektur.md): komponen dan batas runtime.
- [Backend setup](../backend/README.md) dan [frontend setup](../frontend/README.md).
- [Realtime Go](../backend/REALTIME.md): kontrak WebSocket pada runtime persisten.
- [API mobile](../mobile/cashier/docs/API_CONTRACT.md).
- [Testing dan release mobile](../mobile/cashier/docs/TESTING_RELEASE.md).

Dokumen implementasi lama, hasil audit bertanggal, dan catatan deployment historis
tidak dipakai sebagai instruksi rilis baru. Bila membutuhkan alasan perubahan,
gunakan `git log` pada commit yang relevan.
