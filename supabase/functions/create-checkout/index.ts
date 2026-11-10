import { authenticatedUser, errorMessage, handlePreflight, json, serviceClient } from '../_shared/http.ts'

Deno.serve(async (request) => {
  const preflight = handlePreflight(request); if (preflight) return preflight
  try {
    const user = await authenticatedUser(request)
    const body = await request.json()
    if (!Array.isArray(body.items) || body.items.length < 1 || body.items.length > 10) return json(request, { error: 'Invalid cart' }, 400)
    const keyId = Deno.env.get('RAZORPAY_KEY_ID'); const keySecret = Deno.env.get('RAZORPAY_KEY_SECRET')
    if (!keyId || !keySecret) return json(request, { error: 'UPI checkout is not configured yet' }, 503)
    const db = serviceClient()
    const { data: order, error: orderError } = await db.rpc('create_checkout_order', { p_user_id: user.id, p_items: body.items, p_coupon_code: typeof body.couponCode === 'string' ? body.couponCode.slice(0, 40) : null })
    if (orderError) return json(request, { error: orderError.message }, 400)
    const amountPaise = Math.round(Number(order.amount) * 100)
    if (!Number.isSafeInteger(amountPaise) || amountPaise <= 0) {
      await db.from('orders').update({ payment_status: 'failed' }).eq('id', order.id)
      return json(request, { error: 'Final order amount must be greater than zero' }, 400)
    }
    const auth = btoa(`${keyId}:${keySecret}`)
    const response = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST', headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ amount: amountPaise, currency: 'INR', receipt: order.order_number, notes: { internal_order_id: order.id, customer_user_id: user.id } }),
    })
    const gateway = await response.json()
    if (!response.ok || !gateway.id) {
      await db.from('orders').update({ payment_status: 'failed' }).eq('id', order.id)
      await db.from('coupon_usage').update({ status: 'released' }).eq('order_id', order.id).eq('status', 'reserved')
      return json(request, { error: 'Payment gateway could not create the order. No payment was taken.' }, 502)
    }
    const { error: bindError } = await db.rpc('bind_razorpay_order', { p_order_id: order.id, p_provider_order_id: gateway.id, p_amount_paise: amountPaise })
    if (bindError) {
      await fetch(`https://api.razorpay.com/v1/orders/${gateway.id}`, { method: 'PATCH', headers: { Authorization: `Basic ${auth}`, 'Content-Type': 'application/json' }, body: JSON.stringify({ notes: { abandoned: 'order binding failed' } }) }).catch(() => undefined)
      await db.from('orders').update({ payment_status: 'failed' }).eq('id', order.id)
      return json(request, { error: 'Unable to bind the verified gateway order. No checkout was opened.' }, 500)
    }
    return json(request, { orderId: order.id, orderNumber: order.order_number, razorpayOrderId: gateway.id, amount: amountPaise, subtotal: Number(order.subtotal), discountAmount: Number(order.discount_amount), currency: 'INR', keyId, customerEmail: user.email || '' })
  } catch (error) { return json(request, { error: errorMessage(error) }, 400) }
})
