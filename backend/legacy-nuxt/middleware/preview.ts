// The demo client simulates APIs locally. A forgotten client interception must
// fail closed instead of contacting the restaurant's database or Auth service.
export default defineEventHandler(event => {
  if (useRuntimeConfig(event).previewDemo && event.path.startsWith('/api/')) {
    throw createError({ statusCode: 503, statusMessage: 'Preview UI memakai data simulasi di browser. API restoran tidak dihubungkan.' })
  }
})
