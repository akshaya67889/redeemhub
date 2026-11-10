export type Category = { id: string; name: string; slug: string; icon?: string | null; active: boolean }
export type Product = {
  id: string; category_id: string; name: string; slug: string; description: string | null;
  denomination: number | null; region: string | null; compatibility: string | null;
  expiry_info: string | null; redemption_instructions: string | null; terms: string | null;
  image_url: string | null; original_price: number; selling_price: number; stock_available: number;
  active: boolean; featured: boolean; authorized_resale_confirmed: boolean; created_at: string; categories?: Category | null
}
export type Campaign = { id: string; name: string; description: string | null; banner_url: string | null; discount_type: 'percentage' | 'fixed'; discount_value: number; coupon_code: string | null; starts_at: string; ends_at: string; status: string }
export type Order = { id: string; order_number: string; total_amount: number; payment_status: string; delivery_status: string; created_at: string; order_items?: { id: string; product_name: string; quantity: number; unit_price: number }[] }
export type Profile = { id: string; full_name: string | null; phone: string | null; referral_code: string | null; reward_balance: number }
export const money = (value: number) => new Intl.NumberFormat('en-IN', { style: 'currency', currency: 'INR', minimumFractionDigits: 0, maximumFractionDigits: 2 }).format(value)
export const discountPercent = (original: number, sale: number) => original > 0 ? Math.max(0, Math.round((original - sale) / original * 100)) : 0
