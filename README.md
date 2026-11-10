# RedeemHub

A React + TypeScript marketplace frontend with a Supabase/Postgres backend and server-verified Razorpay checkout. The repository intentionally contains no sample customer, product, inventory or payment records. With no backend credentials configured, the app runs in preview mode and disables account access and checkout.

## Run locally

```bash
cp .env.example .env.local
# Set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY after creating a Supabase project.
npm install
npm run dev
```

The public Supabase anon key is expected in the browser; the service-role key, payment secrets and inventory encryption keys must never use a `VITE_` prefix or enter the frontend build. `.env.local` is ignored by git. Build the static frontend with `npm run build`.

## Provision Supabase

1. Create a Supabase project in the intended region. Configure email verification, password reset redirect URLs and an appropriate email provider/rate limit in Auth.
2. Install the Supabase CLI and link this project using the authenticated project account. Review the migration in `supabase/migrations`, then apply it with `supabase db push`. The migration does not seed products, inventory, customer counts or promotional results.
3. Configure Edge Function secrets in the Supabase project dashboard or CLI secrets manager: `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `APP_ORIGIN`, `RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`, `RAZORPAY_WEBHOOK_SECRET`, `INVENTORY_ENCRYPTION_KEY` and `INVENTORY_FINGERPRINT_KEY`. Generate the two inventory keys from a cryptographically secure random source: AES key exactly 32 bytes; fingerprint key at least 32 bytes; encode each as base64. Preserve and back up them securely—losing the encryption key makes delivered and unsold code ciphertext unrecoverable.
4. Deploy the functions: `supabase functions deploy create-checkout`, `resume-checkout`, `verify-payment`, `razorpay-webhook`, `inventory-upload`, `order-codes`, `admin-metrics`, `admin-order-action`, and `admin-customer-status`. The Supabase function configuration disables Supabase JWT prevalidation only for `razorpay-webhook`; that endpoint independently verifies the Razorpay raw-body HMAC.
5. Assign the first admin only after verifying the operator identity. Create/sign up the intended admin account, look up that account's UUID in Supabase Auth, then execute from the trusted SQL editor: `insert into public.admin_roles(user_id, role) values ('<AUTH_USER_UUID>', 'admin');`. Never provide an admin role through browser signup metadata. Additional roles are `inventory_manager` and `support`.
6. Set `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in the static host's build environment; rebuild and deploy. Add the exact production origin to `APP_ORIGIN` and the Supabase Auth redirect allowlist.

## Razorpay / UPI

Use a Razorpay merchant account that is approved for the operator's digital-goods business. Begin with the provider's test credentials and test payments. Enable the UPI methods actually available to that merchant account in Razorpay Checkout. Configure a webhook at `https://<SUPABASE_PROJECT_REF>.supabase.co/functions/v1/razorpay-webhook`, subscribe to `payment.captured` and `payment.failed`, and use the distinct webhook secret as `RAZORPAY_WEBHOOK_SECRET`. The client only receives the publishable `RAZORPAY_KEY_ID`; the secret remains in Edge Function secrets.

The checkout endpoint re-reads active product prices, validates current stock, authorization confirmation, coupon rules and quantity, creates a pending order, then creates a Razorpay order for that exact INR amount. The browser response is not trusted: the verification endpoint checks the Razorpay checkout signature, fetches the payment using server credentials and checks captured status, provider order ID, INR currency and exact amount. The signed webhook is a second authenticated path. The Postgres fulfilment function locks candidate inventory rows, checks that every line can be fulfilled, then marks codes sold in the same transaction. If stock is short, it records verified payment and flags the order for manual resolution; it never sends another customer's or unallocated code. The fulfillment routine is idempotent.

Failed payment attempts do not mark an order paid or deliver codes. The order remains pending so the signed-in customer can resume the same Razorpay order from My Orders; promotion usage remains reserved until the order resolves. Configure an operational reconciliation and stale-order process before accepting live traffic. Refunds are not automatically sent by this starter; any refund must be handled through the provider's authorized workflow and recorded by the operator.

## Inventory and products

Create a category and product in the admin panel. For each product, enter correct pricing, region, expiry, compatibility, issuer instructions and terms. Confirm documented legal authorization for resale before publishing a product. Add authorized stock through the Inventory CSV panel (one redeem code per row; optional `code` header). Code plaintext is transmitted over HTTPS to the inventory-upload function, encrypted with AES-GCM before database insertion, and never returned in admin inventory listings. HMAC fingerprints detect duplicates without storing plaintext. Restrict access to the Supabase project and keep both inventory keys backed up.

## Data and access protections

The migration creates user/profile and admin-role records; categories and products; encrypted inventory; orders, line items and payments; referrals/rewards/settings; campaigns, coupons/usage; transaction ledger; support tickets; notifications; audit events; wishlists and reviews. Row-level security limits customer access to their own orders, codes (codes are released only by the authenticated `order-codes` Edge Function), referrals, rewards and tickets. The browser cannot write payment ledgers, orders, inventory allocation, admin roles or audit events directly. Service-role credentials are used only inside Edge Functions.

## Before production launch

- Run `npm run typecheck` and `npm run build`; test Auth email verification/password reset, a full Razorpay test payment, pending/failure webhooks, replay/idempotency, duplicate webhook delivery, stock exhaustion, duplicate inventory upload, coupon limits and customer-to-customer isolation.
- Review the SQL migration and Edge Functions with a qualified security reviewer; add independent monitoring/alerts, database backups, key rotation/recovery, rate limits, abuse controls and gateway reconciliation.
- Configure Supabase Auth email deliverability, rate limits, allowed origins and backups; restrict admin MFA and account recovery. Assign admins through a trusted channel only.
- Set actual business identity and support contact details; publish jurisdiction-specific privacy, terms, refund/cancellation and digital-delivery policies. Confirm each product is lawfully sourced/authorized for resale and make issuer/region restrictions prominent. No business identity or support address is invented in this project.
- Check applicable Indian consumer, privacy, tax, payments and gift-card rules with qualified counsel/provider compliance staff. Confirm payment provider approval, GST/invoicing and accounting requirements before switching to live keys.
- Use HTTPS, least-privilege project access, secure secrets management and a separate staging project. Never enable live checkout until test and compliance checks pass.

## Preview limitations

The standalone preview is a UI shell only until connected to a real Supabase project and an approved payment-gateway account. It deliberately shows no fictitious inventory, pricing, social proof, sales counts or payment-success state. A public static preview must not be used to accept orders until backend configuration, product authorization and legal details are complete.
