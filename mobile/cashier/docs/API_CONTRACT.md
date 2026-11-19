# Kontrak API mobile kasir

Dibaca dari `backend/internal/commerce/{http,orders,review,realtime,mobile}.go` dan migrasi 1–20.
Jangan menganggap Supabase REST sebagai API bisnis. Public prefix saat ini
`https://teraskayumanis.vercel.app/api/core/`, diproxy ke Go `/api/v1/`.
Seluruh UUID di contoh adalah placeholder, bukan data operasional.

## Auth

Login mendukung:
1. Email/username & password via `POST /api/auth/staff-login` (`{email, password, area: "cashier"}`), lalu instalasi session SDK.
2. Logout mengirim audit Bearer ke `/api/auth/staff-logout`, lalu sign-out lokal tetap berjalan meski audit gagal.
3. Pilihan kasir & PIN 6 angka via `GET /api/auth/cashiers` dan `POST /api/auth/cashier-pin` (`{cashier_id, pin}`) lalu `supabase.auth.setSession(refresh_token)`.

Respons 401 pada login PIN berarti kredensial/akun ditolak dan ditampilkan sebagai
pesan untuk memeriksa kasir/PIN. Pesan sesi berakhir hanya berlaku pada request
setelah login, bukan pada penolakan kredensial.

Ambil access token dari session untuk setiap request dan subscription. Refresh
session dikelola SDK; tidak menyimpan password/PIN. Backend memvalidasi token melalui Auth
`/auth/v1/user`, lalu `profiles.role` (cashier/admin/superadmin) dan `session_version`.

Header staf: `Authorization: Bearer <access-token>`; JSON `Content-Type: application/json`.
Tidak ada cookie wajib, tidak ada table identity. `X-Order-Token` berbeda: private
capability untuk pemilik customer-order, digunakan saat membuat/retry reorder baru.
Jangan menyamakan dengan anon key/staff JWT/QR URL.

## Profil staf & Daftar order

`GET admin/me` -> 200 `{id, full_name, role}`. Wajib memuat nama lengkap staf sebelum menangani pesanan (`claim-pos`).

`GET admin/orders?tab=active&status=&q=&sort=newest&offset=0`

- `tab`: `active` (default) atau `history`.
- `active` statuses: `pending`, `ready` (virtual filter: `pending` + `unpaid` + `reviewed_version == version` + belum kedaluwarsa), `pos_input`, `confirmed`.
- `history` statuses: `forwarded`, `completed`, `expired`, `cancelled`.
- `q`: pencarian literal (maksimal 80 karakter) untuk nomor pesanan, nama pelanggan, atau nama produk.
- `sort`: `newest` (default) atau `oldest`.
- `offset`: integer 0..100000; mobile berpindah dalam langkah 100 dan server limit
  100 tetap. Bukan `page`, bukan cursor.
- Response 200 array order, termasuk detail item dan `pos_handoff`.
- `date=YYYY-MM-DD` pada tab history memfilter `created_at` dalam WIB sebelum pagination.
- `summary=1` pada mobile hanya mengambil metadata/count/handoff; detail item dimuat
  ketika order dibuka. Klien web tanpa parameter ini tetap mendapat full list.
- `GET admin/orders/{id}` adalah detail staf ber-Bearer, tidak bergantung filter/page.
  `GET orders/{id}` tetap endpoint customer capability.

Pada server lama tanpa route detail, hanya respons Go **404 text/plain**
`404 page not found` yang mengaktifkan fallback. Mobile membaca ulang
`admin/orders?tab=active&q=<nomor>&sort=newest&offset=0` tanpa `summary`, status,
tanggal, atau filter UI, lalu mencari ID persis yang dipilih. Jika belum ada,
pencarian berlanjut ke history; masing-masing tab dibatasi tiga halaman 100 baris.
Hanya snapshot segar dengan ID cocok, versi valid, dan `order_items` lengkap
yang dapat mengaktifkan tindakan. JSON 404, 401/403, timeout/5xx, respons rusak,
pesanan hilang, maupun versi mundur tetap menutup tindakan. Pencarian tidak boleh
melintasi pergantian sesi. Nomor pesanan disimpan bersama intent POS baru untuk
rekonsiliasi setelah restart; intent lama tetap dapat dibaca.

Contoh struktur (nilai ilustrasi, bukan respons live):

```json
{
  "id":"<uuid>","order_number":"A123","customer_name":"Pelanggan",
  "table_id":null,"tables":null,"status":"pending","payment_status":"unpaid",
  "payment_method":"cash","version":2,"reviewed_version":2,
  "expires_at":"<ISO8601 UTC>","created_at":"<ISO8601 UTC>","total":10000,
  "order_items":[{
    "id":"<uuid>","product_id":"<uuid>","product_name":"Teh",
    "quantity":2,"unit_price":5000,"addons_total":0,"subtotal":10000,
    "variant_ids":[],"addon_ids":[],"notes":"",
    "order_item_addons":[]
  }]
}
```

Snapshot juga berisi subtotal/discount/tax/service_charge dan field lain. Abaikan field
tambahan yang tidak dibutuhkan; jangan drop order karena tables null. Integer Rupiah.

## Menu untuk review

`GET menu` public, response200 `{settings,categories,products}`.

Product: id,name,price,is_available,variants[],addons[]. Variant:
id,name,group_name,price_modifier,is_available. Addon: id,name,price,is_available.
**Pilih satu variant per available group**, tidak boleh duplicate group; setiap available
group wajib diisi. Addon harus terkait product dan available, tidak boleh duplicate.
Menu/catatan review dimuat fresh sebelum revisi. Jangan mengganti menu hilang diam-diam.
`settings.require_customer_name` mengatur nama saat membuat order/reorder.

## Review/revisi sebelum pembayaran

`POST orders/<uuid>/review`

```json
{"expected_version":1,"items":[{"product_id":"<uuid>","quantity":2,"variant_ids":[],"addon_ids":[],"notes":"tanpa es"}]}
```

Server menghitung harga, mengubah version dan reviewed_version bersama. Tetap pending/unpaid;
expires_at tidak diperpanjang. Response200 snapshot order. Maksimal50 baris, qty1..50,
variant/addon maksimal20 masing-masing, notes disimpan maksimal200 karakter.
Frontend dilarang mengirim total/subtotal buatan sendiri. Stale/expired409 -> muat ulang,
kasir cek ulang bersama pelanggan sebelum menerima uang.

## Tangani pesanan ke aplikasi kasir (`claim-pos`)

`POST orders/<uuid>/claim-pos`

```json
{"expected_version":2}
```

Atau pengambilalihan oleh admin/superadmin untuk order `pos_input` milik kasir lain:

```json
{"expected_version":3,"takeover_reason":"Kasir pagi pergantian shift"}
```

Hanya order `pending` + `unpaid` yang sudah direview (`reviewed_version == version`) dan belum expired (atau pengambilalihan `pos_input` oleh admin/superadmin dengan alasan 5–200 karakter). Status berubah menjadi `pos_input`, batas waktu kedaluwarsa berhenti, dan `pos_handoff` mencatat `cashier_id`, `cashier_name`, `claimed_at`.

## Konfirmasi masuk aplikasi kasir (`forward-pos`)

`POST orders/<uuid>/forward-pos`

```json
{"expected_version":3,"pos_reference":"POS-100","entered_in_pos":true,"paid_in_pos":true}
```

Hanya kasir penanggung jawab (`pos_handoff.cashier_id == staff.id`) pada order `pos_input`. Wajib mencentang `entered_in_pos` dan `paid_in_pos`; `pos_reference` opsional maksimal 80 karakter. Status berubah menjadi `forwarded` dan masuk ke tab Riwayat. Endpoint `confirm-cash` dan `complete` lama telah dipensiunkan (HTTP 410 Gone).

## Pesan ulang expired

`GET orders/<uuid>/reorder` (Bearer staf) ->200:

```json
{"customer_name":"Pelanggan","payment_method":"cash","items":[{"product_id":"<uuid>","quantity":1,"variant_ids":[],"addon_ids":[],"notes":""}]}
```

GET hanya menyiapkan draft, tidak membuat order. Mobile ambil katalog terbaru, revisi
dan konfirmasi. POST `orders` dengan draft baru, **tanpa table_token**:

```text
Idempotency-Key: <random UUID, panjang16..128>
X-Order-Token: <private random capability, panjang24..256>
```

Response201 (termasuk retry) snapshot baru pending/unpaid. Simpan payload/key/capability
secara durable dan scoped akun sebelum POST. Retry harus byte-semantically sama JSON,
jangan mengganti key ketika respons belum pasti. Jangan mengubah timer/order lama.

## Sinkronisasi dan lease Android

`GET admin/sync` dengan Bearer mengembalikan `{revision: string, new_orders:
UUID[], overflow: boolean}`. UUID berasal dari checkout committed 15 menit
terakhir, maksimal 1000. Snapshot pertama menjadi baseline tanpa bunyi.
Daftar notifikasi terpisah dari tab/filter, termasuk ketika membuka history.
Cache membaca revision sebelum full list/detail; force refresh dan rekonsiliasi
60 detik tetap tersedia. Default mobile `SYNC_MODE=polling` memakai interval
lima detik dan backoff jika jaringan gagal.

Kompatibilitas server lama: respons `{revision: string}` tanpa `new_orders`
ditandai `hasNewOrderFeed=false`. Login tetap harus berhasil menginstal session
dan membaca antrean staf. Polling revision, cache, refresh, serta pemeriksaan
otorisasi tetap berjalan. Suara foreground memakai snapshot tetap
`admin/orders?tab=active&summary=1&sort=newest&offset=0` tanpa filter. Respons
antrean yang terlihat digunakan ulang jika query-nya sama; selain itu satu read
tambahan dilakukan saat revision berubah, force refresh, atau rekonsiliasi
60 detik. Snapshot awal adalah baseline tanpa bunyi. ID dan timestamp pembuatan
mencegah bunyi ulang akibat update status, pergantian tab/filter/page, atau
pesanan lama yang masuk halaman pertama. Memori deduplikasi maksimal 1000 ID.
Toggle suara tetap bisa ON/OFF dan ON memutar contoh bunyi. UI menjelaskan
pemantauan latar belum didukung; lease/watcher Android tetap tidak diaktifkan.
Fallback terbatas pada 100 pesanan aktif terbaru per snapshot: checkout yang
sudah keluar dari antrean sebelum poll dapat terlewat. Feed server tetap
dibutuhkan untuk cakupan event/background lengkap.
`new_orders: null` maupun feed bertipe salah tetap merupakan error kontrak yang
ditampilkan sebagai masalah sinkronisasi. Ketika feed tersedia lagi, snapshot
pertama menjadi baseline tanpa bunyi. Fitur detail/aksi lain tetap memerlukan
endpoint server masing-masing; fallback ini bukan bukti kompatibilitas semua API.

| Request | Otorisasi | Hasil |
| --- | --- | --- |
| `POST admin/watch` body `{device_id: UUID}` | Bearer staf aktif | `{token, expires_at}` |
| `GET admin/watch` | Header `X-Watch-Token` | Snapshot sync saja |
| `DELETE admin/watch` | Header `X-Watch-Token` | 204; revoke idempotent |

Token lease acak disimpan hanya hash-nya pada DB, terikat staf/session_version,
TTL maksimum 5 jam 30 menit, maksimal lima perangkat aktif. Device ID acak,
bukan hardware fingerprint. Lease baru untuk perangkat sama mengganti lease lama.
Lease tidak dapat mengakses detail, login, laporan atau mutasi. Token dilarang
di URL/log. Android menyimpan lease AES-GCM/Keystore; tidak menerima token Supabase.

Logout membersihkan state lokal dan mencoba revoke server. Offline revocation
tidak instan; batas izin dan TTL tetap berlaku. Android dataSync/OEM/force-stop
tetap dapat menghentikan watcher; API ini bukan FCM atau jaminan push tanpa batas.

## Error dan jaringan

Bentuk umum `{ "error":"...", "code":"...optional" }`. Jangan expose raw stack,
request header atau Supabase exception penuh di UI. POST tidak otomatis diretry.

- 400: payload/type/method invalid. Periksa serializer/schema.
- 401: auth tidak valid **atau** role staf tidak diterima. Jangan anggap login UI saja cukup.
- 403: forbidden/Origin policy/DB permission. Jangan memperlebar grants sebagai shortcut.
- 404: tidak ditemukan/ownership tidak valid. Bukan alasan mencoba capability berbeda.
- 409: stale/review gate/expired/validation. REST refetch sebelum aksi berikut.
- 409 code `checkout_rejected`: checkout baru pasti tidak commit; boleh hapus attempt.
- 409 code `idempotency_conflict`: key/body/token beda; pertahankan identity dan investigasi.
- 429: hormati `Retry-After`; server persisten memakai budget lane per proses,
  serverless memakai budget IP/identity pada database.
- 503/timeout/network: hasil mutasi bisa tidak pasti. Jangan menampilkan sukses lokal.

Backend REST context8detik, BFF15detik, client timeout bounded; jangan memicu paralel
polling berlebihan. Event coalescing dan batas pagination membantu menjaga budget.
Semua retry gunakan backoff, tidak loop ketat.

## Referensi source dan aturan kompatibilitas

- `../../../backend/internal/commerce/http.go`: routes/menu/budget.
- `../../../backend/internal/commerce/orders.go`: auth/list/payment/checkout.
- `../../../backend/internal/commerce/review.go`: review/reorder/expiry.
- `../../../backend/migrations/0002_order_review_expiry.sql`: gate/transactions.
- `../../../backend/migrations/0005_shared_qr_checkout.sql`: tableless snapshot/staging.

Paths di atas relatif `mobile/cashier/`; dari file docs naik satu tingkat tambahan.
Server adalah sumber kebenaran. Bila API berubah, update test contract, docs dan changelog,
jangan sekadar menyesuaikan parser sehingga error tidak terlihat.
