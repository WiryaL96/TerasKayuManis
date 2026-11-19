export default defineNitroPlugin(nitro=>{
 nitro.hooks.hook('render:html',(html,{event})=>{
  const nonce=event.context.cspNonce
  if(!nonce)return
  for(const key of ['head','body','bodyPrepend','bodyAppend'] as const){
   html[key]=html[key].map(part=>part.replace(/<script\b(?![^>]*\bnonce=)/gi,`<script nonce="${nonce}"`))
  }
 })
})
