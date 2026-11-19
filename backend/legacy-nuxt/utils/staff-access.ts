import { randomBytes, createHash } from 'node:crypto'
import type { H3Event } from 'h3'
import { canManageStaffRole } from '#shared/staff-roles'
import type { Profile } from '#shared/types'

export async function accessLink(
  event: H3Event,
  actor: Pick<Profile, 'id' | 'role'>,
  target: string,
  purpose: 'activation' | 'recovery',
) {
  const sb = serviceClient(event)
  const { data: p, error } = await sb
    .from('profiles')
    .select('id,email,role,staff_status')
    .eq('id', target)
    .single()
  if (
    error ||
    !p ||
    p.staff_status === 'disabled' ||
    !p.email
  )
    throw createError({
      statusCode: 400,
      statusMessage: 'Akun tidak dapat diberi tautan akses.',
    })
  if (actor.id === target || !canManageStaffRole(actor.role, p.role))
    throw createError({ statusCode: 403, statusMessage: 'Peran Anda tidak dapat mengelola akun ini.' })
  const existing = await sb.auth.admin.getUserById(target)
  if (existing.error) {
    if (existing.error.status !== 404)
      throw createError({
        statusCode: 503,
        statusMessage: 'Identitas staf belum dapat diperiksa.',
      })
    const created = await sb.auth.admin.createUser({
      id: target,
      email: p.email,
      email_confirm: true,
      app_metadata: { staff_session_version: 0 },
    })
    if (created.error)
      throw createError({
        statusCode: 409,
        statusMessage:
          'Identitas belum dibuat atau email sudah digunakan akun lain.',
      })
  } else if (existing.data.user.email?.toLowerCase() !== p.email.toLowerCase())
    throw createError({
      statusCode: 409,
      statusMessage: 'Email profil tidak sesuai dengan identitas akun.',
    })
  const ticket = randomBytes(32).toString('hex')
  const { data: profile, error: issueError } = await sb.rpc(
    'issue_staff_access',
    {
      p_actor: actor.id,
      p_target: target,
      p_hash: createHash('sha256').update(ticket).digest('hex'),
      p_purpose: purpose,
    },
  )
  if (issueError || !profile)
    throw createError({
      statusCode: 409,
      statusMessage: 'Akun berubah. Muat ulang dan coba lagi.',
    })
  const { data: link, error: linkError } = await sb.auth.admin.generateLink({
    type: 'recovery',
    email: p.email,
  })
  if (linkError || !link?.properties?.hashed_token || link.user?.id !== target)
    throw createError({
      statusCode: 503,
      statusMessage:
        'Tautan belum berhasil dibuat. Akun tetap menunggu aktivasi; coba buat tautan lagi.',
    })
  const base = String(useRuntimeConfig(event).siteUrl).replace(/\/$/, '')
  const fragment = new URLSearchParams({
    ticket,
    token_hash: link.properties.hashed_token,
    purpose,
  })
  return {
    url: base + '/auth/activate#' + fragment.toString(),
    expires_in: 3600,
  }
}
