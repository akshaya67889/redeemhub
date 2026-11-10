import { authenticatedUser, errorMessage, handlePreflight, json, serviceClient } from '../_shared/http.ts'
import { decryptCode } from '../_shared/codes.ts'
Deno.serve(async (request) => {
  const preflight = handlePreflight(request); if (preflight) return preflight
  try {
    const user = await authenticatedUser(request); const body = await request.json(); const orderId = String(body.orderId || '')
    if (!orderId) return json(request, { error: 'Order ID is required' }, 400)
    const db = serviceClient(); const { data: order, error: orderError } = await db.from('orders').select('id,user_id,payment_status,delivery_status').eq('id', orderId).maybeSingle()
    if (orderError || !order || order.user_id !== user.id) return json(request, { error: 'Order not found' }, 404)
    if (order.payment_status !== 'paid' || order.delivery_status !== 'delivered') return json(request, { error: 'Codes are unavailable until verified payment and delivery' }, 403)
    const { data: items, error } = await db.from('redeem_code_inventory').select('code_ciphertext,code_iv,products(name)').eq('associated_order_id', order.id).eq('status', 'sold').order('delivery_timestamp')
    if (error) throw error
    const codes = await Promise.all((items || []).map(async (item: any) => ({ productName: item.products?.name || 'Digital code', code: await decryptCode(item.code_ciphertext, item.code_iv) })))
    if (!codes.length) return json(request, { error: 'No delivered code is attached to this order. Contact support.' }, 409)
    await db.from('audit_logs').insert({ actor_id: user.id, action: 'delivered_codes_viewed', entity_type: 'order', entity_id: order.id, metadata: { count: codes.length } })
    return json(request, { codes })
  } catch (error) { return json(request, { error: errorMessage(error) }, 400) }
})
