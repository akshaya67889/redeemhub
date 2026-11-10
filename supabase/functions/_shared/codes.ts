function decodeBase64(value: string) { return Uint8Array.from(atob(value), c => c.charCodeAt(0)) }
function encodeBase64(value: Uint8Array) { let binary = ''; for (const byte of value) binary += String.fromCharCode(byte); return btoa(binary) }
async function importAesKey() {
  const secret = Deno.env.get('INVENTORY_ENCRYPTION_KEY')
  if (!secret) throw new Error('INVENTORY_ENCRYPTION_KEY is not configured')
  const raw = decodeBase64(secret)
  if (raw.byteLength !== 32) throw new Error('INVENTORY_ENCRYPTION_KEY must be base64 for exactly 32 random bytes')
  return crypto.subtle.importKey('raw', raw, 'AES-GCM', false, ['encrypt','decrypt'])
}
async function importFingerprintKey() {
  const secret = Deno.env.get('INVENTORY_FINGERPRINT_KEY')
  if (!secret) throw new Error('INVENTORY_FINGERPRINT_KEY is not configured')
  const raw = decodeBase64(secret)
  if (raw.byteLength < 32) throw new Error('INVENTORY_FINGERPRINT_KEY must be base64 for at least 32 random bytes')
  return crypto.subtle.importKey('raw', raw, { name: 'HMAC', hash: 'SHA-256' }, false, ['sign'])
}
export async function encryptCode(code: string) {
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const encrypted = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, await importAesKey(), new TextEncoder().encode(code))
  const fingerprint = await crypto.subtle.sign('HMAC', await importFingerprintKey(), new TextEncoder().encode(code.normalize('NFKC').trim()))
  return { code_ciphertext: encodeBase64(new Uint8Array(encrypted)), code_iv: encodeBase64(iv), code_fingerprint: encodeBase64(new Uint8Array(fingerprint)) }
}
export async function decryptCode(ciphertext: string, iv: string) {
  const raw = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: decodeBase64(iv) }, await importAesKey(), decodeBase64(ciphertext))
  return new TextDecoder().decode(raw)
}
