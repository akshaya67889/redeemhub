import { authenticatedUser, errorMessage, handlePreflight, json, serviceClient } from '../_shared/http.ts'
Deno.serve(async request => {
  const preflight=handlePreflight(request); if(preflight)return preflight
  try {
    const user=await authenticatedUser(request); const body=await request.json(); const orderId=String(body.orderId||'')
    if(!orderId)return json(request,{error:'Order ID is required'},400)
    const db=serviceClient(); const {data:order,error}=await db.from('orders').select('id,order_number,user_id,subtotal,discount_amount,total_amount,payment_status,razorpay_order_id').eq('id',orderId).eq('user_id',user.id).maybeSingle()
    if(error||!order)return json(request,{error:'Order not found'},404)
    if(order.payment_status!=='pending'||!order.razorpay_order_id)return json(request,{error:'This order is not awaiting payment'},409)
    const {data:payment,error:paymentError}=await db.from('payments').select('provider_order_id,amount_paise,currency,status').eq('order_id',order.id).maybeSingle()
    if(paymentError||!payment||payment.provider_order_id!==order.razorpay_order_id)return json(request,{error:'Gateway order is unavailable'},409)
    const keyId=Deno.env.get('RAZORPAY_KEY_ID'); if(!keyId)return json(request,{error:'UPI checkout is not configured'},503)
    return json(request,{orderId:order.id,orderNumber:order.order_number,razorpayOrderId:payment.provider_order_id,amount:payment.amount_paise,subtotal:Number(order.subtotal),discountAmount:Number(order.discount_amount),currency:'INR',keyId,customerEmail:user.email||''})
  } catch(error) { return json(request,{error:errorMessage(error)},400) }
})
