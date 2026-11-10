import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL?.trim()
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY?.trim()
export const isConfigured = Boolean(url && anonKey && !url.includes('your-project'))
export const supabase = isConfigured
  ? createClient(url!, anonKey!, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } })
  : null

export function requireSupabase() {
  if (!supabase) throw new Error('RedeemHub is not connected to Supabase yet. Configure the public Supabase URL and anon key to enable live service.')
  return supabase
}
