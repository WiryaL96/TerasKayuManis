// Reproducible extraction of original document photographs. Input pages are
// 848x1200 PNG renderings of the supplied PDF; bounds were visually reviewed.
import sharp from 'sharp'
import { readFile, mkdir } from 'node:fs/promises'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
const source = process.argv[2]
if (!source)
  throw new Error(
    'Usage: node scripts/extract-menu-photos.mjs <rendered-page-directory>',
  )
const { photos } = JSON.parse(
  await readFile(
    new URL('../data/menu-photo-sources.json', import.meta.url),
    'utf8',
  ),
)
const out = new URL('../frontend/public/images/menu/', import.meta.url)
await mkdir(out, { recursive: true })
for (const {
  slug,
  page,
  rect: [left, top, width, height],
} of photos) {
  await sharp(resolve(source, `page-${String(page).padStart(2, '0')}.png`))
    .extract({ left, top, width, height })
    .resize({ width: 720, withoutEnlargement: true })
    .webp({ quality: 82 })
    .toFile(fileURLToPath(new URL(slug + '.webp', out)))
}
console.log(`${photos.length} original menu photographs extracted.`)
