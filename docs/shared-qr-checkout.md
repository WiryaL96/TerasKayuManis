# Kontrak QR bersama

Satu QR membuka `/menu` pada domain restoran yang dikonfigurasi. Kamera ponsel
customer membuka browser; tidak ada scanner kedua, token meja, pilihan meja,
cookie meja, atau meja default dalam checkout baru. Nomor meja fisik diberikan
kasir setelah proses POS.

Migration 0005 membuat `orders.table_id` nullable. Checkout baru menyimpan NULL;
order historis tetap memiliki referensinya. `order_json` memakai left join sehingga
order tanpa meja tetap terbaca. Reorder hanya menyiapkan draft, kemudian checkout
membuat nomor baru pada harga terkini.

`table_token` lama masih diterima/serialisasi untuk kesetaraan payload idempotency,
tetapi tidak dipakai menetapkan meja baru. Jangan mengubah payload percobaan checkout
yang belum pasti. QR publik juga **bukan** token akses order pribadi: tracking
memerlukan `X-Order-Token` milik order tersebut.

Alur setelah checkout mengikuti [self-order/POS](self-order-pos-flow.md).
Pengujian ada di `scripts/shared-qr.test.mjs`, `backend/tests/shared_qr_migration.sql`
dan Go shared-QR tests. Hasil browser URL tidak membuktikan QR cetak/kamera fisik;
scan hasil cetak pada perangkat nyata sebelum dipasang di restoran.
