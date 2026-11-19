import { readFile } from 'node:fs/promises'
import type { H3Event } from 'h3'
import type { BackupStatus } from '#shared/dashboard'
export async function readBackupStatus(event: H3Event): Promise<BackupStatus> {
  if(useRuntimeConfig(event).serverless){
    const actor=await requireStaff(event,['superadmin'])
    const {data,error}=await serviceClient(event).rpc('read_backup_status',{p_actor:actor.id})
    if(error)return {result:'Status backup belum tersedia. Periksa worker backup.'}
    return data??{}
  }
  try {
    const status = JSON.parse(await readFile(String(useRuntimeConfig(event).backupStatusPath), 'utf8'))
    return Object.fromEntries(['result', 'last_attempt', 'last_success', 'restore_verified_at'].filter(k => typeof status[k] === 'string').map(k => [k, status[k]]))
  } catch { return { result: 'Belum ada status backup yang dapat dibaca' } }
}
