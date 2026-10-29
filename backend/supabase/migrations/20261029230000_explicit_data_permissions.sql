-- Permisos explícitos: no depender de grants automáticos del proveedor.
grant select, insert, update, delete on public.categories, public.products,
  public.product_images, public.collections, public.product_collections,
  public.brand_logos, public.user_settings, public.api_settings to authenticated;
grant select on public.api_audit_log, public.product_versions to authenticated;
-- api_keys conserva sus permisos por columna y sus guards de revocación.
grant select, insert, update, delete on public.categories, public.products,
  public.product_images, public.collections, public.product_collections,
  public.brand_logos, public.user_settings, public.api_settings, public.api_keys,
  public.api_usage, public.api_audit_log, public.product_versions,
  public.api_auth_failures to service_role;
grant usage, select on all sequences in schema public to service_role;
