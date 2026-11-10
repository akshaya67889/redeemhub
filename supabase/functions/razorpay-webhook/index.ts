import { errorMessage, handlePreflight, json, serviceClient } from '../_shared/http.ts'
function hex(bytes: Uint8Array) { return [...bytes].map(v => v.toString(16).padStart(2, '0')).join('') }
async function hmacHex(secret: string, message: string) { const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']); return hex(new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(message)))) }
function equal(a: string,b: string) { if(a.length!==b.length)return false; let x=0; for(let i=0;i<a.length;i++) x|=a.charCodeAt(i)^b.charCodeAt(i); return x===0 }
Deno.serve(async (request) => {
  const preflight = handlePreflight(request); if (preflight) return preflight
  try {
    const raw = await request.text(); const signature = request.headers.get('x-razorpay-signature') || ''; const secret = Deno.env.get('RAZORPAY_WEBHOOK_SECRET')
    if (!secret || !signature) return json(request, { error: 'Webhook verification is not configured' }, 503)
    const expected = await hmacHex(secret, raw)
    if (!equal(expected, signature.toLowerCase())) return json(request, { error: 'Invalid webhook signature' }, 401)
    const event = JSON.parse(raw); const entity = event?.payload?.payment?.entity
    if (event.event === 'payment.captured' && entity?.id && entity?.order_id) {
      const db = serviceClient(); const { data, error } = await db.rpc('fulfill_verified_payment', { p_provider_order_id: entity.order_id, p_provider_payment_id: entity.id, p_amount_paise: Number(entity.amount), p_currency: String(entity.currency), p_event: { event: event.event, id: event.id, created_at: event.created_at } })
      if (error) throw error
      return json(request, { received: true, result: data })
    }
    if (event.event === 'payment.failed' && entity?.id && entity?.order_id) {
      const db = serviceClient(); const { data: payment, error: lookupError } = await db.from('payments').select('id,order_id').eq('provider_order_id', entity.order_id).maybeSingle()
      if (lookupError) throw lookupError
      if (payment) {
        const { error: updateError } = await db.from('payments').update({ provider_payment_id: entity.id, status: 'failed', failure_reason: String(entity.error_description || 'Payment failed').slice(0,300), raw_event: { event: event.event, id: event.id }, updated_at: new Date().toISOString() }).eq('id', payment.id).neq('status','captured')
        if (updateError) throw updateError
        // The Razorpay order remains open for another payment attempt. Keep the internal order and coupon reservation pending.
      }
    }
    return json(request, { received: true })
  } catch (error) { return json(request, { error: errorMessage(error) }, 400) }
})
