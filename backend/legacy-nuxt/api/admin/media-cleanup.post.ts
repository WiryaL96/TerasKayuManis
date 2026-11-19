export default defineEventHandler(async event=>{
 await sensitiveRequest(event,6);await requireStaff(event,['superadmin'])
 return cleanupUploads(event)
})
