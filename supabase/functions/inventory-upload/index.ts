import { authenticatedUser, errorMessage, handlePreflight, json, requireAdmin, serviceClient } from '../_shared/http.ts'
import { encryptCode } from '../_shared/codes.ts'
Deno.serve(async (request) => {
  const preflight = handlePreflight(request); if (preflight) return preflight
  try {
    const user = await authenticatedUser(request); const db = serviceClient(); const role = await requireAdmin(user.id, db)
    if (!['admin','inventory_manager'].includes(role)) return json(request, { error: 'Inventory manager role required' }, 403)
    const body = await request.json(); const productId = String(body.productId || ''); const rawCodes = body.codes
    if (!productId || !Array.isArray(rawCodes) || rawCodes.length < 1 || rawCodes.length > 2000) return json(request, { error: 'Provide a product and 1–2,000 codes' }, 400)
    const { data: product, error: productError } = await db.from('products').select('id').eq('id', productId).maybeSingle()
    if (productError || !product) return json(request, { error: 'Product not found' }, 404)
    const codes = [...new Set(rawCodes.map((value: unknown) => String(value).normalize('NFKC').trim()).filter((value: string) => value.length > 0 && value.length <= 500))]
    let inserted = 0; let duplicates = 0
    for (let i=0; i<codes.length; i+=100) {
      const rows = await Promise.all(codes.slice(i,i+100).map(async (code: string) => ({ product_id: productId, ...await encryptCode(code), uploaded_by: user.id, status: 'available' })))
      const { data, error } = await db.from('redeem_code_inventory').insert(rows).select('id')
      if (!error) { inserted += data?.length || rows.length; continue }
      if (error.code === '23505') {
        for (const row of rows) { const { error: oneError } = await db.from('redeem_code_inventory').insert(row); if (oneError?.code === '23505') duplicates++; else if (oneError) throw oneError; else inserted++ }
      } else throw error
    }
    await db.from('audit_logs').insert({ actor_id: user.id, action: 'inventory_uploaded', entity_type: 'product', entity_id: productId, metadata: { inserted, duplicates } })
    return json(request, { inserted, duplicates })
  } catch (error) { return json(request, { error: errorMessage(error) }, 400) }
})
