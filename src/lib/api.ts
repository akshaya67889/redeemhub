import { requireSupabase } from './supabase'
import type { Campaign, Category, Order, Product } from './types'

export async function getCatalog() {
  const db = requireSupabase()
  const [products, categories, campaigns] = await Promise.all([
    db.from('products').select('*, categories(id,name,slug,icon)').eq('active', true).order('featured', { ascending: false }).order('created_at', { ascending: false }),
    db.from('categories').select('id,name,slug,icon,active').eq('active', true).order('sort_order'),
    db.from('campaigns').select('id,name,description,banner_url,discount_type,discount_value,coupon_code,starts_at,ends_at,status').eq('status', 'active').lte('starts_at', new Date().toISOString()).gte('ends_at', new Date().toISOString()).order('ends_at'),
  ])
  if (products.error) throw products.error
  if (categories.error) throw categories.error
  if (campaigns.error) throw campaigns.error
  return { products: (products.data ?? []) as unknown as Product[], categories: (categories.data ?? []) as Category[], campaigns: (campaigns.data ?? []) as Campaign[] }
}

export async function getOrders(): Promise<Order[]> {
  const { data, error } = await requireSupabase().from('orders').select('id,order_number,total_amount,payment_status,delivery_status,created_at,order_items(id,product_name,quantity,unit_price)').order('created_at', { ascending: false })
  if (error) throw error
  return (data ?? []) as unknown as Order[]
}

export async function startCheckout(items: { productId: string; quantity: number }[], couponCode?: string) {
  const { data, error } = await requireSupabase().functions.invoke('create-checkout', { body: { items, couponCode: couponCode || null } })
  if (error) throw error
  return data as { orderId: string; orderNumber: string; razorpayOrderId: string; amount: number; subtotal: number; discountAmount: number; currency: 'INR'; keyId: string; customerEmail: string }
}

export async function resumeCheckout(orderId: string) {
  const { data, error } = await requireSupabase().functions.invoke('resume-checkout', { body: { orderId } })
  if (error) throw error
  return data as { orderId: string; orderNumber: string; razorpayOrderId: string; amount: number; subtotal: number; discountAmount: number; currency: 'INR'; keyId: string; customerEmail: string }
}

export async function verifyPayment(payload: { razorpay_order_id: string; razorpay_payment_id: string; razorpay_signature: string; orderId: string }) {
  const { data, error } = await requireSupabase().functions.invoke('verify-payment', { body: payload })
  if (error) throw error
  return data as { status: string; deliveryStatus: string }
}

export async function getOrderCodes(orderId: string) {
  const { data, error } = await requireSupabase().functions.invoke('order-codes', { body: { orderId } })
  if (error) throw error
  return data as { codes: { productName: string; code: string }[] }
}

export async function submitSupport(input: { orderId?: string; subject: string; message: string; category: string }) {
  const { error } = await requireSupabase().from('support_tickets').insert({ ...input, order_id: input.orderId || null })
  if (error) throw error
}
