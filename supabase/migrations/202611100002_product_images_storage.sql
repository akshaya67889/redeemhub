-- Catalog-only public image bucket. Never store redeem codes, payment data, or customer data here.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'product-images',
  'product-images',
  true,
  1048576,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set name = excluded.name,
    public = excluded.public,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Public reads are limited to this dedicated catalog-image bucket.
create policy product_images_public_read
on storage.objects
for select
to anon, authenticated
using (bucket_id = 'product-images');

-- Match product administration exactly: only authenticated users with the admin role
-- (public.has_admin_role() checks admin_roles.role = 'admin') may write objects.
create policy product_images_admin_insert
on storage.objects
for insert
to authenticated
with check (bucket_id = 'product-images' and public.has_admin_role());

create policy product_images_admin_update
on storage.objects
for update
to authenticated
using (bucket_id = 'product-images' and public.has_admin_role())
with check (bucket_id = 'product-images' and public.has_admin_role());

create policy product_images_admin_delete
on storage.objects
for delete
to authenticated
using (bucket_id = 'product-images' and public.has_admin_role());
