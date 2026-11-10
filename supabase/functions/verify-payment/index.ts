import { authenticatedUser, errorMessage, handlePreflight, json, serviceClient } from '../_shared/http.ts'

function hex(bytes: Uint8Array) { return [...bytes].map(v => v.toString(16).padStart(2, '0')).join('') }
async function hmacHex(secret: string, message: string) {
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
  return hex(new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message))))
}
function constantTimeEqual(a: string, b: string) { if (a.length !== b.length) return false; let mismatch = 0; for (let i=0;i<a.length;i++) mismatch |= a.charCodeAt(i) ^ b.charCodeAt(i); return mismatch === 0 }
Deno.serve(async (request) => {
  const preflight = handlePreflight(request); if (preflight) return preflight
  try {
    const user = await authenticatedUser(request); const body = await request.json()
    const orderId = String(body.orderId || ''); const providerOrderId = String(body.razorpay_order_id || ''); const paymentId = String(body.razorpay_payment_id || ''); const signature = String(body.razorpay_signature || '')
    if (!orderId || !providerOrderId || !paymentId || !signature) return json(request, { error: 'Missing payment verification fields' }, 400)
    const db = serviceClient()
    const { data: order, error: orderError } = await db.from('orders').select('id,user_id,razorpay_order_id,total_amount,payment_status').eq('id', orderId).maybeSingle()
    if (orderError || !order || order.user_id !== user.id || order.razorpay_order_id !== providerOrderId) return json(request, { error: 'Order not found for this account' }, 404)
    const secret = Deno.env.get('RAZORPAY_KEY_SECRET'); const keyId = Deno.env.get('RAZORPAY_KEY_ID')
    if (!secret || !keyId) return json(request, { error: 'Payment verification is not configured' }, 503)
    const expected = await hmacHex(secret, `${providerOrderId}|${paymentId}`)
    if (!constantTimeEqual(expected, signature.toLowerCase())) return json(request, { error: 'Payment signature did not verify' }, 400)
    const auth = btoa(`${keyId}:${secret}`)
    const gatewayResponse = await fetch(`https://api.razorpay.com/v1/payments/${encodeURIComponent(paymentId)}`, { headers: { Authorization: `Basic ${auth}` } })
    const payment = await gatewayResponse.json()
    if (!gatewayResponse.ok || payment.order_id !== providerOrderId) return json(request, { error: 'Gateway payment could not be verified against this order' }, 400)
    if (payment.currency !== 'INR' || Number(payment.amount) !== Math.round(Number(order.total_amount) * 100)) return json(request, { error: 'Gateway amount or currency does not match the order' }, 400)
    if (payment.status !== 'captured') return json(request, { status: payment.status === 'failed' ? 'failed' : 'pending', deliveryStatus: 'pending', message: 'Payment is not captured yet; no code was delivered.' }, 200)
    const { data, error } = await db.rpc('fulfill_verified_payment', { p_provider_order_id: providerOrderId, p_provider_payment_id: paymentId, p_amount_paise: Number(payment.amount), p_currency: payment.currency, p_event: { source: 'authenticated_checkout_verification', payment_id: paymentId, status: payment.status } })
    if (error) throw error
    return json(request, data)
  } catch (error) { return json(request, { error: errorMessage(error) }, 400) }
})
