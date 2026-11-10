import { authenticatedUser, errorMessage, handlePreflight, json, requireAdmin, serviceClient } from '../_shared/http.ts'
Deno.serve(async request => {
  const preflight=handlePreflight(request); if(preflight)return preflight
  try {
    const user=await authenticatedUser(request); const db=serviceClient(); const role=await requireAdmin(user.id,db)
    if(role!=='admin') return json(request,{error:'Administrator access required'},403)
    const body=await request.json(); const orderId=String(body.orderId||''); const action=String(body.action||'')
    if(action!=='retry_delivery'||!orderId) return json(request,{error:'Unsupported order action'},400)
    const {data:order,error}=await db.from('orders').select('id,payment_status,delivery_status,razorpay_order_id').eq('id',orderId).maybeSingle()
    if(error||!order) return json(request,{error:'Order not found'},404)
    if(order.payment_status!=='paid'||order.delivery_status!=='inventory_pending'||!order.razorpay_order_id) return json(request,{error:'Only verified paid orders awaiting inventory can be retried'},409)
    const {data:payment,error:paymentError}=await db.from('payments').select('provider_order_id,provider_payment_id,amount_paise,currency,status').eq('order_id',orderId).eq('status','captured').order('created_at',{ascending:false}).limit(1).maybeSingle()
    if(paymentError||!payment||!payment.provider_payment_id) return json(request,{error:'No captured gateway payment is available for this order'},409)
    const {data:result,error:retryError}=await db.rpc('fulfill_verified_payment',{p_provider_order_id:payment.provider_order_id,p_provider_payment_id:payment.provider_payment_id,p_amount_paise:payment.amount_paise,p_currency:payment.currency,p_event:{source:'admin_inventory_retry',actor_id:user.id}})
    if(retryError) throw retryError
    await db.from('audit_logs').insert({actor_id:user.id,action:'paid_order_delivery_retry',entity_type:'order',entity_id:orderId,metadata:{result}})
    return json(request,{result})
  } catch(error) { return json(request,{error:errorMessage(error)},400) }
})
