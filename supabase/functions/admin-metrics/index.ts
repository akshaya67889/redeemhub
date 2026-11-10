import { authenticatedUser, errorMessage, handlePreflight, json, requireAdmin, serviceClient } from '../_shared/http.ts'
Deno.serve(async (request) => {
  const preflight = handlePreflight(request); if (preflight) return preflight
  try {
    const user = await authenticatedUser(request); const db = serviceClient(); await requireAdmin(user.id, db)
    const start = new Date(new Date().toLocaleDateString('en-CA', { timeZone: 'Asia/Kolkata' }) + 'T00:00:00+05:30').toISOString()
    const [customers,orders,todayOrders,sales,pending,available,sold,campaigns,referrals,qualified] = await Promise.all([
      db.from('users').select('*',{count:'exact',head:true}).eq('status','active'),
      db.from('orders').select('*',{count:'exact',head:true}),
      db.from('orders').select('*',{count:'exact',head:true}).gte('created_at',start),
      db.from('orders').select('total_amount').eq('payment_status','paid'),
      db.from('orders').select('*',{count:'exact',head:true}).eq('payment_status','pending'),
      db.from('redeem_code_inventory').select('*',{count:'exact',head:true}).eq('status','available'),
      db.from('redeem_code_inventory').select('*',{count:'exact',head:true}).eq('status','sold'),
      db.from('campaigns').select('*',{count:'exact',head:true}).eq('status','active').lte('starts_at',new Date().toISOString()).gt('ends_at',new Date().toISOString()),
      db.from('referrals').select('*',{count:'exact',head:true}),
      db.from('referrals').select('*',{count:'exact',head:true}).eq('status','qualified'),
    ])
    const firstError = [customers,orders,todayOrders,sales,pending,available,sold,campaigns,referrals,qualified].find(x => x.error)
    if (firstError?.error) throw firstError.error
    const totalSales = (sales.data || []).reduce((sum: number,row: any) => sum + Number(row.total_amount || 0),0)
    return json(request,{ customers:customers.count||0, orders:orders.count||0, today_orders:todayOrders.count||0, total_sales:totalSales.toFixed(2), pending_payments:pending.count||0, available_inventory:available.count||0, sold_inventory:sold.count||0, active_campaigns:campaigns.count||0, referrals:referrals.count||0, qualified_referrals:qualified.count||0 })
  } catch (error) { return json(request,{ error:errorMessage(error) },403) }
})
