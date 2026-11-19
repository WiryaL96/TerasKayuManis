// Reserve the actual fixed bar height, including wrapped text and safe-area padding.
export function useCustomerFooter(footer: Ref<HTMLElement|null>) {
  let observer: ResizeObserver | undefined
  let shell: HTMLElement | null = null
  const measure = () => {
    const element=footer.value
    if(element&&shell)shell.style.setProperty('--customer-footer-height',`${Math.ceil(element.getBoundingClientRect().height)}px`)
  }
  const stop = () => { observer?.disconnect(); observer=undefined; shell?.style.removeProperty('--customer-footer-height'); shell=null }
  watch(footer,element=>{
    stop()
    if(!element)return
    shell=element.closest<HTMLElement>('.customer-shell')
    measure()
    if(typeof ResizeObserver!=='undefined'){observer=new ResizeObserver(measure);observer.observe(element)}
  },{flush:'post'})
  onMounted(()=>{measure();window.addEventListener('resize',measure)})
  onUnmounted(()=>{stop();window.removeEventListener('resize',measure)})
}
