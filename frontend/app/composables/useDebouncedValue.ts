export function useDebouncedValue<T>(source: Ref<T>, delay = 350) {
  const value = ref(source.value) as Ref<T>
  let timer: ReturnType<typeof setTimeout> | undefined
  watch(source, next => { clearTimeout(timer); timer = setTimeout(() => { value.value = next }, delay) })
  onUnmounted(() => clearTimeout(timer))
  return value
}
