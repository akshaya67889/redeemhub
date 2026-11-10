import { createClient, type SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2.57.0'

const projectUrl = Deno.env.get('SUPABASE_URL')!
const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const configuredOrigin = Deno.env.get('APP_ORIGIN')

export function corsHeaders(request: Request) {
  const origin = request.headers.get('Origin') || ''
  const allowed = configuredOrigin ? origin === configuredOrigin : true
  return {
    'Access-Control-Allow-Origin': configuredOrigin ? (allowed ? configuredOrigin : 'null') : '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-razorpay-signature',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Vary': 'Origin',
  }
}
export function json(request: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders(request), 'Content-Type': 'application/json', 'Cache-Control': 'no-store' } })
}
export function serviceClient(): SupabaseClient {
  return createClient(projectUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } })
}
export async function authenticatedUser(request: Request) {
  const header = request.headers.get('Authorization') || ''
  if (!header.startsWith('Bearer ')) throw new Error('Authentication required')
  const token = header.slice(7)
  const client = createClient(projectUrl, anonKey, { auth: { persistSession: false, autoRefreshToken: false } })
  const { data, error } = await client.auth.getUser(token)
  if (error || !data.user) throw new Error('Invalid or expired session')
  return data.user
}
export async function requireAdmin(userId: string, db = serviceClient()) {
  const { data, error } = await db.from('admin_roles').select('role').eq('user_id', userId).maybeSingle()
  if (error || !data) throw new Error('Administrator access required')
  return data.role as string
}
export function handlePreflight(request: Request) {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(request) })
  if (request.method !== 'POST') return json(request, { error: 'Method not allowed' }, 405)
  if (Deno.env.get('APP_ORIGIN') && request.headers.get('Origin') !== Deno.env.get('APP_ORIGIN')) return json(request, { error: 'Origin not allowed' }, 403)
  return null
}
export function errorMessage(error: unknown) { return error instanceof Error ? error.message : 'Request could not be completed' }
