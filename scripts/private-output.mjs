import { open, lstat, unlink } from 'node:fs/promises'
import { execFileSync } from 'node:child_process'
import { resolve, join } from 'node:path'

// Reserve a new file before remote mutations. No token is written until its
// access permissions have been verified. Refuse overwriting existing files.
export async function reservePrivateOutput(file) {
  const target = resolve(file)
  if (process.platform === 'win32' && !/^[a-z]:[\\/]/i.test(target))
    throw new Error('Private output requires a local Windows drive')
  const handle = await open(target, 'wx', 0o600)
  const original = await handle.stat()
  try {
    if (process.platform === 'win32') {
      const script = `
$ErrorActionPreference = 'Stop'
$sid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
$acl = New-Object System.Security.AccessControl.FileSecurity
$acl.SetOwner($sid)
$acl.SetAccessRuleProtection($true, $false)
$acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($sid, [System.Security.AccessControl.FileSystemRights]::FullControl, [System.Security.AccessControl.AccessControlType]::Allow))
Set-Acl -LiteralPath $env:TKM_OPERATOR_FILE -AclObject $acl
$check = Get-Acl -LiteralPath $env:TKM_OPERATOR_FILE
$rules = @($check.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
if (-not $check.AreAccessRulesProtected -or $rules.Count -ne 1 -or $rules[0].IdentityReference.Value -ne $sid.Value -or $rules[0].IsInherited -or $rules[0].AccessControlType -ne 'Allow' -or ($rules[0].FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::FullControl) -ne [System.Security.AccessControl.FileSystemRights]::FullControl) { throw 'Private ACL verification failed' }
`
      const env = Object.fromEntries(['SystemRoot', 'WINDIR', 'PATH', 'TEMP', 'TMP', 'USERPROFILE'].filter(key => process.env[key]).map(key => [key, process.env[key]]))
      env.TKM_OPERATOR_FILE = target
      execFileSync(join(process.env.SystemRoot || 'C:\\Windows', 'System32/WindowsPowerShell/v1.0/powershell.exe'), ['-NoLogo', '-NoProfile', '-NonInteractive', '-Command', script], { env, windowsHide: true, timeout: 10000, stdio: ['ignore', 'pipe', 'pipe'] })
    } else {
      await handle.chmod(0o600)
      if (((await handle.stat()).mode & 0o777) !== 0o600) throw new Error('Private file permissions unavailable')
    }
    const current = await lstat(target)
    if (!current.isFile() || current.ino !== original.ino || current.dev !== original.dev) throw new Error('Private output path changed')
    return handle
  } catch {
    await handle.close()
    const current = await lstat(target).catch(() => null)
    if (current?.ino === original.ino && current?.dev === original.dev) await unlink(target).catch(() => {})
    throw new Error('Cannot enforce private operator-file permissions')
  }
}
