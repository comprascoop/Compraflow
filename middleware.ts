-- 0005 — Helpers de segurança (schema app)
-- TODAS SECURITY DEFINER + STABLE + search_path travado.
-- Por serem DEFINER (rodam como owner), bypassam RLS de user_roles/user_departments
-- => nenhuma policy que chame estas funções entra em recursão. Este é o ponto central da estratégia.

create or replace function app.has_role(p_role_code text)
returns boolean
language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = auth.uid()
      and r.code = p_role_code
      and ur.is_active
  );
$$;

create or replace function app.is_admin()
returns boolean
language sql stable security definer
set search_path = app, public, pg_temp
as $$ select app.has_role('ADMINISTRADOR'); $$;

-- Papel de "área de compras" (comprador ou coordenador) — usado em filas e cotações.
create or replace function app.is_purchasing()
returns boolean
language sql stable security definer
set search_path = app, public, pg_temp
as $$ select app.has_role('COMPRADOR') or app.has_role('COORDENADOR_COMPRAS'); $$;

create or replace function app.is_auditor()
returns boolean
language sql stable security definer
set search_path = app, public, pg_temp
as $$ select app.has_role('AUDITOR'); $$;

-- Setores aos quais o usuário atual pertence.
create or replace function app.user_departments()
returns setof uuid
language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select ud.department_id
  from public.user_departments ud
  where ud.user_id = auth.uid();
$$;

create or replace function app.in_department(p_department_id uuid)
returns boolean
language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select exists (
    select 1 from public.user_departments ud
    where ud.user_id = auth.uid()
      and ud.department_id = p_department_id
  );
$$;

-- É gestor (aprovador de setor) do setor informado?
create or replace function app.manages_department(p_department_id uuid)
returns boolean
language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select exists (
    select 1 from public.user_departments ud
    where ud.user_id = auth.uid()
      and ud.department_id = p_department_id
      and ud.is_manager
  );
$$;

-- Expor apenas aos usuários autenticados. NUNCA a anon.
grant usage on schema app to authenticated;
grant execute on all functions in schema app to authenticated;
revoke all on schema app from anon;
