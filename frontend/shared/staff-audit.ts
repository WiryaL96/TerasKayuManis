export const AUDIT_ACTIONS = {
  staff_edit_started: 'Perubahan identitas staf dimulai',
  staff_updated: 'Identitas dan peran staf diperbarui',
  staff_archived: 'Akun staf diarsipkan',
  staff_restored: 'Akun dipulihkan dalam status nonaktif',
  staff_login: 'Masuk aplikasi',
  staff_logout_requested: 'Permintaan keluar',
  cash_payment_confirmed: 'Pembayaran tunai diterima',
  order_reviewed: 'Menu pesanan diperiksa',
  pos_claimed: 'Pesanan ditangani untuk input ke aplikasi kasir',
  pos_reassigned: 'Penanganan pesanan diambil alih admin',
  pos_forwarded: 'Pesanan dikonfirmasi masuk aplikasi kasir',
  order_completed: 'Pesanan selesai',
  cashier_created: 'Akun kasir dibuat',
  admin_created: 'Akun admin dibuat',
  staff_password_started: 'Pengaturan akses staf dimulai',
  staff_password_set: 'Akses staf diatur dan akun diaktifkan',
  staff_creation_failed: 'Pembuatan akun staf dibatalkan',
  cashier_pin_set: 'PIN kasir diatur',
  staff_photo_updated: 'Foto staf diperbarui',
  staff_role_migrated: 'Peran staf dimigrasikan',
  rename: 'Nama staf diubah',
  disable: 'Akun staf dinonaktifkan',
  enable: 'Akun staf diaktifkan kembali',
  access_link_activation: 'Tautan aktivasi dibuat',
  access_link_recovery: 'Tautan pemulihan dibuat',
  access_activated: 'Password dan akses diaktifkan',
  pricing_confirmed: 'Tarif dan penerimaan pesanan diatur',
  owner_bootstrap: 'Akun pemilik disiapkan',
  superadmin_bootstrap: 'Akun superadmin disiapkan',
} as const
export type AuditAction = keyof typeof AUDIT_ACTIONS
export interface StaffActivity {
  id: string
  actor_id: string | null
  actor_name: string | null
  actor_role: string | null
  target_name: string | null
  order_id: string | null
  action: string
  created_at: string
  details: Record<string, string | number | boolean | null>
}
export interface StaffActivityPage {
  entries: StaffActivity[]
  total: number
  limit: number
  staff: { id: string; full_name: string | null; role: string }[]
}
