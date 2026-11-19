import {copyFileSync,lstatSync,mkdirSync,readdirSync,realpathSync,symlinkSync} from 'node:fs'
import {dirname,relative,resolve,sep} from 'node:path'

// Nitro shares its traced runtime through directory symlinks/junctions. Keep
// them as links within the destination; expanding each alias multiplies bundles.
export function copyVercelOutput(source,target){
 const sourceRoot=realpathSync(source),targetRoot=resolve(target)
 function copy(src,dst){
  const stat=lstatSync(src)
  if(stat.isSymbolicLink()){
   const resolved=realpathSync(src)
   if(resolved!==sourceRoot&&!resolved.startsWith(sourceRoot+sep))throw Error('Build output link must stay inside generated output')
   const dest=resolve(targetRoot,relative(sourceRoot,resolved))
   mkdirSync(dirname(dst),{recursive:true})
   if(lstatSync(resolved).isDirectory())symlinkSync(process.platform==='win32'?dest:relative(dirname(dst),dest),dst,process.platform==='win32'?'junction':'dir')
   else copyFileSync(resolved,dst)
  }else if(stat.isDirectory()){
   mkdirSync(dst,{recursive:true})
   for(const name of readdirSync(src))copy(resolve(src,name),resolve(dst,name))
  }else copyFileSync(src,dst)
 }
 copy(sourceRoot,targetRoot)
}
