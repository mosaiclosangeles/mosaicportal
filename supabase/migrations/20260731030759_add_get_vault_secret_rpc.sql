create or replace function public.get_vault_secret(p_name text)
returns text
language sql
security definer
set search_path = public, vault
as $$
  select decrypted_secret from vault.decrypted_secrets where name = p_name limit 1;
$$;

comment on function public.get_vault_secret(text) is
  'Returns a decrypted Vault secret by name. SECURITY DEFINER; execute intentionally restricted to service_role only (used by the numbers-alert edge function to read slack_bot_token).';

revoke all on function public.get_vault_secret(text) from public, anon, authenticated;
