export const STAFF_ROLES = ['superadmin', 'admin', 'cashier'] as const
export type StaffRole = typeof STAFF_ROLES[number]
export const STAFF_ROLE_LABELS: Record<StaffRole, string> = {
  superadmin: 'Superadmin', admin: 'Admin', cashier: 'Kasir',
}
export function canManageStaffRole(actor: string, target: string) {
  return actor === 'superadmin' ? target === 'admin' || target === 'cashier'
    : actor === 'admin' && target === 'cashier'
}
