-- 0023 — Pontes no schema public para as RPCs do schema app.
-- Motivo: o supabase-js exige que o schema seja explicitamente exposto para usar
-- .schema('app').rpc(). Expondo estas pontes em public, o frontend chama sem depender
-- de configuração extra no painel. Elas apenas repassam para app.* (que tem toda a lógica).

create or replace function public.fn_transition_request(
  p_request_id uuid, p_to_status public.request_status,
  p_comment text default null, p_context jsonb default '{}'::jsonb)
returns public.request_status
language sql security definer
set search_path = public, app, pg_temp
as $$ select app.fn_transition_request(p_request_id, p_to_status, p_comment, p_context); $$;

create or replace function public.fn_assign_buyer(p_request_id uuid)
returns void language sql security definer
set search_path = public, app, pg_temp
as $$ select app.fn_assign_buyer(p_request_id); $$;

create or replace function public.fn_set_supplier_status(
  p_supplier_id uuid, p_status public.supplier_status,
  p_reason text default null, p_valid_until date default null)
returns public.supplier_status
language sql security definer
set search_path = public, app, pg_temp
as $$ select app.fn_set_supplier_status(p_supplier_id, p_status, p_reason, p_valid_until); $$;

create or replace function public.fn_generate_orders(p_request_id uuid)
returns int language sql security definer
set search_path = public, app, pg_temp
as $$ select app.fn_generate_orders(p_request_id); $$;

create or replace function public.fn_start_approval(p_recommendation_id uuid)
returns uuid language sql security definer
set search_path = public, app, pg_temp
as $$ select app.fn_start_approval(p_recommendation_id); $$;

create or replace function public.fn_decide_approval(
  p_instance_id uuid, p_decision public.approval_decision, p_comment text default null)
returns text language sql security definer
set search_path = public, app, pg_temp
as $$ select app.fn_decide_approval(p_instance_id, p_decision, p_comment); $$;

create or replace function public.fn_mark_notifications_read(p_ids uuid[] default null)
returns int language sql security definer
set search_path = public, app, pg_temp
as $$ select app.fn_mark_notifications_read(p_ids); $$;

grant execute on function public.fn_transition_request(uuid, public.request_status, text, jsonb) to authenticated;
grant execute on function public.fn_assign_buyer(uuid) to authenticated;
grant execute on function public.fn_set_supplier_status(uuid, public.supplier_status, text, date) to authenticated;
grant execute on function public.fn_generate_orders(uuid) to authenticated;
grant execute on function public.fn_start_approval(uuid) to authenticated;
grant execute on function public.fn_decide_approval(uuid, public.approval_decision, text) to authenticated;
grant execute on function public.fn_mark_notifications_read(uuid[]) to authenticated;

-- Pontes das funções do portal do fornecedor (chamadas pelos Route Handlers via service role)
create or replace function public.fn_register_invitation_token(
  p_invitation_id uuid, p_token_hash text, p_expires_at timestamptz)
returns uuid language sql security definer
set search_path = public, app, pg_temp
as $$ select app.fn_register_invitation_token(p_invitation_id, p_token_hash, p_expires_at); $$;

create or replace function public.fn_validate_invitation_token(p_token_hash text)
returns table (invitation_id uuid, round_id uuid, supplier_id uuid, supplier_name text,
  request_id uuid, request_number text, request_title text,
  invited_email citext, deadline_at timestamptz, mode text, status public.invitation_status)
language sql security definer
set search_path = public, app, pg_temp
as $$ select * from app.fn_validate_invitation_token(p_token_hash); $$;

create or replace function public.fn_register_token_failure(p_token_hash text)
returns void language sql security definer
set search_path = public, app, pg_temp
as $$ select app.fn_register_token_failure(p_token_hash); $$;

create or replace function public.fn_submit_supplier_quote(
  p_invitation_id uuid, p_header jsonb, p_items jsonb)
returns table (protocol text, total_cost numeric)
language sql security definer
set search_path = public, app, pg_temp
as $$ select * from app.fn_submit_supplier_quote(p_invitation_id, p_header, p_items); $$;

create or replace function public.fn_decline_invitation(p_invitation_id uuid, p_reason text)
returns void language sql security definer
set search_path = public, app, pg_temp
as $$ select app.fn_decline_invitation(p_invitation_id, p_reason); $$;

create or replace function public.fn_open_sealed_round(p_round_id uuid, p_reason text)
returns void language sql security definer
set search_path = public, app, pg_temp
as $$ select app.fn_open_sealed_round(p_round_id, p_reason); $$;

grant execute on function public.fn_register_invitation_token(uuid, text, timestamptz) to authenticated, service_role;
grant execute on function public.fn_validate_invitation_token(text) to authenticated, service_role;
grant execute on function public.fn_register_token_failure(text) to authenticated, service_role;
grant execute on function public.fn_submit_supplier_quote(uuid, jsonb, jsonb) to authenticated, service_role;
grant execute on function public.fn_decline_invitation(uuid, text) to authenticated, service_role;
grant execute on function public.fn_open_sealed_round(uuid, text) to authenticated, service_role;
