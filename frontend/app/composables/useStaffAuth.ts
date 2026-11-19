import type { Profile } from '#shared/types'

export function useStaffAuth() {
  const client = useSupabase()
  const admin = useAdmin(), store = useDashboardCache()
  async function install(result:{profile:Profile;session:{access_token:string;refresh_token:string}}){
    admin.reset()
    const {error}=await client.auth.setSession(result.session)
    if(error){await client.auth.signOut({scope:'local'}).catch(()=>{});throw new Error('Sesi belum tersimpan. Coba masuk kembali.')}
    store.bind(result.profile)
    return result.profile
  }
  async function login(email: string, password: string, area: 'cashier' | 'admin') {
    const result = await $fetch<{ profile: Profile; session: { access_token: string; refresh_token: string } }>('/api/auth/staff-login', {
      method: 'POST', body: { email, password, area }, timeout: 25000, retry: 0,
    })
    return install(result)
  }
  async function loginPin(cashier_id:string,pin:string){
    const result=await $fetch<{profile:Profile;session:{access_token:string;refresh_token:string}}>('/api/auth/cashier-pin',{method:'POST',body:{cashier_id,pin},timeout:45000,retry:0})
    return install(result)
  }
  async function logout() {
    admin.reset()
    let recorded = true
    try { await $fetch('/api/auth/staff-logout', { method: 'POST', timeout: 10000, retry: 0 }) } catch { recorded = false }
    // A broken audit connection must never trap a cashier in a shared device.
    try {
      const { error } = await client.auth.signOut({ scope: 'local' })
      return recorded && !error
    } catch { return false }
    finally { admin.reset() }
  }
  return { login, loginPin, logout }
}
