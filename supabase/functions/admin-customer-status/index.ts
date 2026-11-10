import { authenticatedUser, errorMessage, handlePreflight, json, requireAdmin, serviceClient } from '../_shared/http.ts'
Deno.serve(async request => {
  const preflight=handlePreflight(request); if(preflight)return preflight
  try {
    const user=await authenticatedUser(request); const db=serviceClient(); const role=await requireAdmin(user.id,db)
    if(role!=='admin') return json(request,{error:'Administrator access required'},403)
    const body=await request.json(); const customerId=String(body.customerId||''); const status=String(body.status||''); const reason=String(body.reason||'').trim()
    if(!customerId||!['active','suspended'].includes(status)||reason.length<8||reason.length>500) return json(request,{error:'Provide a customer, valid status and an 8–500 character reason'},400)
    if(customerId===user.id) return json(request,{error:'Administrators cannot suspend their own account'},400)
    const {data:before,error:readError}=await db.from('users').select('id,status').eq('id',customerId).maybeSingle()
    if(readError||!before) return json(request,{error:'Customer not found'},404)
    const {error:updateError}=await db.from('users').update({status,updated_at:new Date().toISOString()}).eq('id',customerId)
    if(updateError) throw updateError
    const {error:auditError}=await db.from('audit_logs').insert({actor_id:user.id,action:status==='suspended'?'customer_suspended':'customer_reinstated',entity_type:'user',entity_id:customerId,metadata:{reason,previous_status:before.status,new_status:status}})
    if(auditError) throw auditError
    return json(request,{customerId,status})
  } catch(error) { return json(request,{error:errorMessage(error)},400) }
})
