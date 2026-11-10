-- RedeemHub initial schema. Apply with `supabase db push` after linking the intended project.
-- Sensitive code values are encrypted by Edge Functions before insertion.
create extension if not exists pgcrypto with schema extensions;

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  status text not null default 'active' check (status in ('active','suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  referral_code text not null unique,
  reward_balance numeric(12,2) not null default 0 check (reward_balance >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.admin_roles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null default 'admin' check (role in ('admin','support','inventory_manager')),
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);

create table public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  icon text,
  sort_order integer not null default 0,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id),
  name text not null,
  slug text not null unique,
  description text,
  denomination numeric(12,2) check (denomination is null or denomination >= 0),
  region text,
  compatibility text,
  expiry_info text,
  redemption_instructions text,
  terms text,
  image_url text,
  original_price numeric(12,2) not null check (original_price > 0),
  selling_price numeric(12,2) not null check (selling_price > 0 and selling_price <= original_price),
  stock_available integer not null default 0 check (stock_available >= 0),
  active boolean not null default false,
  featured boolean not null default false,
  authorized_resale_confirmed boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index products_public_idx on public.products(active, featured desc, created_at desc);
create index products_category_idx on public.products(category_id, active);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  order_number text not null unique,
  user_id uuid not null references auth.users(id),
  subtotal numeric(12,2) not null check (subtotal >= 0),
  discount_amount numeric(12,2) not null default 0 check (discount_amount >= 0),
  total_amount numeric(12,2) not null check (total_amount >= 0),
  currency text not null default 'INR' check (currency = 'INR'),
  payment_status text not null default 'pending' check (payment_status in ('pending','paid','failed','cancelled','refund_pending','refunded','inventory_pending')),
  delivery_status text not null default 'pending' check (delivery_status in ('pending','delivered','inventory_pending','cancelled')),
  razorpay_order_id text unique,
  paid_at timestamptz,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index orders_user_created_idx on public.orders(user_id, created_at desc);
create index orders_payment_created_idx on public.orders(payment_status, created_at desc);
create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id),
  product_name text not null,
  quantity integer not null check (quantity between 1 and 10),
  unit_price numeric(12,2) not null check (unit_price > 0),
  line_total numeric(12,2) not null check (line_total > 0),
  created_at timestamptz not null default now()
);
create index order_items_order_idx on public.order_items(order_id);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id),
  provider text not null default 'razorpay',
  provider_order_id text not null unique,
  provider_payment_id text unique,
  amount_paise bigint not null check (amount_paise > 0),
  currency text not null default 'INR' check (currency = 'INR'),
  status text not null default 'created' check (status in ('created','authorized','captured','failed','refunded')),
  failure_reason text,
  raw_event jsonb,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index payments_order_idx on public.payments(order_id, created_at desc);

create table public.redeem_code_inventory (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id),
  code_ciphertext text not null,
  code_iv text not null,
  code_fingerprint text not null,
  status text not null default 'available' check (status in ('available','reserved','sold')),
  associated_order_id uuid references public.orders(id),
  uploaded_by uuid references auth.users(id),
  upload_date timestamptz not null default now(),
  delivery_timestamp timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((status = 'available' and associated_order_id is null and delivery_timestamp is null) or status in ('reserved','sold'))
);
create unique index inventory_fingerprint_product_uq on public.redeem_code_inventory(product_id, code_fingerprint);
create index inventory_available_product_idx on public.redeem_code_inventory(product_id, upload_date) where status = 'available';
create index inventory_order_idx on public.redeem_code_inventory(associated_order_id) where associated_order_id is not null;

create table public.coupons (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  discount_type text not null check (discount_type in ('percentage','fixed')),
  discount_value numeric(12,2) not null check (discount_value > 0),
  minimum_order_value numeric(12,2) not null default 0 check (minimum_order_value >= 0),
  maximum_discount numeric(12,2) check (maximum_discount is null or maximum_discount >= 0),
  product_ids uuid[] not null default '{}',
  usage_limit integer check (usage_limit is null or usage_limit > 0),
  per_user_limit integer not null default 1 check (per_user_limit > 0),
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  check (expires_at is null or expires_at > starts_at)
);
create table public.coupon_usage (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.coupons(id),
  user_id uuid not null references auth.users(id),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  status text not null default 'reserved' check (status in ('reserved','used','released')),
  created_at timestamptz not null default now(),
  used_at timestamptz,
  unique(coupon_id, user_id, order_id)
);
create index coupon_usage_limits_idx on public.coupon_usage(coupon_id, status, user_id);

create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  banner_url text,
  discount_type text not null default 'percentage' check (discount_type in ('percentage','fixed')),
  discount_value numeric(12,2) not null default 0 check (discount_value >= 0),
  eligible_product_ids uuid[] not null default '{}',
  coupon_code text,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status text not null default 'scheduled' check (status in ('scheduled','active','paused','ended')),
  usage_limit integer check (usage_limit is null or usage_limit > 0),
  minimum_order_value numeric(12,2) not null default 0 check (minimum_order_value >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index campaigns_window_idx on public.campaigns(status, starts_at, ends_at);

alter table public.orders add column applied_campaign_id uuid references public.campaigns(id);
create table public.campaign_usage (
  id uuid primary key default gen_random_uuid(),
  campaign_id uuid not null references public.campaigns(id),
  user_id uuid not null references auth.users(id),
  order_id uuid not null unique references public.orders(id) on delete cascade,
  status text not null default 'reserved' check (status in ('reserved','used','released')),
  created_at timestamptz not null default now(),
  used_at timestamptz
);
create index campaign_usage_limit_idx on public.campaign_usage(campaign_id,status);

create table public.referrals (
  id uuid primary key default gen_random_uuid(),
  referrer_id uuid not null references auth.users(id),
  referred_user_id uuid not null unique references auth.users(id),
  referral_code text not null,
  status text not null default 'registered' check (status in ('registered','qualified','rejected')),
  created_at timestamptz not null default now(),
  qualified_at timestamptz,
  check (referrer_id <> referred_user_id)
);
create index referrals_referrer_idx on public.referrals(referrer_id, created_at desc);
create table public.referral_rewards (
  id uuid primary key default gen_random_uuid(),
  referral_id uuid references public.referrals(id),
  user_id uuid not null references auth.users(id),
  reward_type text not null check (reward_type in ('registration','first_purchase','milestone','adjustment')),
  amount numeric(12,2) not null check (amount >= 0),
  status text not null default 'credited' check (status in ('pending','credited','reversed')),
  idempotency_key text not null unique,
  created_at timestamptz not null default now(),
  created_by uuid references auth.users(id)
);
create index referral_rewards_user_idx on public.referral_rewards(user_id, created_at desc);
create table public.referral_settings (
  id boolean primary key default true check (id),
  registration_reward numeric(12,2) not null default 0 check (registration_reward >= 0),
  first_purchase_reward numeric(12,2) not null default 0 check (first_purchase_reward >= 0),
  milestone_count integer not null default 5 check (milestone_count > 0),
  milestone_reward numeric(12,2) not null default 0 check (milestone_reward >= 0),
  qualifying_order_minimum numeric(12,2) not null default 0 check (qualifying_order_minimum >= 0),
  enabled boolean not null default false,
  updated_at timestamptz not null default now()
);
insert into public.referral_settings(id) values (true) on conflict do nothing;

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id),
  order_id uuid references public.orders(id),
  type text not null check (type in ('payment','refund','referral_reward','adjustment')),
  amount numeric(12,2) not null,
  currency text not null default 'INR',
  status text not null,
  reference text,
  idempotency_key text not null unique,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index transactions_user_created_idx on public.transactions(user_id, created_at desc);

create table public.support_tickets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  order_id uuid references public.orders(id),
  category text not null check (category in ('invalid_code','payment','delivery','refund','other')),
  subject text not null check (length(subject) between 1 and 120),
  message text not null check (length(message) between 8 and 4000),
  status text not null default 'open' check (status in ('open','in_progress','resolved','closed')),
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index support_user_created_idx on public.support_tickets(user_id, created_at desc);
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id),
  type text not null,
  title text not null,
  body text not null,
  read_at timestamptz,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index notifications_user_created_idx on public.notifications(user_id, created_at desc);
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references auth.users(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index audit_entity_idx on public.audit_logs(entity_type, entity_id, created_at desc);
create table public.wishlists (
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key(user_id, product_id)
);
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  body text check (body is null or length(body) <= 500),
  visible boolean not null default false,
  created_at timestamptz not null default now(),
  unique(product_id, user_id)
);

create or replace function public.has_admin_role()
returns boolean language sql stable security definer set search_path = public
as $$ select exists (select 1 from public.admin_roles where user_id = auth.uid() and role = 'admin') $$;
revoke all on function public.has_admin_role() from public;
grant execute on function public.has_admin_role() to anon, authenticated, service_role;

create or replace function public.set_updated_at()
returns trigger language plpgsql set search_path = public
as $$ begin new.updated_at = now(); return new; end $$;
create or replace function public.sync_inventory_stock()
returns trigger language plpgsql security definer set search_path = public
as $$
declare v_product uuid;
begin
  v_product := coalesce(new.product_id, old.product_id);
  update public.products p set stock_available = (select count(*)::integer from public.redeem_code_inventory i where i.product_id = v_product and i.status = 'available'), updated_at = now() where p.id = v_product;
  if tg_op = 'UPDATE' and old.product_id <> new.product_id then
    update public.products p set stock_available = (select count(*)::integer from public.redeem_code_inventory i where i.product_id = old.product_id and i.status = 'available'), updated_at = now() where p.id = old.product_id;
  end if;
  return coalesce(new, old);
end $$;
create or replace function public.on_auth_user_created()
returns trigger language plpgsql security definer set search_path = public, extensions
as $$
declare v_code text; v_referrer uuid; v_ref_code text;
begin
  insert into public.users(id,email) values (new.id, coalesce(new.email,'')) on conflict (id) do update set email = excluded.email;
  v_code := 'RH' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  insert into public.profiles(id,full_name,referral_code) values (new.id, nullif(new.raw_user_meta_data->>'full_name',''), v_code);
  v_ref_code := upper(trim(coalesce(new.raw_user_meta_data->>'referral_code','')));
  if v_ref_code <> '' then
    select p.id into v_referrer from public.profiles p where upper(p.referral_code) = v_ref_code and p.id <> new.id limit 1;
    if v_referrer is not null then
      insert into public.referrals(referrer_id,referred_user_id,referral_code) values (v_referrer,new.id,v_ref_code) on conflict (referred_user_id) do nothing;
    end if;
  end if;
  return new;
end $$;
create trigger auth_user_created after insert on auth.users for each row execute function public.on_auth_user_created();
create trigger inventory_stock_change after insert or update or delete on public.redeem_code_inventory for each row execute function public.sync_inventory_stock();

create or replace function public.reward_verified_referral_registration()
returns trigger language plpgsql security definer set search_path = public
as $$
declare v_ref public.referrals%rowtype; v_settings public.referral_settings%rowtype; v_inserted integer;
begin
  if old.email_confirmed_at is null and new.email_confirmed_at is not null then
    select * into v_settings from public.referral_settings where id=true;
    if coalesce(v_settings.enabled,false) and coalesce(v_settings.registration_reward,0)>0 then
      select * into v_ref from public.referrals where referred_user_id=new.id and status='registered' for update;
      if found then
        insert into public.referral_rewards(referral_id,user_id,reward_type,amount,idempotency_key) values(v_ref.id,v_ref.referrer_id,'registration',v_settings.registration_reward,'referral-registration:'||v_ref.id::text) on conflict(idempotency_key) do nothing;
        get diagnostics v_inserted = row_count;
        if v_inserted=1 then update public.profiles set reward_balance=reward_balance+v_settings.registration_reward where id=v_ref.referrer_id; end if;
      end if;
    end if;
  end if;
  return new;
end $$;
create trigger verified_referral_registration after update of email_confirmed_at on auth.users for each row execute function public.reward_verified_referral_registration();

create or replace function public.create_checkout_order(p_user_id uuid, p_items jsonb, p_coupon_code text default null)
returns jsonb language plpgsql security definer set search_path = public
as $$
declare v_order_id uuid := gen_random_uuid(); v_order_number text; v_subtotal numeric(12,2) := 0; v_discount numeric(12,2) := 0; v_total numeric(12,2); v_item jsonb; v_product public.products%rowtype; v_qty integer; v_coupon public.coupons%rowtype; v_campaign public.campaigns%rowtype; v_campaign_id uuid; v_campaign_discount numeric(12,2) := 0; v_candidate_discount numeric(12,2); v_campaign_eligible numeric(12,2); v_campaign_used integer; v_used integer; v_user_used integer; v_eligible_total numeric(12,2) := 0;
begin
  if p_user_id is null or jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items) not between 1 and 10 then raise exception 'Invalid checkout request'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_user_id::text,1));
  if exists (select 1 from public.users where id=p_user_id and status <> 'active') then raise exception 'Account unavailable'; end if;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    if v_qty not between 1 and 10 then raise exception 'Quantity is outside the allowed range'; end if;
    select * into v_product from public.products where id=(v_item->>'productId')::uuid and active=true for share;
    if not found then raise exception 'A product is unavailable'; end if;
    if v_product.stock_available < v_qty then raise exception 'Insufficient stock for %',v_product.name; end if;
    if v_product.authorized_resale_confirmed is false then raise exception 'Product resale authorization has not been verified'; end if;
    if exists (select 1 from public.order_items oi join public.orders o on o.id=oi.order_id where o.user_id=p_user_id and o.payment_status in ('pending','paid') and oi.product_id=v_product.id and o.created_at > now()-interval '10 minutes') then
      raise exception 'A recent order already contains this item';
    end if;
    v_subtotal := v_subtotal + v_product.selling_price * v_qty;
  end loop;
  if p_coupon_code is not null and btrim(p_coupon_code) <> '' then
    select * into v_coupon from public.coupons where code=upper(btrim(p_coupon_code)) and enabled=true and starts_at <= now() and (expires_at is null or expires_at > now()) for update;
    if not found then raise exception 'Coupon is invalid or expired'; end if;
    if v_subtotal < v_coupon.minimum_order_value then raise exception 'Order does not meet the coupon minimum'; end if;
    select count(*) into v_used from public.coupon_usage where coupon_id=v_coupon.id and status in ('reserved','used');
    if v_coupon.usage_limit is not null and v_used >= v_coupon.usage_limit then raise exception 'Coupon usage limit reached'; end if;
    select count(*) into v_user_used from public.coupon_usage where coupon_id=v_coupon.id and user_id=p_user_id and status in ('reserved','used');
    if v_user_used >= v_coupon.per_user_limit then raise exception 'Coupon use limit reached for this account'; end if;
    if cardinality(v_coupon.product_ids) = 0 then v_eligible_total := v_subtotal;
    else
      for v_item in select value from jsonb_array_elements(p_items) loop
        select * into v_product from public.products where id=(v_item->>'productId')::uuid;
        if v_product.id = any(v_coupon.product_ids) then v_eligible_total := v_eligible_total + v_product.selling_price * (v_item->>'quantity')::integer; end if;
      end loop;
    end if;
    if v_eligible_total = 0 then raise exception 'Coupon does not apply to these products'; end if;
    if v_coupon.discount_type = 'percentage' then v_discount := round(v_eligible_total * v_coupon.discount_value / 100,2); else v_discount := least(v_coupon.discount_value,v_eligible_total); end if;
    if v_coupon.maximum_discount is not null then v_discount := least(v_discount,v_coupon.maximum_discount); end if;
    v_discount := least(v_discount,v_subtotal);
  end if;
  -- When no coupon is entered, apply the best currently active campaign that has no code gate.
  if p_coupon_code is null or btrim(p_coupon_code) = '' then
    for v_campaign in select * from public.campaigns where status='active' and starts_at<=now() and ends_at>now() and coupon_code is null and minimum_order_value<=v_subtotal order by discount_value desc for update loop
      v_campaign_eligible := 0;
      if cardinality(v_campaign.eligible_product_ids)=0 then v_campaign_eligible := v_subtotal;
      else
        for v_item in select value from jsonb_array_elements(p_items) loop
          select * into v_product from public.products where id=(v_item->>'productId')::uuid;
          if v_product.id=any(v_campaign.eligible_product_ids) then v_campaign_eligible := v_campaign_eligible + v_product.selling_price*(v_item->>'quantity')::integer; end if;
        end loop;
      end if;
      if v_campaign_eligible>0 then
        select count(*) into v_campaign_used from public.campaign_usage where campaign_id=v_campaign.id and status in ('reserved','used');
        if v_campaign.usage_limit is null or v_campaign_used<v_campaign.usage_limit then
          if v_campaign.discount_type='percentage' then v_candidate_discount := round(v_campaign_eligible*v_campaign.discount_value/100,2); else v_candidate_discount := least(v_campaign.discount_value,v_campaign_eligible); end if;
          v_candidate_discount := least(v_candidate_discount,v_campaign_eligible);
          if v_candidate_discount>v_campaign_discount then v_campaign_discount := v_candidate_discount; v_campaign_id := v_campaign.id; end if;
        end if;
      end if;
    end loop;
    if v_campaign_id is not null then v_discount := greatest(v_discount,coalesce(v_campaign_discount,0)); end if;
  end if;
  v_total := greatest(0,v_subtotal-v_discount);
  if v_total<=0 then raise exception 'Final amount must be greater than zero'; end if;
  v_order_number := 'RH-' || to_char(now() at time zone 'Asia/Kolkata','YYYYMMDD') || '-' || upper(substr(replace(v_order_id::text,'-',''),1,8));
  insert into public.orders(id,order_number,user_id,subtotal,discount_amount,total_amount,applied_campaign_id) values(v_order_id,v_order_number,p_user_id,v_subtotal,v_discount,v_total,v_campaign_id);
  for v_item in select value from jsonb_array_elements(p_items) loop
    select * into v_product from public.products where id=(v_item->>'productId')::uuid;
    v_qty := (v_item->>'quantity')::integer;
    insert into public.order_items(order_id,product_id,product_name,quantity,unit_price,line_total) values(v_order_id,v_product.id,v_product.name,v_qty,v_product.selling_price,v_product.selling_price*v_qty);
  end loop;
  if p_coupon_code is not null and btrim(p_coupon_code) <> '' then
    insert into public.coupon_usage(coupon_id,user_id,order_id,status) values(v_coupon.id,p_user_id,v_order_id,'reserved');
  end if;
  if v_campaign_id is not null then insert into public.campaign_usage(campaign_id,user_id,order_id,status) values(v_campaign_id,p_user_id,v_order_id,'reserved'); end if;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,metadata) values(p_user_id,'order_created','order',v_order_id,jsonb_build_object('order_number',v_order_number,'total',v_total));
  return jsonb_build_object('id',v_order_id,'order_number',v_order_number,'subtotal',v_subtotal,'discount_amount',v_discount,'amount',v_total,'currency','INR');
end $$;
revoke all on function public.create_checkout_order(uuid,jsonb,text) from public, anon, authenticated;
grant execute on function public.create_checkout_order(uuid,jsonb,text) to service_role;

create or replace function public.bind_razorpay_order(p_order_id uuid,p_provider_order_id text,p_amount_paise bigint)
returns void language plpgsql security definer set search_path = public
as $$
begin
  update public.orders set razorpay_order_id=p_provider_order_id,updated_at=now() where id=p_order_id and payment_status='pending' and round(total_amount*100)::bigint=p_amount_paise;
  if not found then raise exception 'Order amount or state mismatch'; end if;
  insert into public.payments(order_id,provider_order_id,amount_paise,status) values(p_order_id,p_provider_order_id,p_amount_paise,'created');
end $$;
revoke all on function public.bind_razorpay_order(uuid,text,bigint) from public, anon, authenticated;
grant execute on function public.bind_razorpay_order(uuid,text,bigint) to service_role;

create or replace function public.fulfill_verified_payment(p_provider_order_id text,p_provider_payment_id text,p_amount_paise bigint,p_currency text,p_event jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = public
as $$
declare v_payment public.payments%rowtype; v_order public.orders%rowtype; v_item record; v_ids uuid[]; v_plan jsonb := '[]'::jsonb; v_entry jsonb; v_inventory_id uuid; v_short boolean := false; v_reward_setting public.referral_settings%rowtype; v_ref public.referrals%rowtype; v_first boolean; v_qualified integer; v_inserted integer;
begin
  select * into v_payment from public.payments where provider_order_id=p_provider_order_id for update;
  if not found then raise exception 'Unknown payment order'; end if;
  select * into v_order from public.orders where id=v_payment.order_id for update;
  if not found or v_order.razorpay_order_id <> p_provider_order_id then raise exception 'Order binding mismatch'; end if;
  if p_currency <> 'INR' or p_amount_paise <> v_payment.amount_paise or p_amount_paise <> round(v_order.total_amount*100)::bigint then raise exception 'Payment amount/currency mismatch'; end if;
  if v_order.payment_status='paid' and v_order.delivery_status='delivered' then return jsonb_build_object('status','paid','deliveryStatus',v_order.delivery_status,'orderNumber',v_order.order_number,'idempotent',true); end if;
  if v_order.payment_status not in ('pending','paid') then raise exception 'Order is not payable'; end if;
  if v_order.payment_status<>'paid' then
    update public.payments set provider_payment_id=p_provider_payment_id,status='captured',verified_at=now(),raw_event=p_event,updated_at=now() where id=v_payment.id;
    update public.orders set payment_status='paid',paid_at=coalesce(paid_at,now()),updated_at=now() where id=v_order.id;
    insert into public.transactions(user_id,order_id,type,amount,status,reference,idempotency_key,metadata) values(v_order.user_id,v_order.id,'payment',v_order.total_amount,'verified',p_provider_payment_id,'payment:'||p_provider_payment_id,jsonb_build_object('provider','razorpay')) on conflict(idempotency_key) do nothing;
  end if;
  -- Build a complete allocation plan while locking candidates. Nothing is sold unless every order line has enough stock.
  for v_item in select * from public.order_items where order_id=v_order.id order by product_id loop
    select array_agg(id) into v_ids from (
      select id from public.redeem_code_inventory where product_id=v_item.product_id and status='available' order by upload_date,id limit v_item.quantity for update skip locked
    ) candidates;
    if coalesce(cardinality(v_ids),0) < v_item.quantity then v_short := true; exit; end if;
    v_plan := v_plan || jsonb_build_array(jsonb_build_object('item_id',v_item.id,'inventory_ids',to_jsonb(v_ids)));
  end loop;
  if v_short then
    update public.orders set delivery_status='inventory_pending',updated_at=now() where id=v_order.id;
    update public.coupon_usage set status='used',used_at=now() where order_id=v_order.id and status='reserved';
    update public.campaign_usage set status='used',used_at=now() where order_id=v_order.id and status='reserved';
    insert into public.notifications(user_id,type,title,body,metadata) values(v_order.user_id,'delivery_review','Payment verified — delivery under review','Your payment is confirmed. Our team will resolve the stock issue or contact you about a refund.',jsonb_build_object('order_id',v_order.id));
    insert into public.audit_logs(action,entity_type,entity_id,metadata) values('payment_verified_inventory_shortage','order',v_order.id,jsonb_build_object('payment_id',p_provider_payment_id));
    return jsonb_build_object('status','paid','deliveryStatus','inventory_pending','orderNumber',v_order.order_number);
  end if;
  for v_entry in select value from jsonb_array_elements(v_plan) loop
    for v_inventory_id in select jsonb_array_elements_text(v_entry->'inventory_ids')::uuid loop
      update public.redeem_code_inventory set status='sold',associated_order_id=v_order.id,delivery_timestamp=now(),updated_at=now() where id=v_inventory_id and status='available';
      if not found then raise exception 'Inventory allocation conflict'; end if;
    end loop;
  end loop;
  update public.orders set delivery_status='delivered',delivered_at=now(),updated_at=now() where id=v_order.id;
  update public.coupon_usage set status='used',used_at=now() where order_id=v_order.id and status='reserved';
  update public.campaign_usage set status='used',used_at=now() where order_id=v_order.id and status='reserved';
  insert into public.notifications(user_id,type,title,body,metadata) values(v_order.user_id,'order_delivered','Your digital code is ready','Your verified order has been fulfilled. Open My Orders to view your code.',jsonb_build_object('order_id',v_order.id));
  insert into public.audit_logs(action,entity_type,entity_id,metadata) values('codes_delivered','order',v_order.id,jsonb_build_object('payment_id',p_provider_payment_id,'items',jsonb_array_length(v_plan)));
  -- Referral rewards only follow an eligible, successfully paid first purchase; inserts are idempotent.
  select * into v_reward_setting from public.referral_settings where id=true;
  select exists(select 1 from public.orders where user_id=v_order.user_id and id<>v_order.id and payment_status='paid' and total_amount>=coalesce(v_reward_setting.qualifying_order_minimum,0)) into v_first;
  if not v_first and v_reward_setting.enabled and v_order.total_amount>=coalesce(v_reward_setting.qualifying_order_minimum,0) then
    select * into v_ref from public.referrals where referred_user_id=v_order.user_id and status='registered' for update;
    if found then
      update public.referrals set status='qualified',qualified_at=now() where id=v_ref.id;
      if v_reward_setting.first_purchase_reward>0 then
        insert into public.referral_rewards(referral_id,user_id,reward_type,amount,idempotency_key) values(v_ref.id,v_ref.referrer_id,'first_purchase',v_reward_setting.first_purchase_reward,'referral-first:'||v_ref.id::text) on conflict(idempotency_key) do nothing;
        get diagnostics v_inserted = row_count;
        if v_inserted=1 then update public.profiles set reward_balance=reward_balance+v_reward_setting.first_purchase_reward where id=v_ref.referrer_id; end if;
      end if;
      select count(*) into v_qualified from public.referrals where referrer_id=v_ref.referrer_id and status='qualified';
      if v_reward_setting.milestone_reward>0 and v_qualified>=v_reward_setting.milestone_count and mod(v_qualified,v_reward_setting.milestone_count)=0 then
        insert into public.referral_rewards(referral_id,user_id,reward_type,amount,idempotency_key) values(v_ref.id,v_ref.referrer_id,'milestone',v_reward_setting.milestone_reward,'referral-milestone:'||v_ref.referrer_id::text||':'||v_qualified::text) on conflict(idempotency_key) do nothing;
        get diagnostics v_inserted = row_count;
        if v_inserted=1 then update public.profiles set reward_balance=reward_balance+v_reward_setting.milestone_reward where id=v_ref.referrer_id; end if;
      end if;
    end if;
  end if;
  return jsonb_build_object('status','paid','deliveryStatus','delivered','orderNumber',v_order.order_number);
end $$;
revoke all on function public.fulfill_verified_payment(text,text,bigint,text,jsonb) from public, anon, authenticated;
grant execute on function public.fulfill_verified_payment(text,text,bigint,text,jsonb) to service_role;

create or replace function public.admin_dashboard_metrics()
returns jsonb language plpgsql security definer set search_path = public
as $$
begin
 if not public.has_admin_role() then raise exception 'Administrator access required'; end if;
 return jsonb_build_object(
   'customers',(select count(*) from public.users where status='active'),
   'orders',(select count(*) from public.orders),
   'today_orders',(select count(*) from public.orders where created_at >= date_trunc('day',now() at time zone 'Asia/Kolkata') at time zone 'Asia/Kolkata'),
   'total_sales',(select coalesce(round(sum(total_amount),2),0) from public.orders where payment_status='paid'),
   'pending_payments',(select count(*) from public.orders where payment_status='pending'),
   'available_inventory',(select count(*) from public.redeem_code_inventory where status='available'),
   'sold_inventory',(select count(*) from public.redeem_code_inventory where status='sold'),
   'active_campaigns',(select count(*) from public.campaigns where status='active' and starts_at<=now() and ends_at>now()),
   'referrals',(select count(*) from public.referrals),
   'qualified_referrals',(select count(*) from public.referrals where status='qualified')
 );
end $$;
revoke all on function public.admin_dashboard_metrics() from public, anon;
grant execute on function public.admin_dashboard_metrics() to authenticated, service_role;

create or replace function public.get_referral_leaderboard()
returns table(rank integer, display_name text, successful_referrals bigint)
language sql stable security definer set search_path = public
as $$
  select ranked.position::integer, 'Top referrer #' || ranked.position::text, ranked.successful
  from (
    select row_number() over (order by counts.successful desc, counts.first_qualified asc) as position, counts.successful
    from (
      select referrer_id, count(*) filter (where status='qualified') as successful, min(qualified_at) as first_qualified
      from public.referrals group by referrer_id having count(*) filter (where status='qualified') > 0
    ) counts
    order by counts.successful desc, counts.first_qualified asc limit 10
  ) ranked
  order by ranked.position;
$$;
revoke all on function public.get_referral_leaderboard() from public, anon;
grant execute on function public.get_referral_leaderboard() to authenticated, service_role;

-- Authenticated users can only view their own records. Service role is reserved for Edge Functions.
alter table public.users enable row level security;
alter table public.profiles enable row level security;
alter table public.admin_roles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;
alter table public.redeem_code_inventory enable row level security;
alter table public.coupons enable row level security;
alter table public.coupon_usage enable row level security;
alter table public.campaigns enable row level security;
alter table public.campaign_usage enable row level security;
alter table public.referrals enable row level security;
alter table public.referral_rewards enable row level security;
alter table public.referral_settings enable row level security;
alter table public.transactions enable row level security;
alter table public.support_tickets enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;
alter table public.wishlists enable row level security;
alter table public.reviews enable row level security;

create policy users_self_select on public.users for select to authenticated using(id=auth.uid() or public.has_admin_role());
create policy users_admin_update on public.users for update to authenticated using(public.has_admin_role()) with check(public.has_admin_role());
create policy profiles_self_select on public.profiles for select to authenticated using(id=auth.uid() or public.has_admin_role());
create policy profiles_self_update on public.profiles for update to authenticated using(id=auth.uid()) with check(id=auth.uid());
create policy profiles_admin_select on public.profiles for select to authenticated using(public.has_admin_role());
create policy admins_self_select on public.admin_roles for select to authenticated using(user_id=auth.uid());
create policy categories_public_select on public.categories for select to anon,authenticated using(active=true or public.has_admin_role());
create policy categories_admin_all on public.categories for all to authenticated using(public.has_admin_role()) with check(public.has_admin_role());
create policy products_public_select on public.products for select to anon,authenticated using((active=true and exists(select 1 from public.categories c where c.id=category_id and c.active=true)) or public.has_admin_role());
create policy products_admin_all on public.products for all to authenticated using(public.has_admin_role()) with check(public.has_admin_role());
create policy orders_owner_select on public.orders for select to authenticated using(user_id=auth.uid() or public.has_admin_role());
create policy items_owner_select on public.order_items for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.has_admin_role())));
create policy payments_owner_select on public.payments for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.has_admin_role())));
create policy inventory_admin_only on public.redeem_code_inventory for all to authenticated using(public.has_admin_role()) with check(public.has_admin_role());
create policy coupons_admin_only on public.coupons for all to authenticated using(public.has_admin_role()) with check(public.has_admin_role());
create policy coupon_usage_owner_select on public.coupon_usage for select to authenticated using(user_id=auth.uid() or public.has_admin_role());
create policy campaigns_public_select on public.campaigns for select to anon,authenticated using((status='active' and starts_at<=now() and ends_at>now()) or public.has_admin_role());
create policy campaigns_admin_all on public.campaigns for all to authenticated using(public.has_admin_role()) with check(public.has_admin_role());
create policy referrals_owner_select on public.referrals for select to authenticated using(referrer_id=auth.uid() or referred_user_id=auth.uid() or public.has_admin_role());
create policy rewards_owner_select on public.referral_rewards for select to authenticated using(user_id=auth.uid() or public.has_admin_role());
create policy referral_settings_admin_all on public.referral_settings for all to authenticated using(public.has_admin_role()) with check(public.has_admin_role());
create policy transactions_owner_select on public.transactions for select to authenticated using(user_id=auth.uid() or public.has_admin_role());
create policy tickets_owner_select on public.support_tickets for select to authenticated using(user_id=auth.uid() or public.has_admin_role());
create policy tickets_owner_insert on public.support_tickets for insert to authenticated with check(user_id=auth.uid() and status='open' and admin_note is null);
create policy tickets_admin_update on public.support_tickets for update to authenticated using(public.has_admin_role()) with check(public.has_admin_role());
create policy notifications_owner_select on public.notifications for select to authenticated using(user_id=auth.uid());
create policy notifications_owner_update on public.notifications for update to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy audit_admin_select on public.audit_logs for select to authenticated using(public.has_admin_role());
create policy wishlists_owner_all on public.wishlists for all to authenticated using(user_id=auth.uid()) with check(user_id=auth.uid());
create policy reviews_visible_select on public.reviews for select to anon,authenticated using(visible=true or user_id=auth.uid() or public.has_admin_role());
create policy reviews_verified_insert on public.reviews for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.orders o join public.order_items oi on oi.order_id=o.id where o.user_id=auth.uid() and o.payment_status='paid' and oi.product_id=public.reviews.product_id));
create policy reviews_admin_update on public.reviews for update to authenticated using(public.has_admin_role()) with check(public.has_admin_role());

-- Never allow direct client writes to payment/order/inventory ledgers or admin assignment.
revoke all on public.users, public.orders, public.order_items, public.payments, public.redeem_code_inventory, public.coupons, public.coupon_usage, public.campaign_usage, public.referrals, public.referral_rewards, public.transactions, public.audit_logs, public.referral_settings from anon, authenticated;
grant select on public.users, public.orders, public.order_items, public.payments, public.coupon_usage, public.referrals, public.referral_rewards, public.transactions, public.notifications, public.reviews to authenticated;
grant select on public.categories, public.products, public.campaigns to anon, authenticated;
grant select on public.admin_roles to authenticated;
grant select, insert on public.profiles to authenticated;
grant update(full_name,phone) on public.profiles to authenticated;
grant select, insert, update, delete on public.wishlists to authenticated;
grant select, insert, update on public.support_tickets to authenticated;
grant select, insert, update on public.reviews to authenticated;
grant update(status) on public.users to authenticated;
grant select, insert, update, delete on public.categories, public.products, public.campaigns, public.coupons, public.redeem_code_inventory, public.referral_settings to authenticated;

grant all on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;

-- Automatic housekeeping: scheduled status is time-gated in every read; this function may be run by pg_cron if enabled.
create or replace function public.refresh_campaign_status()
returns void language sql security definer set search_path = public
as $$ update public.campaigns set status=case when status in ('active','scheduled') and starts_at<=now() and ends_at>now() then 'active' when status in ('active','scheduled') and ends_at<=now() then 'ended' else status end where status in ('active','scheduled') $$;
revoke all on function public.refresh_campaign_status() from public, anon, authenticated;
grant execute on function public.refresh_campaign_status() to service_role;

-- Must be assigned out-of-band by a trusted project owner after verifying the operator identity:
-- insert into public.admin_roles(user_id,role) values ('<auth.users UUID>','admin');
