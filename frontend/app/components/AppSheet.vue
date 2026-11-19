<script setup lang="ts">
const route = useRoute()
const dashboardTheme = useState<'light'|'dark'>('dashboard-theme', ()=>'light')
const dashboard = computed(()=>route.path.startsWith('/admin'))
const props = defineProps<{ open: boolean; title?: string }>()
const emit = defineEmits<{ close: [] }>()
const dialog = ref<HTMLDialogElement | null>(null)
const titleId = useId()
const closing = ref(false)
let previousFocus: HTMLElement | null = null
let previousOverflow = ''
let locked = false
let revision = 0
let animation: Animation | undefined
function unlock() {
  if (!locked) return
  document.body.style.overflow = previousOverflow
  locked = false
  if (previousFocus?.isConnected) previousFocus.focus()
}
watch(() => props.open, async open => {
  if (!import.meta.client) return
  const current = ++revision
  await nextTick()
  const element = dialog.value
  if (!element || current !== revision || (!open && !element.open)) return
  const wasOpen = element.open
  const from = wasOpen ? getComputedStyle(element).transform : 'translateY(60px)'
  animation?.cancel()
  closing.value = !open
  if (open && !wasOpen) {
    previousFocus = document.activeElement as HTMLElement | null
    previousOverflow = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    locked = true
    element.showModal()
    element.querySelector<HTMLElement>('input:not([disabled]), select:not([disabled]), textarea:not([disabled])')?.focus()
  }
  if (!matchMedia('(prefers-reduced-motion: reduce)').matches) {
    animation = element.animate([{ transform: from, opacity: wasOpen ? getComputedStyle(element).opacity : '0' }, { transform: open ? 'translateY(0)' : 'translateY(60px)', opacity: open ? '1' : '0' }], { duration: 320, easing: 'cubic-bezier(.22,1,.36,1)', fill: 'forwards' })
    try { await animation.finished } catch { return }
  }
  if (current !== revision) return
  if (!open) { element.close(); unlock() }
  animation?.cancel()
  animation = undefined
}, { immediate: true })
function backdrop(event: MouseEvent) {
  if (event.target !== dialog.value) return
  const bounds = dialog.value!.getBoundingClientRect()
  if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) emit('close')
}
onBeforeUnmount(() => { revision++; animation?.cancel(); dialog.value?.close(); unlock() })
</script>

<template>
  <Teleport to="body">
    <dialog ref="dialog" class="app-sheet-dialog" :class="{'tkm-dashboard':dashboard}" :data-dashboard-theme="dashboard ? dashboardTheme : undefined" :data-state="closing ? 'closing' : 'open'" :aria-labelledby="props.title ? titleId : undefined" :aria-label="props.title ? undefined : 'Formulir'" @cancel.prevent="emit('close')" @click="backdrop">
      <div class="app-sheet-panel">
        <div class="app-sheet-header sticky top-0 z-10 flex items-center justify-between border-b border-brand-100 bg-white px-5 py-4">
          <h2 :id="titleId" class="font-display text-lg font-semibold text-brand-950">{{ props.title }}</h2>
          <button type="button" class="btn btn-ghost btn-sm" aria-label="Tutup" @click="emit('close')"><Icon name="x" :size="18" /></button>
        </div>
        <div class="px-5 py-4"><slot /></div>
        <slot name="footer" />
      </div>
    </dialog>
  </Teleport>
</template>
