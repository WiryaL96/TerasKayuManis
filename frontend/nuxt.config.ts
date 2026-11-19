import tailwindcss from '@tailwindcss/vite'

// A deliberately isolated UI sandbox. Never enabled by a production deployment.
const previewDemo = process.env.VERCEL_ENV === 'preview' && process.env.TKM_PREVIEW_DEMO === '1'

export default defineNuxtConfig({
  ssr: !previewDemo,
  compatibilityDate: '2025-07-15',
  devtools: { enabled: process.env.NODE_ENV !== 'production' },
  // Transitional Nitro API: source is separated; runtime remains Nuxt until
  // each business endpoint has been migrated and verified in Go.
  serverDir: '../backend/legacy-nuxt',
  css: ['~/assets/css/main.css', '~/assets/css/customer.css', '~/assets/css/customer-responsive.css', '~/assets/css/cashier.css', '~/assets/css/operations.css', '~/assets/css/dashboard.css'],
  vite: { plugins: [tailwindcss()] },
  // Server runtime is Node 22+; financial aggregations use native BigInt.
  nitro: { esbuild: { options: { target: 'es2022' } } },
  runtimeConfig: {
    previewDemo,
    siteUrl: '',
    backupStatusPath: '/var/lib/teraskayumanis-backups/status.json',
    goApiUrl: '',
    serverless: process.env.VERCEL === '1',
    backendProxySecret: '',
    supabaseUrl: '',
    supabaseServiceKey: '',
    supabaseAnonKey: '',
    cashierPinSecret: '',
    public: {
      previewDemo,
      syncMode: process.env.VERCEL === '1' ? 'polling' : 'websocket',
      supabaseUrl: '',
      supabaseAnonKey: ''
    }
  },
  routeRules: {
    '/admin/**': { ssr: false },
    '/cashier': { ssr: false }
  },
  app: {
    head: {
      title: 'TerasKayuManis',
      link: [
        { rel: 'icon', type: 'image/png', sizes: '32x32', href: '/favicon-32.png' },
        { rel: 'apple-touch-icon', sizes: '180x180', href: '/apple-touch-icon.png' },
        { rel: 'preconnect', href: 'https://fonts.googleapis.com' },
        { rel: 'preconnect', href: 'https://fonts.gstatic.com', crossorigin: '' },
        {
          rel: 'stylesheet',
          href: 'https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,400..700&family=Inter:wght@400..700&family=Montserrat:wght@400;500;600;700;800&display=swap'
        }
      ]
    }
  }
})
