-- CompraFlow — todas as migrations em ordem. Gerado em Tue Jul 28 11:43:21 UTC 2026


-- ============ 0001_extensions_schemas.sql ============
-- 0001 — Extensões e schemas
-- Idempotente. Aplicar em ordem numérica.

create extension if not exists pgcrypto;   -- gen_random_uuid(), digest() p/ hash de token
create extension if not exists citext;     -- e-mails case-insensitive

-- schema de funções auxiliares (helpers de RLS/domínio). Nunca exposto via API.
create schema if not exists app;

-- schema analytics (estrela) — populado em etapa posterior via views/materialized views.
create schema if not exists analytics;

comment on schema app is 'Funções de domínio e helpers de segurança (SECURITY DEFINER). Não expor no PostgREST.';
comment on schema analytics is 'Modelo estrela (dims/facts) para dashboards. Somente leitura.';


-- ============ 0002_enums.sql ============
-- 0002 — Tipos enumerados
-- Padrão idempotente: cria o type e ignora se já existe.

do $$ begin
  create type public.priority as enum ('BAIXA','NORMAL','ALTA','CRITICA');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.purchase_type as enum
    ('PRODUTO','SERVICO','CONTRATO','RENOVACAO','COMPRA_EMERGENCIAL');
exception when duplicate_object then null; end $$;

-- Máquina de estados da demanda (seção 5)
do $$ begin
  create type public.request_status as enum (
    'RASCUNHO','ENVIADA','AGUARDANDO_APROVACAO_DO_SETOR','EM_ANALISE_POR_COMPRAS',
    'AGUARDANDO_INFORMACOES','EM_COTACAO','COTACOES_RECEBIDAS','EM_ANALISE_DE_COTACOES',
    'AGUARDANDO_APROVACAO_TECNICA','AGUARDANDO_APROVACAO_FINANCEIRA','APROVADA','REJEITADA',
    'PEDIDO_EMITIDO','EM_ENTREGA','RECEBIDA','ENCERRADA','CANCELADA'
  );
exception when duplicate_object then null; end $$;

-- Estados do pedido (seção 14)
do $$ begin
  create type public.purchase_order_status as enum (
    'RASCUNHO','EMITIDO','ENVIADO','CONFIRMADO_PELO_FORNECEDOR',
    'PARCIALMENTE_RECEBIDO','RECEBIDO','CANCELADO','ENCERRADO'
  );
exception when duplicate_object then null; end $$;

-- Status do fornecedor (seção 16)
do $$ begin
  create type public.supplier_status as enum (
    'EM_CADASTRO','PENDENTE_DE_HOMOLOGACAO','HOMOLOGADO',
    'HOMOLOGADO_COM_RESTRICAO','BLOQUEADO','INATIVO'
  );
exception when duplicate_object then null; end $$;

-- Estados do convite do portal externo (portal seção 18)
do $$ begin
  create type public.invitation_status as enum (
    'RASCUNHO','AGUARDANDO_ENVIO','ENVIADO','ENTREGUE','EMAIL_FALHOU','ACESSADO',
    'PARTICIPACAO_CONFIRMADA','RECUSADO','PROPOSTA_EM_RASCUNHO','RESPONDIDO',
    'EXPIRADO','REVOGADO','CANCELADO'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.approval_decision as enum
    ('APROVADO','REJEITADO','AJUSTE_SOLICITADO','ENCAMINHADO');
exception when duplicate_object then null; end $$;


-- ============ 0003_core_org.sql ============
-- 0003 — Núcleo organizacional
-- companies > business_units > departments > cost_centers
-- Cadastros usam soft delete (deleted_at). Transacionais (etapas futuras) NÃO terão delete físico.

-- Colunas de auditoria padrão são repetidas por tabela (created_at/updated_at/created_by/updated_by).
-- Trigger de updated_at e de audit_log são anexados na migration 0006.

create table if not exists public.companies (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  legal_name   text,
  cnpj         text,
  logo_url     text,
  primary_color text default '#2563EB',
  settings     jsonb not null default '{}'::jsonb,
  is_active    boolean not null default true,
  deleted_at   timestamptz,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  created_by   uuid references auth.users(id),
  updated_by   uuid references auth.users(id),
  constraint companies_cnpj_uk unique (cnpj)
);

create table if not exists public.business_units (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id),
  name        text not null,
  code        text,
  is_active   boolean not null default true,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id),
  updated_by  uuid references auth.users(id)
);
create index if not exists ix_business_units_company on public.business_units(company_id);

create table if not exists public.departments (
  id               uuid primary key default gen_random_uuid(),
  business_unit_id uuid not null references public.business_units(id),
  name             text not null,
  code             text,
  is_active        boolean not null default true,
  deleted_at       timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  created_by       uuid references auth.users(id),
  updated_by       uuid references auth.users(id)
);
create index if not exists ix_departments_bu on public.departments(business_unit_id);

create table if not exists public.cost_centers (
  id             uuid primary key default gen_random_uuid(),
  department_id  uuid not null references public.departments(id),
  name           text not null,
  code           text not null,
  is_active      boolean not null default true,
  deleted_at     timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid references auth.users(id),
  updated_by     uuid references auth.users(id)
);
create index if not exists ix_cost_centers_dept on public.cost_centers(department_id);


-- ============ 0004_rbac.sql ============
-- 0004 — Perfis e RBAC (N:N) + escopo por setor
-- profiles.id = auth.users.id (1:1). RBAC via roles/permissions.
-- Um usuário pode ter vários papéis (user_roles) e pertencer a vários setores (user_departments).

create table if not exists public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  full_name   text not null default '',
  email       citext,
  phone       text,
  avatar_url  text,
  is_active   boolean not null default true,
  settings    jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.roles (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,          -- ADMINISTRADOR, REQUISITANTE, ...
  name        text not null,
  description text,
  is_system   boolean not null default true, -- papéis de sistema não podem ser excluídos
  created_at  timestamptz not null default now()
);

create table if not exists public.permissions (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,          -- ex.: requests.create, suppliers.approve
  description text,
  created_at  timestamptz not null default now()
);

create table if not exists public.role_permissions (
  role_id        uuid not null references public.roles(id) on delete cascade,
  permission_id  uuid not null references public.permissions(id) on delete cascade,
  primary key (role_id, permission_id)
);

create table if not exists public.user_roles (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  role_id     uuid not null references public.roles(id) on delete cascade,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id),
  constraint user_roles_uk unique (user_id, role_id)
);
create index if not exists ix_user_roles_user on public.user_roles(user_id);

create table if not exists public.user_departments (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,
  department_id  uuid not null references public.departments(id) on delete cascade,
  is_manager     boolean not null default false,  -- gestor do setor
  is_primary     boolean not null default false,
  created_at     timestamptz not null default now(),
  constraint user_departments_uk unique (user_id, department_id)
);
create index if not exists ix_user_departments_user on public.user_departments(user_id);
create index if not exists ix_user_departments_dept on public.user_departments(department_id);

-- Cria automaticamente um profile quando um auth.user é criado.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id, full_name, email)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============ 0005_rls_helpers.sql ============
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


-- ============ 0006_audit.sql ============
-- 0006 — Auditoria imutável + triggers de suporte
-- audit_logs recebe INSERT via trigger e nada mais. Sem UPDATE/DELETE (garantido por RLS na 0007).

create table if not exists public.audit_logs (
  id          bigint generated always as identity primary key,
  actor_id    uuid references auth.users(id),
  entity      text not null,          -- nome da tabela
  entity_id   uuid,
  action      text not null,          -- INSERT | UPDATE | DELETE | (ações de domínio)
  old_values  jsonb,
  new_values  jsonb,
  context     jsonb,                  -- ip, user_agent, versão da recomendação, etc.
  created_at  timestamptz not null default now()
);
create index if not exists ix_audit_entity on public.audit_logs(entity, entity_id);
create index if not exists ix_audit_created on public.audit_logs(created_at);

-- Toca updated_at automaticamente.
create or replace function app.tg_touch_updated_at()
returns trigger language plpgsql
set search_path = app, public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Trigger genérico de auditoria. Anexar às tabelas críticas.
create or replace function app.tg_audit()
returns trigger
language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_id  uuid;
begin
  if tg_op = 'DELETE' then
    v_old := to_jsonb(old); v_new := null; v_id := (old).id;
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old); v_new := to_jsonb(new); v_id := (new).id;
  else
    v_old := null; v_new := to_jsonb(new); v_id := (new).id;
  end if;

  insert into public.audit_logs(actor_id, entity, entity_id, action, old_values, new_values)
  values (auth.uid(), tg_table_name, v_id, tg_op, v_old, v_new);

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

-- Anexa updated_at + auditoria nas tabelas de cadastro já existentes.
do $$
declare t text;
begin
  foreach t in array array[
    'companies','business_units','departments','cost_centers','profiles',
    'roles','user_roles','user_departments'
  ]
  loop
    execute format('drop trigger if exists tg_touch on public.%I', t);
    -- profiles/roles não têm updated_at nas de RBAC simples; só anexa onde a coluna existe.
    if exists (select 1 from information_schema.columns
               where table_schema='public' and table_name=t and column_name='updated_at') then
      execute format(
        'create trigger tg_touch before update on public.%I
         for each row execute function app.tg_touch_updated_at()', t);
    end if;

    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format(
      'create trigger tg_audit after insert or update or delete on public.%I
       for each row execute function app.tg_audit()', t);
  end loop;
end $$;


-- ============ 0007_rls_core.sql ============
-- 0007 — RLS do núcleo (org + RBAC + auditoria)
-- Princípio: deny by default. Habilita RLS e cria policies explícitas.
-- Sem policy = nenhum acesso (exceto owner/service_role, que ignoram RLS).

alter table public.companies       enable row level security;
alter table public.business_units  enable row level security;
alter table public.departments     enable row level security;
alter table public.cost_centers    enable row level security;
alter table public.profiles        enable row level security;
alter table public.roles           enable row level security;
alter table public.permissions     enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles      enable row level security;
alter table public.user_departments enable row level security;
alter table public.audit_logs      enable row level security;

-- ---------- Cadastros organizacionais ----------
-- Leitura: qualquer autenticado (estrutura da empresa não é sigilosa e é referência de formulários).
-- Escrita: só ADMIN.
do $$
declare t text;
begin
  foreach t in array array['companies','business_units','departments','cost_centers'] loop
    execute format('drop policy if exists sel_%1$s on public.%1$s', t);
    execute format(
      'create policy sel_%1$s on public.%1$s for select to authenticated
       using (deleted_at is null or app.is_admin())', t);

    execute format('drop policy if exists ins_%1$s on public.%1$s', t);
    execute format(
      'create policy ins_%1$s on public.%1$s for insert to authenticated
       with check (app.is_admin())', t);

    execute format('drop policy if exists upd_%1$s on public.%1$s', t);
    execute format(
      'create policy upd_%1$s on public.%1$s for update to authenticated
       using (app.is_admin()) with check (app.is_admin())', t);
    -- Sem policy de DELETE => exclusão física bloqueada. Usar soft delete (deleted_at).
  end loop;
end $$;

-- ---------- profiles ----------
drop policy if exists sel_profiles on public.profiles;
create policy sel_profiles on public.profiles for select to authenticated
  using (id = auth.uid() or app.is_admin() or app.is_auditor());

drop policy if exists upd_profiles_self on public.profiles;
create policy upd_profiles_self on public.profiles for update to authenticated
  using (id = auth.uid() or app.is_admin())
  with check (id = auth.uid() or app.is_admin());

-- ---------- roles / permissions / role_permissions ----------
-- Leitura para autenticados (a UI precisa exibir nomes de papéis); escrita só ADMIN.
do $$
declare t text;
begin
  foreach t in array array['roles','permissions','role_permissions'] loop
    execute format('drop policy if exists sel_%1$s on public.%1$s', t);
    execute format('create policy sel_%1$s on public.%1$s for select to authenticated using (true)', t);
    execute format('drop policy if exists wr_%1$s on public.%1$s', t);
    execute format('create policy wr_%1$s on public.%1$s for all to authenticated
                    using (app.is_admin()) with check (app.is_admin())', t);
  end loop;
end $$;

-- ---------- user_roles ----------
-- Usuário vê os próprios papéis; ADMIN vê/gerencia todos.
drop policy if exists sel_user_roles on public.user_roles;
create policy sel_user_roles on public.user_roles for select to authenticated
  using (user_id = auth.uid() or app.is_admin() or app.is_auditor());

drop policy if exists wr_user_roles on public.user_roles;
create policy wr_user_roles on public.user_roles for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- ---------- user_departments ----------
drop policy if exists sel_user_departments on public.user_departments;
create policy sel_user_departments on public.user_departments for select to authenticated
  using (user_id = auth.uid() or app.is_admin() or app.is_auditor());

drop policy if exists wr_user_departments on public.user_departments;
create policy wr_user_departments on public.user_departments for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- ---------- audit_logs ----------
-- Leitura: ADMIN e AUDITOR. Escrita: NENHUMA via API (só o trigger DEFINER insere).
-- Sem policy de insert/update/delete => imutável do ponto de vista do usuário autenticado.
drop policy if exists sel_audit on public.audit_logs;
create policy sel_audit on public.audit_logs for select to authenticated
  using (app.is_admin() or app.is_auditor());


-- ============ 0008_catalog.sql ============
-- 0008 — Cadastros de apoio da demanda (categorias, unidades de medida)
-- Leitura para autenticados; escrita só ADMIN; soft delete; auditados.

create table if not exists public.categories (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  code        text,
  parent_id   uuid references public.categories(id),
  is_active   boolean not null default true,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id),
  updated_by  uuid references auth.users(id)
);
create index if not exists ix_categories_parent on public.categories(parent_id);

create table if not exists public.units_of_measure (
  id          uuid primary key default gen_random_uuid(),
  code        text not null unique,      -- UN, CX, KG, M, L, H (hora), SV (serviço)
  name        text not null,
  is_active   boolean not null default true,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.categories       enable row level security;
alter table public.units_of_measure enable row level security;

do $$
declare t text;
begin
  foreach t in array array['categories','units_of_measure'] loop
    execute format('drop policy if exists sel_%1$s on public.%1$s', t);
    execute format('create policy sel_%1$s on public.%1$s for select to authenticated
                    using (coalesce(deleted_at is null, true) or app.is_admin())', t);
    execute format('drop policy if exists wr_%1$s on public.%1$s', t);
    execute format('create policy wr_%1$s on public.%1$s for all to authenticated
                    using (app.is_admin()) with check (app.is_admin())', t);

    execute format('drop trigger if exists tg_touch on public.%I', t);
    execute format('create trigger tg_touch before update on public.%I
                    for each row execute function app.tg_touch_updated_at()', t);
    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format('create trigger tg_audit after insert or update or delete on public.%I
                    for each row execute function app.tg_audit()', t);
  end loop;
end $$;


-- ============ 0009_requests.sql ============
-- 0009 — Demandas: numeração, tabelas, itens (totais automáticos), histórico

-- ---------- Numeração sequencial por escopo/ano (base do menu admin "Numerações") ----------
create table if not exists public.number_sequences (
  scope       text not null,
  year        int  not null,
  last_value  bigint not null default 0,
  primary key (scope, year)
);

create or replace function app.fn_next_number(p_scope text, p_prefix text)
returns text
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_year int := extract(year from now())::int;
  v_val  bigint;
begin
  insert into public.number_sequences(scope, year, last_value)
  values (p_scope, v_year, 1)
  on conflict (scope, year)
    do update set last_value = number_sequences.last_value + 1
  returning last_value into v_val;

  return p_prefix || '-' || v_year || '-' || lpad(v_val::text, 6, '0');
end;
$$;

-- ---------- Demanda ----------
create table if not exists public.purchase_requests (
  id                 uuid primary key default gen_random_uuid(),
  number             text unique,                 -- preenchido por trigger
  company_id         uuid references public.companies(id),
  business_unit_id   uuid references public.business_units(id),
  department_id      uuid not null references public.departments(id),
  cost_center_id     uuid references public.cost_centers(id),
  category_id        uuid references public.categories(id),
  title              text not null,
  purchase_type      public.purchase_type not null default 'PRODUTO',
  priority           public.priority not null default 'NORMAL',
  status             public.request_status not null default 'RASCUNHO',
  needed_at          date,
  delivery_location  text,
  project_ref        text,
  justification      text,
  expected_benefit   text,
  consequence        text,
  is_emergency       boolean not null default false,
  emergency_reason   text,
  estimated_total    numeric(18,2) not null default 0,   -- mantido por trigger a partir dos itens
  assigned_buyer_id  uuid references auth.users(id),      -- comprador que assumiu
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  created_by         uuid not null default auth.uid() references auth.users(id),
  updated_by         uuid references auth.users(id)
);
create index if not exists ix_requests_dept   on public.purchase_requests(department_id);
create index if not exists ix_requests_status on public.purchase_requests(status);
create index if not exists ix_requests_buyer  on public.purchase_requests(assigned_buyer_id);
create index if not exists ix_requests_creator on public.purchase_requests(created_by);

-- ---------- Itens ----------
create table if not exists public.purchase_request_items (
  id                 uuid primary key default gen_random_uuid(),
  request_id         uuid not null references public.purchase_requests(id) on delete cascade,
  line_no            int  not null default 1,
  description        text not null,
  specification      text,
  unit_id            uuid references public.units_of_measure(id),
  quantity           numeric(18,4) not null default 1 check (quantity > 0),
  reference_brand    text,
  allow_equivalent   boolean not null default true,
  unit_price         numeric(18,2) not null default 0 check (unit_price >= 0),
  total_estimated    numeric(18,2) generated always as (round(quantity * unit_price, 2)) stored,
  category_id        uuid references public.categories(id),
  notes              text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);
create index if not exists ix_request_items_request on public.purchase_request_items(request_id);

-- ON DELETE CASCADE acima só atua enquanto a demanda é RASCUNHO (item pertence a rascunho).
-- Demanda enviada não é excluível (sem policy de DELETE + regra de negócio no RPC).

-- ---------- Histórico de status ----------
create table if not exists public.status_history (
  id           bigint generated always as identity primary key,
  request_id   uuid not null references public.purchase_requests(id),
  from_status  public.request_status,
  to_status    public.request_status not null,
  comment      text,
  context      jsonb,
  changed_by   uuid references auth.users(id),
  created_at   timestamptz not null default now()
);
create index if not exists ix_status_history_request on public.status_history(request_id);

-- ---------- Trigger: numeração automática ----------
create or replace function app.tg_request_number()
returns trigger language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
begin
  if new.number is null then
    new.number := app.fn_next_number('purchase_request', 'DEM');
  end if;
  return new;
end;
$$;
drop trigger if exists tg_request_number on public.purchase_requests;
create trigger tg_request_number before insert on public.purchase_requests
  for each row execute function app.tg_request_number();

-- ---------- Trigger: recalcular total da demanda a partir dos itens ----------
create or replace function app.tg_recalc_request_total()
returns trigger language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare v_req uuid;
begin
  v_req := coalesce(new.request_id, old.request_id);
  update public.purchase_requests r
     set estimated_total = coalesce((
           select sum(i.total_estimated) from public.purchase_request_items i
           where i.request_id = v_req), 0)
   where r.id = v_req;
  return null;
end;
$$;
drop trigger if exists tg_recalc_total on public.purchase_request_items;
create trigger tg_recalc_total after insert or update or delete on public.purchase_request_items
  for each row execute function app.tg_recalc_request_total();

-- ---------- updated_at + auditoria ----------
drop trigger if exists tg_touch on public.purchase_requests;
create trigger tg_touch before update on public.purchase_requests
  for each row execute function app.tg_touch_updated_at();
drop trigger if exists tg_touch on public.purchase_request_items;
create trigger tg_touch before update on public.purchase_request_items
  for each row execute function app.tg_touch_updated_at();

drop trigger if exists tg_audit on public.purchase_requests;
create trigger tg_audit after insert or update or delete on public.purchase_requests
  for each row execute function app.tg_audit();
drop trigger if exists tg_audit on public.purchase_request_items;
create trigger tg_audit after insert or update or delete on public.purchase_request_items
  for each row execute function app.tg_audit();


-- ============ 0010_requests_state_machine.sql ============
-- 0010 — Máquina de estados da demanda (tabela de transições + RPC)
-- O front NUNCA faz "update status". Só chama app.fn_transition_request().

-- ---------- Transições permitidas ----------
-- required_role: papel exigido (NULL = não exige papel específico)
-- allow_owner: o criador da demanda pode disparar
-- allow_dept_manager: o gestor (is_manager) do setor da demanda pode disparar
-- requires_items: exige título/centro de custo e ao menos 1 item
-- Coordenador de compras recebe TAMBÉM o papel COMPRADOR no cadastro do usuário
-- (spec: "coordenador possui as permissões do comprador"), por isso COMPRADOR cobre ambos.
create table if not exists public.request_status_transitions (
  from_status        public.request_status not null,
  to_status          public.request_status not null,
  required_role      text,
  allow_owner        boolean not null default false,
  allow_dept_manager boolean not null default false,
  requires_items     boolean not null default false,
  requires_comment   boolean not null default false,
  description        text,
  primary key (from_status, to_status)
);

insert into public.request_status_transitions
  (from_status, to_status, required_role, allow_owner, allow_dept_manager, requires_items, requires_comment, description)
values
  ('RASCUNHO','ENVIADA',                       null, true,  false, true,  false, 'Requisitante envia a demanda'),
  ('RASCUNHO','CANCELADA',                     null, true,  false, false, true,  'Cancelar rascunho'),
  ('ENVIADA','AGUARDANDO_APROVACAO_DO_SETOR',  null, false, true,  false, false, 'Rota com aprovação de setor habilitada'),
  ('ENVIADA','EM_ANALISE_POR_COMPRAS',        'COMPRADOR', false, false, false, false, 'Compras assume (sem etapa de setor)'),
  ('ENVIADA','CANCELADA',                      null, true,  false, false, true,  'Cancelar antes da cotação'),
  ('AGUARDANDO_APROVACAO_DO_SETOR','EM_ANALISE_POR_COMPRAS', null, false, true, false, false, 'Gestor aprova → compras'),
  ('AGUARDANDO_APROVACAO_DO_SETOR','RASCUNHO', null, false, true,  false, true,  'Gestor devolve p/ ajuste'),
  ('AGUARDANDO_APROVACAO_DO_SETOR','REJEITADA',null, false, true,  false, true,  'Gestor rejeita'),
  ('EM_ANALISE_POR_COMPRAS','AGUARDANDO_INFORMACOES','COMPRADOR', false, false, false, true, 'Comprador pede complemento'),
  ('EM_ANALISE_POR_COMPRAS','EM_COTACAO',      'COMPRADOR', false, false, false, false, 'Abrir cotação'),
  ('AGUARDANDO_INFORMACOES','EM_ANALISE_POR_COMPRAS', null, true, false, false, false, 'Requisitante responde'),
  ('EM_COTACAO','COTACOES_RECEBIDAS',          'COMPRADOR', false, false, false, false, 'Encerrar recebimento de propostas'),
  ('COTACOES_RECEBIDAS','EM_ANALISE_DE_COTACOES','COMPRADOR', false, false, false, false, 'Analisar cotações'),
  ('EM_ANALISE_DE_COTACOES','AGUARDANDO_APROVACAO_FINANCEIRA','COMPRADOR', false, false, false, false, 'Enviar p/ aprovação'),
  ('AGUARDANDO_APROVACAO_FINANCEIRA','APROVADA','APROVADOR_FINANCEIRO', false, false, false, false, 'Diretor aprova'),
  ('AGUARDANDO_APROVACAO_FINANCEIRA','REJEITADA','APROVADOR_FINANCEIRO', false, false, false, true,  'Diretor rejeita'),
  ('AGUARDANDO_APROVACAO_FINANCEIRA','EM_ANALISE_DE_COTACOES','APROVADOR_FINANCEIRO', false, false, false, true, 'Diretor solicita ajuste'),
  ('APROVADA','PEDIDO_EMITIDO',                'COMPRADOR', false, false, false, false, 'Gerar pedido'),
  ('PEDIDO_EMITIDO','EM_ENTREGA',              'COMPRADOR', false, false, false, false, 'Pedido enviado ao fornecedor'),
  ('EM_ENTREGA','RECEBIDA',                    'COMPRADOR', true,  false, false, false, 'Confirmar recebimento'),
  ('RECEBIDA','ENCERRADA',                     'COMPRADOR', false, false, false, false, 'Encerrar demanda')
on conflict (from_status, to_status) do nothing;

-- ---------- Helpers de acesso à demanda (usados pela RLS de itens/histórico) ----------
create or replace function app.can_read_request(p_request_id uuid)
returns boolean
language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select exists (
    select 1 from public.purchase_requests r
    where r.id = p_request_id
      and (
        r.created_by = auth.uid()
        or r.assigned_buyer_id = auth.uid()
        or app.in_department(r.department_id)
        or app.is_purchasing()
        or app.is_admin()
        or app.is_auditor()
      )
  );
$$;

-- ---------- RPC de transição ----------
create or replace function app.fn_transition_request(
  p_request_id uuid,
  p_to_status  public.request_status,
  p_comment    text default null,
  p_context    jsonb default '{}'::jsonb
)
returns public.request_status
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_req  public.purchase_requests%rowtype;
  v_tr   public.request_status_transitions%rowtype;
  v_ok   boolean := false;
  v_items int;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado' using errcode = '28000';
  end if;

  select * into v_req from public.purchase_requests where id = p_request_id for update;
  if not found then
    raise exception 'Demanda % não encontrada', p_request_id using errcode = 'P0002';
  end if;

  select * into v_tr from public.request_status_transitions
   where from_status = v_req.status and to_status = p_to_status;
  if not found then
    raise exception 'Transição inválida: % → %', v_req.status, p_to_status using errcode = 'P0001';
  end if;

  -- Autorização
  v_ok := app.is_admin();
  if not v_ok and v_tr.required_role is not null then
    v_ok := app.has_role(v_tr.required_role);
  end if;
  if not v_ok and v_tr.allow_owner then
    v_ok := (v_req.created_by = auth.uid());
  end if;
  if not v_ok and v_tr.allow_dept_manager then
    v_ok := app.manages_department(v_req.department_id);
  end if;
  if not v_ok then
    raise exception 'Sem permissão para % → %', v_req.status, p_to_status using errcode = '42501';
  end if;

  -- Validações de conteúdo
  if v_tr.requires_comment and (p_comment is null or length(trim(p_comment)) = 0) then
    raise exception 'Justificativa obrigatória para esta transição' using errcode = 'P0001';
  end if;

  if v_tr.requires_items then
    if v_req.title is null or v_req.cost_center_id is null then
      raise exception 'Título e centro de custo são obrigatórios para envio' using errcode = 'P0001';
    end if;
    select count(*) into v_items from public.purchase_request_items where request_id = p_request_id;
    if v_items = 0 then
      raise exception 'A demanda precisa de ao menos um item' using errcode = 'P0001';
    end if;
    if v_req.is_emergency and (v_req.emergency_reason is null or length(trim(v_req.emergency_reason))=0) then
      raise exception 'Compra emergencial exige justificativa da emergência' using errcode = 'P0001';
    end if;
  end if;

  -- Aplica
  update public.purchase_requests
     set status = p_to_status, updated_by = auth.uid()
   where id = p_request_id;

  insert into public.status_history(request_id, from_status, to_status, comment, context, changed_by)
  values (p_request_id, v_req.status, p_to_status, p_comment, p_context, auth.uid());

  return p_to_status;
end;
$$;

-- RPC para um comprador assumir a demanda (define assigned_buyer_id)
create or replace function app.fn_assign_buyer(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
begin
  if not (app.is_purchasing() or app.is_admin()) then
    raise exception 'Apenas compras pode assumir demandas' using errcode = '42501';
  end if;
  update public.purchase_requests
     set assigned_buyer_id = auth.uid(), updated_by = auth.uid()
   where id = p_request_id;
end;
$$;

grant execute on function app.fn_transition_request(uuid, public.request_status, text, jsonb) to authenticated;
grant execute on function app.fn_assign_buyer(uuid) to authenticated;
grant execute on function app.can_read_request(uuid) to authenticated;


-- ============ 0011_requests_rls.sql ============
-- 0011 — RLS das demandas, itens, histórico e transições

alter table public.purchase_requests           enable row level security;
alter table public.purchase_request_items       enable row level security;
alter table public.status_history               enable row level security;
alter table public.request_status_transitions   enable row level security;
alter table public.number_sequences             enable row level security;

-- ---------- purchase_requests ----------
-- Leitura: dono, comprador atribuído, membros do setor, área de compras, admin, auditor.
drop policy if exists sel_requests on public.purchase_requests;
create policy sel_requests on public.purchase_requests for select to authenticated
  using (
    created_by = auth.uid()
    or assigned_buyer_id = auth.uid()
    or app.in_department(department_id)
    or app.is_purchasing()
    or app.is_admin()
    or app.is_auditor()
  );

-- Criação: requisitante (ou admin), sempre em nome próprio e num setor a que pertence.
drop policy if exists ins_requests on public.purchase_requests;
create policy ins_requests on public.purchase_requests for insert to authenticated
  with check (
    created_by = auth.uid()
    and (app.is_admin() or (app.has_role('REQUISITANTE') and app.in_department(department_id)))
  );

-- Edição de campos: só o dono enquanto RASCUNHO, ou compras/admin.
-- (Mudança de STATUS não passa por aqui — é via RPC definer.)
drop policy if exists upd_requests on public.purchase_requests;
create policy upd_requests on public.purchase_requests for update to authenticated
  using (
    (created_by = auth.uid() and status = 'RASCUNHO')
    or app.is_purchasing()
    or app.is_admin()
  )
  with check (
    (created_by = auth.uid() and status = 'RASCUNHO')
    or app.is_purchasing()
    or app.is_admin()
  );
-- Sem policy de DELETE => demanda nunca é excluída fisicamente.

-- ---------- purchase_request_items ----------
drop policy if exists sel_request_items on public.purchase_request_items;
create policy sel_request_items on public.purchase_request_items for select to authenticated
  using (app.can_read_request(request_id));

-- Inserir/editar/remover itens só enquanto a demanda-mãe é RASCUNHO e do próprio dono (ou compras/admin).
drop policy if exists wr_request_items on public.purchase_request_items;
create policy wr_request_items on public.purchase_request_items for all to authenticated
  using (
    exists (select 1 from public.purchase_requests r
            where r.id = request_id
              and ((r.created_by = auth.uid() and r.status = 'RASCUNHO')
                   or app.is_purchasing() or app.is_admin()))
  )
  with check (
    exists (select 1 from public.purchase_requests r
            where r.id = request_id
              and ((r.created_by = auth.uid() and r.status = 'RASCUNHO')
                   or app.is_purchasing() or app.is_admin()))
  );

-- ---------- status_history ----------
-- Leitura conforme acesso à demanda; escrita SÓ via RPC definer (sem policy de insert).
drop policy if exists sel_status_history on public.status_history;
create policy sel_status_history on public.status_history for select to authenticated
  using (app.can_read_request(request_id));

-- ---------- request_status_transitions ----------
-- Catálogo somente leitura (UI precisa saber ações disponíveis); escrita só ADMIN.
drop policy if exists sel_transitions on public.request_status_transitions;
create policy sel_transitions on public.request_status_transitions for select to authenticated
  using (true);
drop policy if exists wr_transitions on public.request_status_transitions;
create policy wr_transitions on public.request_status_transitions for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- ---------- number_sequences ----------
-- Sem policies de leitura/escrita p/ usuários. Só funções definer tocam nela.


-- ============ 0012_suppliers.sql ============
-- 0012 — Fornecedores: validação de CNPJ + cadastro principal

-- ---------- Validador de CNPJ (dígitos verificadores reais) ----------
create or replace function app.is_valid_cnpj(p text)
returns boolean
language plpgsql immutable
set search_path = pg_temp
as $$
declare
  d text;
  nums int[];
  w1 int[] := array[5,4,3,2,9,8,7,6,5,4,3,2];
  w2 int[] := array[6,5,4,3,2,9,8,7,6,5,4,3,2];
  s int; r int; dv1 int; dv2 int; i int;
begin
  d := regexp_replace(coalesce(p,''), '\D', '', 'g');
  if length(d) <> 14 then return false; end if;
  if d ~ '^(.)\1{13}$' then return false; end if;             -- rejeita todos iguais
  nums := array(select substr(d, g, 1)::int from generate_series(1,14) g);
  s := 0; for i in 1..12 loop s := s + nums[i]*w1[i]; end loop;
  r := s % 11; dv1 := case when r < 2 then 0 else 11 - r end;
  if dv1 <> nums[13] then return false; end if;
  s := 0; for i in 1..13 loop s := s + nums[i]*w2[i]; end loop;
  r := s % 11; dv2 := case when r < 2 then 0 else 11 - r end;
  return dv2 = nums[14];
end;
$$;

-- ---------- Fornecedor ----------
create table if not exists public.suppliers (
  id                       uuid primary key default gen_random_uuid(),
  legal_name               text not null,                 -- razão social
  trade_name               text,                          -- nome fantasia
  cnpj                     text not null,                 -- armazenado só com dígitos
  state_registration       text,                          -- inscrição estadual
  address                  text,
  city                     text,
  state                    char(2),                       -- UF
  zip_code                 text,                           -- CEP
  website                  text,
  default_payment_terms    text,
  average_lead_time_days   int check (average_lead_time_days >= 0),
  status                   public.supplier_status not null default 'EM_CADASTRO',
  homologation_valid_until date,
  rating                   numeric(3,2) check (rating >= 0 and rating <= 5),
  notes                    text,
  tags                     text[] not null default '{}',
  deleted_at               timestamptz,
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now(),
  created_by               uuid references auth.users(id),
  updated_by               uuid references auth.users(id),
  constraint suppliers_cnpj_valido check (app.is_valid_cnpj(cnpj))
);

-- Unicidade de CNPJ apenas entre fornecedores ativos (permite recadastro após exclusão lógica).
create unique index if not exists uix_suppliers_cnpj_ativo
  on public.suppliers(cnpj) where deleted_at is null;
create index if not exists ix_suppliers_status on public.suppliers(status);
create index if not exists ix_suppliers_trade  on public.suppliers(trade_name);

-- Normaliza CNPJ (só dígitos) antes de gravar.
create or replace function app.tg_normalize_supplier()
returns trigger language plpgsql
set search_path = app, public, pg_temp
as $$
begin
  new.cnpj := regexp_replace(coalesce(new.cnpj,''), '\D', '', 'g');
  if new.zip_code is not null then
    new.zip_code := regexp_replace(new.zip_code, '\D', '', 'g');
  end if;
  if new.state is not null then new.state := upper(new.state); end if;
  return new;
end;
$$;
drop trigger if exists tg_normalize on public.suppliers;
create trigger tg_normalize before insert or update on public.suppliers
  for each row execute function app.tg_normalize_supplier();

drop trigger if exists tg_touch on public.suppliers;
create trigger tg_touch before update on public.suppliers
  for each row execute function app.tg_touch_updated_at();
drop trigger if exists tg_audit on public.suppliers;
create trigger tg_audit after insert or update or delete on public.suppliers
  for each row execute function app.tg_audit();

-- RLS: leitura para autenticados (referência de cotação); escrita só compras/admin; sem delete físico.
alter table public.suppliers enable row level security;

drop policy if exists sel_suppliers on public.suppliers;
create policy sel_suppliers on public.suppliers for select to authenticated
  using (deleted_at is null or app.is_admin() or app.is_auditor());

drop policy if exists ins_suppliers on public.suppliers;
create policy ins_suppliers on public.suppliers for insert to authenticated
  with check (app.is_purchasing() or app.is_admin());

drop policy if exists upd_suppliers on public.suppliers;
create policy upd_suppliers on public.suppliers for update to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());


-- ============ 0013_supplier_related.sql ============
-- 0013 — Contatos, categorias, documentos, avaliações e dados bancários (isolados)

-- ---------- Contatos ----------
create table if not exists public.supplier_contacts (
  id          uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  name        text not null,
  title       text,
  email       citext,
  phone       text,
  is_primary  boolean not null default false,
  notes       text,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists ix_supplier_contacts_supplier on public.supplier_contacts(supplier_id);

-- ---------- Categorias atendidas ----------
create table if not exists public.supplier_categories (
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  category_id uuid not null references public.categories(id),
  primary key (supplier_id, category_id)
);

-- ---------- Documentos / certidões (arquivo físico no bucket supplier-documents) ----------
create table if not exists public.supplier_documents (
  id            uuid primary key default gen_random_uuid(),
  supplier_id   uuid not null references public.suppliers(id) on delete cascade,
  doc_type      text not null,                 -- CERTIDAO, CONTRATO_SOCIAL, ATESTADO, OUTRO
  title         text not null,
  storage_path  text not null,                 -- nome físico (UUID) no bucket
  original_name text,
  mime_type     text,
  size_bytes    bigint,
  valid_until   date,                          -- vencimento (certidões)
  deleted_at    timestamptz,                   -- exclusão lógica
  created_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id)
);
create index if not exists ix_supplier_docs_supplier on public.supplier_documents(supplier_id);
create index if not exists ix_supplier_docs_validade on public.supplier_documents(valid_until);

-- ---------- Avaliações (alimentam rating médio) ----------
create table if not exists public.supplier_evaluations (
  id           uuid primary key default gen_random_uuid(),
  supplier_id  uuid not null references public.suppliers(id) on delete cascade,
  score        numeric(3,2) not null check (score >= 0 and score <= 5),
  criteria     jsonb not null default '{}'::jsonb,   -- notas por critério (prazo, qualidade, ...)
  comment      text,
  period       text,
  created_at   timestamptz not null default now(),
  created_by   uuid references auth.users(id)
);
create index if not exists ix_supplier_evals_supplier on public.supplier_evaluations(supplier_id);

-- ---------- Dados bancários (SENSÍVEL — tabela isolada, RLS restrita) ----------
create table if not exists public.supplier_bank_accounts (
  id            uuid primary key default gen_random_uuid(),
  supplier_id   uuid not null references public.suppliers(id) on delete cascade,
  bank_code     text,
  bank_name     text,
  agency        text,
  account       text,
  account_type  text,
  pix_key       text,
  holder_name   text,
  holder_document text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id)
);
create index if not exists ix_supplier_bank_supplier on public.supplier_bank_accounts(supplier_id);

-- Recalcula rating médio do fornecedor a cada avaliação.
create or replace function app.tg_recalc_supplier_rating()
returns trigger language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare v_sup uuid;
begin
  v_sup := coalesce(new.supplier_id, old.supplier_id);
  update public.suppliers s
     set rating = (select round(avg(e.score),2) from public.supplier_evaluations e
                   where e.supplier_id = v_sup)
   where s.id = v_sup;
  return null;
end;
$$;
drop trigger if exists tg_recalc_rating on public.supplier_evaluations;
create trigger tg_recalc_rating after insert or update or delete on public.supplier_evaluations
  for each row execute function app.tg_recalc_supplier_rating();

-- updated_at + auditoria nas tabelas relacionadas com essa coluna
do $$
declare t text;
begin
  foreach t in array array['supplier_contacts','supplier_bank_accounts'] loop
    execute format('drop trigger if exists tg_touch on public.%I', t);
    execute format('create trigger tg_touch before update on public.%I
                    for each row execute function app.tg_touch_updated_at()', t);
  end loop;
  foreach t in array array['supplier_contacts','supplier_categories','supplier_documents',
                           'supplier_evaluations','supplier_bank_accounts'] loop
    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format('create trigger tg_audit after insert or update or delete on public.%I
                    for each row execute function app.tg_audit()', t);
  end loop;
end $$;


-- ============ 0014_suppliers_rls_rpc.sql ============
-- 0014 — RLS das tabelas de fornecedor + RPC de homologação

alter table public.supplier_contacts       enable row level security;
alter table public.supplier_categories      enable row level security;
alter table public.supplier_documents       enable row level security;
alter table public.supplier_evaluations     enable row level security;
alter table public.supplier_bank_accounts   enable row level security;

-- Contatos e categorias: leitura para autenticados; escrita compras/admin.
do $$
declare t text;
begin
  foreach t in array array['supplier_contacts','supplier_categories','supplier_documents'] loop
    execute format('drop policy if exists sel_%1$s on public.%1$s', t);
    execute format('drop policy if exists wr_%1$s on public.%1$s', t);
  end loop;
end $$;

create policy sel_supplier_contacts on public.supplier_contacts for select to authenticated
  using (deleted_at is null or app.is_admin());
create policy wr_supplier_contacts on public.supplier_contacts for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

create policy sel_supplier_categories on public.supplier_categories for select to authenticated
  using (true);
create policy wr_supplier_categories on public.supplier_categories for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

create policy sel_supplier_documents on public.supplier_documents for select to authenticated
  using (deleted_at is null or app.is_admin() or app.is_auditor());
create policy wr_supplier_documents on public.supplier_documents for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

-- Avaliações: internas — só compras/admin/auditor leem; compras/admin escrevem.
drop policy if exists sel_supplier_evaluations on public.supplier_evaluations;
create policy sel_supplier_evaluations on public.supplier_evaluations for select to authenticated
  using (app.is_purchasing() or app.is_admin() or app.is_auditor());
drop policy if exists wr_supplier_evaluations on public.supplier_evaluations;
create policy wr_supplier_evaluations on public.supplier_evaluations for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

-- Dados bancários: SENSÍVEL — só ADMIN e COORDENADOR de compras.
drop policy if exists sel_supplier_bank on public.supplier_bank_accounts;
create policy sel_supplier_bank on public.supplier_bank_accounts for select to authenticated
  using (app.is_admin() or app.has_role('COORDENADOR_COMPRAS'));
drop policy if exists wr_supplier_bank on public.supplier_bank_accounts;
create policy wr_supplier_bank on public.supplier_bank_accounts for all to authenticated
  using (app.is_admin() or app.has_role('COORDENADOR_COMPRAS'))
  with check (app.is_admin() or app.has_role('COORDENADOR_COMPRAS'));

-- ---------- RPC de homologação / mudança de status do fornecedor ----------
-- Só ADMIN ou COORDENADOR_COMPRAS. Registra motivo em audit_logs com contexto.
create or replace function app.fn_set_supplier_status(
  p_supplier_id uuid,
  p_status      public.supplier_status,
  p_reason      text default null,
  p_valid_until date default null
)
returns public.supplier_status
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare v_old public.supplier_status;
begin
  if not (app.is_admin() or app.has_role('COORDENADOR_COMPRAS')) then
    raise exception 'Sem permissão para homologar fornecedores' using errcode = '42501';
  end if;

  if p_status in ('HOMOLOGADO','HOMOLOGADO_COM_RESTRICAO','BLOQUEADO')
     and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'Justificativa obrigatória para % ', p_status using errcode = 'P0001';
  end if;

  select status into v_old from public.suppliers where id = p_supplier_id for update;
  if not found then
    raise exception 'Fornecedor não encontrado' using errcode = 'P0002';
  end if;

  update public.suppliers
     set status = p_status,
         homologation_valid_until = coalesce(p_valid_until, homologation_valid_until),
         updated_by = auth.uid()
   where id = p_supplier_id;

  insert into public.audit_logs(actor_id, entity, entity_id, action, old_values, new_values, context)
  values (auth.uid(), 'suppliers', p_supplier_id, 'STATUS_FORNECEDOR',
          jsonb_build_object('status', v_old),
          jsonb_build_object('status', p_status),
          jsonb_build_object('reason', p_reason, 'valid_until', p_valid_until));

  return p_status;
end;
$$;

grant execute on function app.fn_set_supplier_status(uuid, public.supplier_status, text, date) to authenticated;
grant execute on function app.is_valid_cnpj(text) to authenticated;


-- ============ 0015_sourcing.sql ============
-- 0015 — Cotação: rodadas, fornecedores convidados, propostas e itens cotados
-- Totais SEMPRE recalculados no banco (nunca confiar no navegador).

create table if not exists public.sourcing_rounds (
  id            uuid primary key default gen_random_uuid(),
  request_id    uuid not null references public.purchase_requests(id),
  round_no      int not null default 1,
  mode          text not null default 'PADRAO' check (mode in ('PADRAO','ENVELOPE_FECHADO')),
  deadline_at   timestamptz,
  message       text,
  is_open       boolean not null default true,
  opened_at     timestamptz,
  opened_by     uuid references auth.users(id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id) default auth.uid(),
  constraint sourcing_rounds_uk unique (request_id, round_no)
);
create index if not exists ix_rounds_request on public.sourcing_rounds(request_id);

create table if not exists public.sourcing_suppliers (
  id             uuid primary key default gen_random_uuid(),
  round_id       uuid not null references public.sourcing_rounds(id) on delete cascade,
  supplier_id    uuid not null references public.suppliers(id),
  status         text not null default 'CONVIDADO'
                 check (status in ('CONVIDADO','RESPONDIDO','RECUSADO','SEM_RESPOSTA')),
  decline_reason text,
  created_at     timestamptz not null default now(),
  constraint sourcing_suppliers_uk unique (round_id, supplier_id)
);
create index if not exists ix_sourcing_suppliers_round on public.sourcing_suppliers(round_id);

create table if not exists public.supplier_quotes (
  id                uuid primary key default gen_random_uuid(),
  round_id          uuid not null references public.sourcing_rounds(id),
  supplier_id       uuid not null references public.suppliers(id),
  version_no        int not null default 1,
  is_current        boolean not null default true,
  reference         text,
  quote_date        date,
  valid_until       date,
  currency          char(3) not null default 'BRL',
  payment_terms     text,
  delivery_days     int check (delivery_days >= 0),
  freight_type      text,
  freight_amount    numeric(18,2) not null default 0 check (freight_amount >= 0),
  insurance_amount  numeric(18,2) not null default 0 check (insurance_amount >= 0),
  taxes_amount      numeric(18,2) not null default 0 check (taxes_amount >= 0),
  discount_amount   numeric(18,2) not null default 0 check (discount_amount >= 0),
  warranty          text,
  commercial_notes  text,
  technical_notes   text,
  contact_name      text,
  status            text not null default 'RECEBIDA'
                    check (status in ('RASCUNHO','RECEBIDA','VALIDA','DESCLASSIFICADA')),
  disqualify_reason text,
  items_subtotal    numeric(18,2) not null default 0,
  total_cost        numeric(18,2) not null default 0,
  submitted_at      timestamptz,
  protocol          text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id) default auth.uid(),
  constraint supplier_quotes_uk unique (round_id, supplier_id, version_no)
);
create index if not exists ix_quotes_round on public.supplier_quotes(round_id);

create table if not exists public.supplier_quote_items (
  id                  uuid primary key default gen_random_uuid(),
  quote_id            uuid not null references public.supplier_quotes(id) on delete cascade,
  request_item_id     uuid not null references public.purchase_request_items(id),
  will_quote          boolean not null default true,
  offered_description text,
  brand               text,
  model               text,
  quantity_offered    numeric(18,4) not null default 0 check (quantity_offered >= 0),
  unit_price          numeric(18,2) not null default 0 check (unit_price >= 0),
  discount_amount     numeric(18,2) not null default 0 check (discount_amount >= 0),
  taxes_amount        numeric(18,2) not null default 0 check (taxes_amount >= 0),
  delivery_days       int check (delivery_days >= 0),
  technical_fit       text not null default 'ATENDE'
                      check (technical_fit in ('ATENDE','ATENDE_PARCIALMENTE','NAO_ATENDE')),
  is_equivalent       boolean not null default false,
  equivalent_reason   text,
  unavailable         boolean not null default false,
  notes               text,
  line_total          numeric(18,2) generated always as
                      (round(quantity_offered * unit_price - discount_amount + taxes_amount, 2)) stored,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint quote_items_uk unique (quote_id, request_item_id)
);
create index if not exists ix_quote_items_quote on public.supplier_quote_items(quote_id);

create table if not exists public.quote_versions (
  id          bigint generated always as identity primary key,
  quote_id    uuid not null references public.supplier_quotes(id),
  version_no  int not null,
  snapshot    jsonb not null,
  reason      text,
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id)
);
create index if not exists ix_quote_versions_quote on public.quote_versions(quote_id);

-- Fórmula documentada do custo total de aquisição:
--   items_subtotal = Σ (qtd*unit - desc + impostos) dos itens cotados e disponíveis
--   total_cost     = items_subtotal - desconto geral + impostos + frete + seguro
create or replace function app.fn_recalc_quote(p_quote_id uuid)
returns void
language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_sub numeric(18,2);
begin
  select coalesce(sum(i.line_total), 0) into v_sub
    from public.supplier_quote_items i
   where i.quote_id = p_quote_id and i.will_quote and not i.unavailable;

  update public.supplier_quotes q
     set items_subtotal = v_sub,
         total_cost = round(v_sub - q.discount_amount + q.taxes_amount
                            + q.freight_amount + q.insurance_amount, 2)
   where q.id = p_quote_id;
end;
$$;

create or replace function app.tg_recalc_quote_from_item()
returns trigger language plpgsql security definer
set search_path = app, public, pg_temp
as $$
begin
  perform app.fn_recalc_quote(coalesce(new.quote_id, old.quote_id));
  return null;
end;
$$;
drop trigger if exists tg_recalc_quote on public.supplier_quote_items;
create trigger tg_recalc_quote after insert or update or delete on public.supplier_quote_items
  for each row execute function app.tg_recalc_quote_from_item();

create or replace function app.tg_recalc_quote_header()
returns trigger language plpgsql security definer
set search_path = app, public, pg_temp
as $$
begin
  if new.discount_amount is distinct from old.discount_amount
     or new.taxes_amount is distinct from old.taxes_amount
     or new.freight_amount is distinct from old.freight_amount
     or new.insurance_amount is distinct from old.insurance_amount then
    perform app.fn_recalc_quote(new.id);
  end if;
  return null;
end;
$$;
drop trigger if exists tg_recalc_quote_header on public.supplier_quotes;
create trigger tg_recalc_quote_header after update on public.supplier_quotes
  for each row execute function app.tg_recalc_quote_header();

do $$
declare t text;
begin
  foreach t in array array['sourcing_rounds','supplier_quotes','supplier_quote_items'] loop
    execute format('drop trigger if exists tg_touch on public.%I', t);
    execute format('create trigger tg_touch before update on public.%I
                    for each row execute function app.tg_touch_updated_at()', t);
  end loop;
  foreach t in array array['sourcing_rounds','sourcing_suppliers','supplier_quotes','supplier_quote_items'] loop
    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format('create trigger tg_audit after insert or update or delete on public.%I
                    for each row execute function app.tg_audit()', t);
  end loop;
end $$;


-- ============ 0016_comparison_recommendation.sql ============
-- 0016 — Mapa comparativo + recomendação de compra
-- O sistema NÃO elege vencedor. Ele calcula e destaca; a decisão é humana.

-- View do comparativo por item (uma linha por item × fornecedor × proposta vigente)
create or replace view public.v_comparison_items as
select
  r.id                as request_id,
  ri.id               as request_item_id,
  ri.line_no,
  ri.description      as item_description,
  ri.quantity         as quantity_requested,
  ri.unit_price       as estimated_unit_price,
  q.id                as quote_id,
  q.supplier_id,
  s.legal_name        as supplier_name,
  s.status            as supplier_status,
  qi.unit_price,
  qi.quantity_offered,
  qi.line_total,
  qi.delivery_days,
  qi.technical_fit,
  qi.is_equivalent,
  qi.unavailable,
  q.payment_terms,
  q.valid_until,
  q.status            as quote_status,
  -- destaques calculados (menor preço/prazo entre propostas válidas do item)
  min(qi.unit_price) filter (where qi.will_quote and not qi.unavailable)
    over (partition by ri.id)                       as best_unit_price,
  min(qi.delivery_days) filter (where qi.will_quote and not qi.unavailable)
    over (partition by ri.id)                       as best_delivery_days
from public.purchase_requests r
join public.purchase_request_items ri on ri.request_id = r.id
join public.sourcing_rounds sr        on sr.request_id = r.id
join public.supplier_quotes q         on q.round_id = sr.id and q.is_current
join public.suppliers s               on s.id = q.supplier_id
join public.supplier_quote_items qi   on qi.quote_id = q.id and qi.request_item_id = ri.id
where q.status <> 'DESCLASSIFICADA';

-- View do comparativo por proposta (totais consolidados)
create or replace view public.v_comparison_quotes as
select
  sr.request_id,
  q.id            as quote_id,
  q.supplier_id,
  s.legal_name    as supplier_name,
  s.status        as supplier_status,
  s.rating        as supplier_rating,
  q.items_subtotal,
  q.discount_amount,
  q.taxes_amount,
  q.freight_amount,
  q.insurance_amount,
  q.total_cost,
  q.payment_terms,
  q.delivery_days,
  q.valid_until,
  q.status,
  -- cobertura: itens efetivamente cotados / itens da demanda
  (select count(*) from public.supplier_quote_items i
    where i.quote_id = q.id and i.will_quote and not i.unavailable)    as items_quoted,
  (select count(*) from public.purchase_request_items ri
    where ri.request_id = sr.request_id)                                as items_requested,
  -- economia vs. estimativa da demanda
  (select r.estimated_total from public.purchase_requests r where r.id = sr.request_id)
    - q.total_cost                                                      as savings_vs_estimate,
  -- diferença para a proposta de menor custo total
  q.total_cost - min(q.total_cost) over (partition by sr.request_id)    as diff_to_lowest
from public.sourcing_rounds sr
join public.supplier_quotes q on q.round_id = sr.id and q.is_current
join public.suppliers s       on s.id = q.supplier_id
where q.status <> 'DESCLASSIFICADA';

-- ---------- Recomendação ----------
create table if not exists public.recommendations (
  id                uuid primary key default gen_random_uuid(),
  request_id        uuid not null references public.purchase_requests(id),
  version_no        int not null default 1,
  is_current        boolean not null default true,
  total_amount      numeric(18,2) not null default 0,
  savings_amount    numeric(18,2) not null default 0,
  justification     text not null,
  risks             text,
  buyer_notes       text,
  not_lowest_price  boolean not null default false,
  not_lowest_reason text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id) default auth.uid(),
  constraint recommendations_uk unique (request_id, version_no),
  -- Escolher fora do menor preço EXIGE justificativa específica.
  constraint recommendations_not_lowest_ck
    check (not not_lowest_price or (not_lowest_reason is not null and length(trim(not_lowest_reason)) > 0))
);
create index if not exists ix_recommendations_request on public.recommendations(request_id);

-- Adjudicação por item: cada item pode ir para um fornecedor diferente.
create table if not exists public.recommendation_items (
  id                 uuid primary key default gen_random_uuid(),
  recommendation_id  uuid not null references public.recommendations(id) on delete cascade,
  request_item_id    uuid not null references public.purchase_request_items(id),
  quote_id           uuid not null references public.supplier_quotes(id),
  supplier_id        uuid not null references public.suppliers(id),
  quantity           numeric(18,4) not null check (quantity > 0),
  unit_price         numeric(18,2) not null check (unit_price >= 0),
  line_total         numeric(18,2) generated always as (round(quantity * unit_price, 2)) stored,
  created_at         timestamptz not null default now(),
  constraint recommendation_items_uk unique (recommendation_id, request_item_id)
);
create index if not exists ix_rec_items_rec on public.recommendation_items(recommendation_id);

-- Total da recomendação = soma dos itens adjudicados.
create or replace function app.tg_recalc_recommendation()
returns trigger language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_rec uuid;
begin
  v_rec := coalesce(new.recommendation_id, old.recommendation_id);
  update public.recommendations rc
     set total_amount = coalesce((select sum(ri.line_total) from public.recommendation_items ri
                                  where ri.recommendation_id = v_rec), 0)
   where rc.id = v_rec;
  return null;
end;
$$;
drop trigger if exists tg_recalc_rec on public.recommendation_items;
create trigger tg_recalc_rec after insert or update or delete on public.recommendation_items
  for each row execute function app.tg_recalc_recommendation();

-- Total adjudicado por fornecedor (alerta de divisão da compra).
create or replace view public.v_award_by_supplier as
select ri.recommendation_id, ri.supplier_id, s.legal_name as supplier_name,
       count(*) as items_awarded, sum(ri.line_total) as awarded_total
from public.recommendation_items ri
join public.suppliers s on s.id = ri.supplier_id
group by ri.recommendation_id, ri.supplier_id, s.legal_name;

do $$
declare t text;
begin
  foreach t in array array['recommendations'] loop
    execute format('drop trigger if exists tg_touch on public.%I', t);
    execute format('create trigger tg_touch before update on public.%I
                    for each row execute function app.tg_touch_updated_at()', t);
  end loop;
  foreach t in array array['recommendations','recommendation_items'] loop
    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format('create trigger tg_audit after insert or update or delete on public.%I
                    for each row execute function app.tg_audit()', t);
  end loop;
end $$;


-- ============ 0017_approvals.sql ============
-- 0017 — Matriz de aprovação configurável + instâncias + decisões imutáveis

create table if not exists public.approval_rules (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  company_id     uuid references public.companies(id),
  business_unit_id uuid references public.business_units(id),
  department_id  uuid references public.departments(id),
  cost_center_id uuid references public.cost_centers(id),
  category_id    uuid references public.categories(id),
  purchase_type  public.purchase_type,
  is_emergency   boolean,
  min_amount     numeric(18,2) not null default 0,
  max_amount     numeric(18,2),                  -- null = sem teto
  currency       char(3) not null default 'BRL',
  priority_order int not null default 100,        -- menor = avaliada antes
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint approval_rules_amount_ck check (max_amount is null or max_amount >= min_amount)
);

create table if not exists public.approval_rule_steps (
  id             uuid primary key default gen_random_uuid(),
  rule_id        uuid not null references public.approval_rules(id) on delete cascade,
  step_no        int not null,
  mode           text not null default 'SEQUENCIAL' check (mode in ('SEQUENCIAL','PARALELA')),
  approver_user_id uuid references auth.users(id),
  approver_role  text,                            -- código do papel
  use_dept_manager boolean not null default false,
  min_approvals  int not null default 1 check (min_approvals >= 1),
  unanimous      boolean not null default false,
  deadline_hours int,
  created_at     timestamptz not null default now(),
  constraint rule_steps_uk unique (rule_id, step_no),
  -- a etapa precisa apontar para alguém
  constraint rule_steps_target_ck check (
    approver_user_id is not null or approver_role is not null or use_dept_manager
  )
);

-- Instância = execução da matriz para uma recomendação específica.
create table if not exists public.approval_instances (
  id                uuid primary key default gen_random_uuid(),
  request_id        uuid not null references public.purchase_requests(id),
  recommendation_id uuid not null references public.recommendations(id),
  rule_id           uuid references public.approval_rules(id),
  amount            numeric(18,2) not null,
  status            text not null default 'EM_ANDAMENTO'
                    check (status in ('EM_ANDAMENTO','APROVADA','REJEITADA','CANCELADA')),
  current_step      int not null default 1,
  created_at        timestamptz not null default now(),
  closed_at         timestamptz
);
create index if not exists ix_approval_inst_request on public.approval_instances(request_id);

create table if not exists public.approval_instance_steps (
  id            uuid primary key default gen_random_uuid(),
  instance_id   uuid not null references public.approval_instances(id) on delete cascade,
  step_no       int not null,
  mode          text not null default 'SEQUENCIAL',
  approver_user_id uuid references auth.users(id),
  approver_role text,
  min_approvals int not null default 1,
  status        text not null default 'PENDENTE'
                check (status in ('PENDENTE','APROVADA','REJEITADA','PULADA')),
  deadline_at   timestamptz,
  created_at    timestamptz not null default now(),
  constraint inst_steps_uk unique (instance_id, step_no)
);

-- Decisões: append-only. Sem UPDATE/DELETE (garantido por RLS na 0019).
create table if not exists public.approval_actions (
  id              uuid primary key default gen_random_uuid(),
  instance_id     uuid not null references public.approval_instances(id),
  step_no         int not null,
  approver_id     uuid not null references auth.users(id),
  decision        public.approval_decision not null,
  comment         text,
  ip_address      inet,
  user_agent      text,
  recommendation_version int,
  amount_at_decision numeric(18,2),
  quote_snapshot  jsonb,
  created_at      timestamptz not null default now()
);
create index if not exists ix_approval_actions_inst on public.approval_actions(instance_id);

-- ---------- Seleção da regra aplicável ----------
create or replace function app.fn_find_approval_rule(p_request_id uuid, p_amount numeric)
returns uuid
language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select ar.id
  from public.approval_rules ar
  join public.purchase_requests r on r.id = p_request_id
  where ar.is_active
    and (ar.company_id       is null or ar.company_id = r.company_id)
    and (ar.business_unit_id is null or ar.business_unit_id = r.business_unit_id)
    and (ar.department_id    is null or ar.department_id = r.department_id)
    and (ar.cost_center_id   is null or ar.cost_center_id = r.cost_center_id)
    and (ar.category_id      is null or ar.category_id = r.category_id)
    and (ar.purchase_type    is null or ar.purchase_type = r.purchase_type)
    and (ar.is_emergency     is null or ar.is_emergency = r.is_emergency)
    and p_amount >= ar.min_amount
    and (ar.max_amount is null or p_amount <= ar.max_amount)
  order by ar.priority_order, ar.min_amount desc
  limit 1;
$$;

-- ---------- Abrir fluxo de aprovação a partir da recomendação ----------
create or replace function app.fn_start_approval(p_recommendation_id uuid)
returns uuid
language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare
  v_rec  public.recommendations%rowtype;
  v_rule uuid;
  v_inst uuid;
  s      record;
begin
  if not (app.is_purchasing() or app.is_admin()) then
    raise exception 'Apenas compras pode enviar para aprovação' using errcode = '42501';
  end if;

  select * into v_rec from public.recommendations where id = p_recommendation_id;
  if not found then raise exception 'Recomendação não encontrada' using errcode='P0002'; end if;

  v_rule := app.fn_find_approval_rule(v_rec.request_id, v_rec.total_amount);
  if v_rule is null then
    raise exception 'Nenhuma regra de aprovação aplicável para o valor %', v_rec.total_amount
      using errcode = 'P0001';
  end if;

  insert into public.approval_instances (request_id, recommendation_id, rule_id, amount)
  values (v_rec.request_id, p_recommendation_id, v_rule, v_rec.total_amount)
  returning id into v_inst;

  for s in select * from public.approval_rule_steps where rule_id = v_rule order by step_no loop
    insert into public.approval_instance_steps
      (instance_id, step_no, mode, approver_user_id, approver_role, min_approvals, deadline_at)
    values (v_inst, s.step_no, s.mode, s.approver_user_id, s.approver_role, s.min_approvals,
            case when s.deadline_hours is not null then now() + (s.deadline_hours || ' hours')::interval end);
  end loop;

  perform app.fn_transition_request(v_rec.request_id, 'AGUARDANDO_APROVACAO_FINANCEIRA', 'Enviada para aprovação');
  return v_inst;
end;
$$;

-- ---------- Registrar decisão ----------
create or replace function app.fn_decide_approval(
  p_instance_id uuid,
  p_decision    public.approval_decision,
  p_comment     text default null
)
returns text
language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare
  v_inst public.approval_instances%rowtype;
  v_step public.approval_instance_steps%rowtype;
  v_rec  public.recommendations%rowtype;
  v_authorized boolean := false;
  v_approvals int;
  v_next int;
begin
  select * into v_inst from public.approval_instances where id = p_instance_id for update;
  if not found then raise exception 'Instância não encontrada' using errcode='P0002'; end if;
  if v_inst.status <> 'EM_ANDAMENTO' then
    raise exception 'Este fluxo já foi encerrado' using errcode='P0001';
  end if;

  select * into v_step from public.approval_instance_steps
   where instance_id = p_instance_id and step_no = v_inst.current_step;

  -- autorização: usuário nominal, papel, ou admin
  if v_step.approver_user_id is not null and v_step.approver_user_id = auth.uid() then
    v_authorized := true;
  elsif v_step.approver_role is not null and app.has_role(v_step.approver_role) then
    v_authorized := true;
  elsif app.is_admin() then
    v_authorized := true;
  end if;
  if not v_authorized then
    raise exception 'Você não é aprovador desta etapa' using errcode='42501';
  end if;

  if p_decision in ('REJEITADO','AJUSTE_SOLICITADO')
     and (p_comment is null or length(trim(p_comment)) = 0) then
    raise exception 'Comentário obrigatório para rejeitar ou solicitar ajustes' using errcode='P0001';
  end if;

  select * into v_rec from public.recommendations where id = v_inst.recommendation_id;

  insert into public.approval_actions
    (instance_id, step_no, approver_id, decision, comment, recommendation_version, amount_at_decision)
  values (p_instance_id, v_inst.current_step, auth.uid(), p_decision, p_comment,
          v_rec.version_no, v_inst.amount);

  if p_decision = 'REJEITADO' then
    update public.approval_instances set status='REJEITADA', closed_at=now() where id=p_instance_id;
    update public.approval_instance_steps set status='REJEITADA'
      where instance_id=p_instance_id and step_no=v_inst.current_step;
    perform app.fn_transition_request(v_inst.request_id, 'REJEITADA', coalesce(p_comment,'Rejeitada na aprovação'));
    return 'REJEITADA';

  elsif p_decision = 'AJUSTE_SOLICITADO' then
    update public.approval_instances set status='CANCELADA', closed_at=now() where id=p_instance_id;
    perform app.fn_transition_request(v_inst.request_id, 'EM_ANALISE_DE_COTACOES', coalesce(p_comment,'Ajustes solicitados'));
    return 'AJUSTE_SOLICITADO';

  elsif p_decision = 'APROVADO' then
    select count(*) into v_approvals from public.approval_actions
     where instance_id=p_instance_id and step_no=v_inst.current_step and decision='APROVADO';

    if v_approvals >= v_step.min_approvals then
      update public.approval_instance_steps set status='APROVADA'
        where instance_id=p_instance_id and step_no=v_inst.current_step;

      select min(step_no) into v_next from public.approval_instance_steps
       where instance_id=p_instance_id and status='PENDENTE';

      if v_next is null then
        update public.approval_instances set status='APROVADA', closed_at=now() where id=p_instance_id;
        perform app.fn_transition_request(v_inst.request_id, 'APROVADA', 'Aprovação concluída');
        return 'APROVADA';
      else
        update public.approval_instances set current_step=v_next where id=p_instance_id;
        return 'PROXIMA_ETAPA';
      end if;
    end if;
    return 'AGUARDANDO_DEMAIS_APROVADORES';
  end if;

  return 'REGISTRADO';
end;
$$;

-- ---------- Invalidação: alterar cotação após início da aprovação derruba as aprovações ----------
create or replace function app.tg_invalidate_approvals()
returns trigger language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_request uuid; v_inst uuid;
begin
  select sr.request_id into v_request
    from public.sourcing_rounds sr where sr.id = new.round_id;

  select ai.id into v_inst from public.approval_instances ai
   where ai.request_id = v_request and ai.status = 'EM_ANDAMENTO' limit 1;

  if v_inst is not null then
    update public.approval_instances set status='CANCELADA', closed_at=now() where id=v_inst;
    insert into public.audit_logs(actor_id, entity, entity_id, action, context)
    values (auth.uid(), 'approval_instances', v_inst, 'APROVACOES_INVALIDADAS',
            jsonb_build_object('motivo','Proposta alterada após início da aprovação',
                               'quote_id', new.id));
  end if;
  return new;
end;
$$;
drop trigger if exists tg_invalidate_approvals on public.supplier_quotes;
create trigger tg_invalidate_approvals after update of total_cost, supplier_id, status
  on public.supplier_quotes
  for each row execute function app.tg_invalidate_approvals();

grant execute on function app.fn_find_approval_rule(uuid, numeric) to authenticated;
grant execute on function app.fn_start_approval(uuid) to authenticated;
grant execute on function app.fn_decide_approval(uuid, public.approval_decision, text) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['approval_rules','approval_rule_steps','approval_instances','approval_actions'] loop
    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format('create trigger tg_audit after insert or update or delete on public.%I
                    for each row execute function app.tg_audit()', t);
  end loop;
end $$;


-- ============ 0018_orders_receipts.sql ============
-- 0018 — Pedidos de compra, recebimento, anexos, comentários e notificações

create table if not exists public.purchase_orders (
  id             uuid primary key default gen_random_uuid(),
  number         text unique,
  request_id     uuid not null references public.purchase_requests(id),
  recommendation_id uuid references public.recommendations(id),
  supplier_id    uuid not null references public.suppliers(id),
  status         public.purchase_order_status not null default 'RASCUNHO',
  payment_terms  text,
  delivery_days  int,
  freight_type   text,
  delivery_location text,
  total_amount   numeric(18,2) not null default 0,
  notes          text,
  issued_at      timestamptz,
  sent_at        timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  created_by     uuid references auth.users(id) default auth.uid()
);
create index if not exists ix_orders_request on public.purchase_orders(request_id);
create index if not exists ix_orders_supplier on public.purchase_orders(supplier_id);

create table if not exists public.purchase_order_items (
  id              uuid primary key default gen_random_uuid(),
  order_id        uuid not null references public.purchase_orders(id) on delete cascade,
  request_item_id uuid not null references public.purchase_request_items(id),
  line_no         int not null default 1,
  description     text not null,
  quantity        numeric(18,4) not null check (quantity > 0),
  unit_price      numeric(18,2) not null check (unit_price >= 0),
  line_total      numeric(18,2) generated always as (round(quantity * unit_price, 2)) stored,
  created_at      timestamptz not null default now()
);
create index if not exists ix_order_items_order on public.purchase_order_items(order_id);

create table if not exists public.receipts (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.purchase_orders(id),
  received_at  date not null default current_date,
  invoice_number text,
  responsible_id uuid references auth.users(id) default auth.uid(),
  has_divergence boolean not null default false,
  divergence_notes text,
  accepted     boolean not null default true,
  notes        text,
  created_at   timestamptz not null default now()
);
create index if not exists ix_receipts_order on public.receipts(order_id);

create table if not exists public.receipt_items (
  id              uuid primary key default gen_random_uuid(),
  receipt_id      uuid not null references public.receipts(id) on delete cascade,
  order_item_id   uuid not null references public.purchase_order_items(id),
  quantity_received numeric(18,4) not null check (quantity_received > 0),
  notes           text,
  created_at      timestamptz not null default now()
);
create index if not exists ix_receipt_items_receipt on public.receipt_items(receipt_id);

-- Saldo pendente por item do pedido
create or replace view public.v_order_item_balance as
select oi.order_id, oi.id as order_item_id, oi.description, oi.quantity as quantity_ordered,
       coalesce(sum(ri.quantity_received), 0) as quantity_received,
       oi.quantity - coalesce(sum(ri.quantity_received), 0) as quantity_pending
from public.purchase_order_items oi
left join public.receipt_items ri on ri.order_item_id = oi.id
group by oi.order_id, oi.id, oi.description, oi.quantity;

-- Numeração do pedido
create or replace function app.tg_order_number()
returns trigger language plpgsql security definer
set search_path = app, public, pg_temp
as $$
begin
  if new.number is null then
    new.number := app.fn_next_number('purchase_order', 'PC');
  end if;
  return new;
end;
$$;
drop trigger if exists tg_order_number on public.purchase_orders;
create trigger tg_order_number before insert on public.purchase_orders
  for each row execute function app.tg_order_number();

-- Total do pedido a partir dos itens
create or replace function app.tg_recalc_order_total()
returns trigger language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_ord uuid;
begin
  v_ord := coalesce(new.order_id, old.order_id);
  update public.purchase_orders o
     set total_amount = coalesce((select sum(i.line_total) from public.purchase_order_items i
                                  where i.order_id = v_ord), 0)
   where o.id = v_ord;
  return null;
end;
$$;
drop trigger if exists tg_recalc_order on public.purchase_order_items;
create trigger tg_recalc_order after insert or update or delete on public.purchase_order_items
  for each row execute function app.tg_recalc_order_total();

-- ---------- Geração do pedido a partir da recomendação APROVADA ----------
-- Um pedido por fornecedor adjudicado. Copia exatamente o que foi aprovado.
create or replace function app.fn_generate_orders(p_request_id uuid)
returns int
language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare
  v_status public.request_status;
  v_rec    public.recommendations%rowtype;
  v_count  int := 0;
  sup      record;
  v_order  uuid;
  v_line   int;
  it       record;
begin
  if not (app.is_purchasing() or app.is_admin()) then
    raise exception 'Apenas compras pode emitir pedidos' using errcode='42501';
  end if;

  select status into v_status from public.purchase_requests where id = p_request_id;
  if v_status <> 'APROVADA' then
    raise exception 'A demanda precisa estar APROVADA para emitir pedido (atual: %)', v_status
      using errcode='P0001';
  end if;

  select * into v_rec from public.recommendations
   where request_id = p_request_id and is_current order by version_no desc limit 1;
  if not found then raise exception 'Nenhuma recomendação vigente' using errcode='P0002'; end if;

  for sup in
    select ri.supplier_id, q.payment_terms, q.delivery_days, q.freight_type
    from public.recommendation_items ri
    join public.supplier_quotes q on q.id = ri.quote_id
    where ri.recommendation_id = v_rec.id
    group by ri.supplier_id, q.payment_terms, q.delivery_days, q.freight_type
  loop
    insert into public.purchase_orders
      (request_id, recommendation_id, supplier_id, status, payment_terms, delivery_days, freight_type, issued_at)
    values (p_request_id, v_rec.id, sup.supplier_id, 'EMITIDO', sup.payment_terms,
            sup.delivery_days, sup.freight_type, now())
    returning id into v_order;

    v_line := 0;
    for it in
      select ri.request_item_id, ri.quantity, ri.unit_price, pri.description
      from public.recommendation_items ri
      join public.purchase_request_items pri on pri.id = ri.request_item_id
      where ri.recommendation_id = v_rec.id and ri.supplier_id = sup.supplier_id
      order by pri.line_no
    loop
      v_line := v_line + 1;
      insert into public.purchase_order_items
        (order_id, request_item_id, line_no, description, quantity, unit_price)
      values (v_order, it.request_item_id, v_line, it.description, it.quantity, it.unit_price);
    end loop;

    v_count := v_count + 1;
  end loop;

  if v_count > 0 then
    perform app.fn_transition_request(p_request_id, 'PEDIDO_EMITIDO', 'Pedido(s) gerado(s) automaticamente');
  end if;
  return v_count;
end;
$$;
grant execute on function app.fn_generate_orders(uuid) to authenticated;

-- ---------- Anexos, comentários e notificações ----------
create table if not exists public.attachments (
  id            uuid primary key default gen_random_uuid(),
  entity        text not null,             -- purchase_requests, supplier_quotes, purchase_orders, receipts
  entity_id     uuid not null,
  bucket        text not null,
  storage_path  text not null,             -- nome físico (UUID)
  original_name text not null,
  mime_type     text,
  size_bytes    bigint,
  doc_type      text,
  deleted_at    timestamptz,               -- exclusão lógica
  created_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id) default auth.uid()
);
create index if not exists ix_attachments_entity on public.attachments(entity, entity_id);

create table if not exists public.comments (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.purchase_requests(id),
  body        text not null,
  is_internal boolean not null default false,
  created_at  timestamptz not null default now(),
  created_by  uuid references auth.users(id) default auth.uid()
);
create index if not exists ix_comments_request on public.comments(request_id);

create table if not exists public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  type        text not null,
  title       text not null,
  body        text,
  link        text,
  priority    public.priority not null default 'NORMAL',
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists ix_notifications_user on public.notifications(user_id, read_at);

do $$
declare t text;
begin
  foreach t in array array['purchase_orders'] loop
    execute format('drop trigger if exists tg_touch on public.%I', t);
    execute format('create trigger tg_touch before update on public.%I
                    for each row execute function app.tg_touch_updated_at()', t);
  end loop;
  foreach t in array array['purchase_orders','purchase_order_items','receipts','receipt_items','attachments'] loop
    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format('create trigger tg_audit after insert or update or delete on public.%I
                    for each row execute function app.tg_audit()', t);
  end loop;
end $$;


-- ============ 0019_rls_operational.sql ============
-- 0019 — RLS de cotação, aprovação, pedidos, recebimento, anexos e Storage

-- Helper: acesso à rodada/proposta pela demanda-mãe
create or replace function app.can_read_round(p_round_id uuid)
returns boolean language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select exists (select 1 from public.sourcing_rounds sr
                 where sr.id = p_round_id and app.can_read_request(sr.request_id));
$$;

create or replace function app.can_read_quote(p_quote_id uuid)
returns boolean language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select exists (select 1 from public.supplier_quotes q where q.id = p_quote_id and app.can_read_round(q.round_id));
$$;

-- Envelope fechado: antes da abertura, valores só para quem abriu/admin.
create or replace function app.can_see_quote_values(p_quote_id uuid)
returns boolean language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select exists (
    select 1 from public.supplier_quotes q
    join public.sourcing_rounds sr on sr.id = q.round_id
    where q.id = p_quote_id
      and app.can_read_round(q.round_id)
      and (sr.mode <> 'ENVELOPE_FECHADO' or sr.opened_at is not null)
  );
$$;

grant execute on function app.can_read_round(uuid) to authenticated;
grant execute on function app.can_read_quote(uuid) to authenticated;
grant execute on function app.can_see_quote_values(uuid) to authenticated;

alter table public.sourcing_rounds          enable row level security;
alter table public.sourcing_suppliers        enable row level security;
alter table public.supplier_quotes           enable row level security;
alter table public.supplier_quote_items      enable row level security;
alter table public.quote_versions            enable row level security;
alter table public.recommendations           enable row level security;
alter table public.recommendation_items      enable row level security;
alter table public.approval_rules            enable row level security;
alter table public.approval_rule_steps       enable row level security;
alter table public.approval_instances        enable row level security;
alter table public.approval_instance_steps   enable row level security;
alter table public.approval_actions          enable row level security;
alter table public.purchase_orders           enable row level security;
alter table public.purchase_order_items      enable row level security;
alter table public.receipts                  enable row level security;
alter table public.receipt_items             enable row level security;
alter table public.attachments               enable row level security;
alter table public.comments                  enable row level security;
alter table public.notifications             enable row level security;

-- ---------- Cotação ----------
drop policy if exists sel_rounds on public.sourcing_rounds;
create policy sel_rounds on public.sourcing_rounds for select to authenticated
  using (app.can_read_request(request_id));
drop policy if exists wr_rounds on public.sourcing_rounds;
create policy wr_rounds on public.sourcing_rounds for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

drop policy if exists sel_sourcing_suppliers on public.sourcing_suppliers;
create policy sel_sourcing_suppliers on public.sourcing_suppliers for select to authenticated
  using (app.can_read_round(round_id));
drop policy if exists wr_sourcing_suppliers on public.sourcing_suppliers;
create policy wr_sourcing_suppliers on public.sourcing_suppliers for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

-- Propostas: leitura respeita envelope fechado.
drop policy if exists sel_quotes on public.supplier_quotes;
create policy sel_quotes on public.supplier_quotes for select to authenticated
  using (app.can_see_quote_values(id) or app.is_admin());
drop policy if exists wr_quotes on public.supplier_quotes;
create policy wr_quotes on public.supplier_quotes for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

drop policy if exists sel_quote_items on public.supplier_quote_items;
create policy sel_quote_items on public.supplier_quote_items for select to authenticated
  using (app.can_see_quote_values(quote_id) or app.is_admin());
drop policy if exists wr_quote_items on public.supplier_quote_items;
create policy wr_quote_items on public.supplier_quote_items for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

drop policy if exists sel_quote_versions on public.quote_versions;
create policy sel_quote_versions on public.quote_versions for select to authenticated
  using (app.can_read_quote(quote_id));

-- ---------- Recomendação ----------
drop policy if exists sel_recommendations on public.recommendations;
create policy sel_recommendations on public.recommendations for select to authenticated
  using (app.can_read_request(request_id));
drop policy if exists wr_recommendations on public.recommendations;
create policy wr_recommendations on public.recommendations for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

drop policy if exists sel_rec_items on public.recommendation_items;
create policy sel_rec_items on public.recommendation_items for select to authenticated
  using (exists (select 1 from public.recommendations rc
                 where rc.id = recommendation_id and app.can_read_request(rc.request_id)));
drop policy if exists wr_rec_items on public.recommendation_items;
create policy wr_rec_items on public.recommendation_items for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

-- ---------- Matriz de aprovação (config: admin; leitura ampla p/ transparência) ----------
do $$
declare t text;
begin
  foreach t in array array['approval_rules','approval_rule_steps'] loop
    execute format('drop policy if exists sel_%1$s on public.%1$s', t);
    execute format('create policy sel_%1$s on public.%1$s for select to authenticated using (true)', t);
    execute format('drop policy if exists wr_%1$s on public.%1$s', t);
    execute format('create policy wr_%1$s on public.%1$s for all to authenticated
                    using (app.is_admin()) with check (app.is_admin())', t);
  end loop;
end $$;

-- Instâncias: quem enxerga a demanda + aprovadores.
drop policy if exists sel_approval_instances on public.approval_instances;
create policy sel_approval_instances on public.approval_instances for select to authenticated
  using (app.can_read_request(request_id) or app.has_role('APROVADOR_FINANCEIRO'));

drop policy if exists sel_approval_steps on public.approval_instance_steps;
create policy sel_approval_steps on public.approval_instance_steps for select to authenticated
  using (exists (select 1 from public.approval_instances ai
                 where ai.id = instance_id
                   and (app.can_read_request(ai.request_id) or app.has_role('APROVADOR_FINANCEIRO'))));

-- Decisões: LEITURA apenas. Sem insert/update/delete via API → só a RPC definer grava.
-- Isso torna a decisão imutável (critério de aceite 9).
drop policy if exists sel_approval_actions on public.approval_actions;
create policy sel_approval_actions on public.approval_actions for select to authenticated
  using (exists (select 1 from public.approval_instances ai
                 where ai.id = instance_id
                   and (app.can_read_request(ai.request_id) or app.has_role('APROVADOR_FINANCEIRO')))
         or app.is_auditor());

-- ---------- Pedidos e recebimento ----------
drop policy if exists sel_orders on public.purchase_orders;
create policy sel_orders on public.purchase_orders for select to authenticated
  using (app.can_read_request(request_id));
drop policy if exists wr_orders on public.purchase_orders;
create policy wr_orders on public.purchase_orders for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

drop policy if exists sel_order_items on public.purchase_order_items;
create policy sel_order_items on public.purchase_order_items for select to authenticated
  using (exists (select 1 from public.purchase_orders o
                 where o.id = order_id and app.can_read_request(o.request_id)));
drop policy if exists wr_order_items on public.purchase_order_items;
create policy wr_order_items on public.purchase_order_items for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

drop policy if exists sel_receipts on public.receipts;
create policy sel_receipts on public.receipts for select to authenticated
  using (exists (select 1 from public.purchase_orders o
                 where o.id = order_id and app.can_read_request(o.request_id)));
drop policy if exists wr_receipts on public.receipts;
create policy wr_receipts on public.receipts for all to authenticated
  using (exists (select 1 from public.purchase_orders o
                 where o.id = order_id and app.can_read_request(o.request_id)))
  with check (exists (select 1 from public.purchase_orders o
                      where o.id = order_id and app.can_read_request(o.request_id)));

drop policy if exists sel_receipt_items on public.receipt_items;
create policy sel_receipt_items on public.receipt_items for select to authenticated
  using (exists (select 1 from public.receipts rc join public.purchase_orders o on o.id = rc.order_id
                 where rc.id = receipt_id and app.can_read_request(o.request_id)));
drop policy if exists wr_receipt_items on public.receipt_items;
create policy wr_receipt_items on public.receipt_items for all to authenticated
  using (exists (select 1 from public.receipts rc join public.purchase_orders o on o.id = rc.order_id
                 where rc.id = receipt_id and app.can_read_request(o.request_id)))
  with check (exists (select 1 from public.receipts rc join public.purchase_orders o on o.id = rc.order_id
                      where rc.id = receipt_id and app.can_read_request(o.request_id)));

-- ---------- Anexos, comentários, notificações ----------
drop policy if exists sel_attachments on public.attachments;
create policy sel_attachments on public.attachments for select to authenticated
  using (
    deleted_at is null and (
      (entity = 'purchase_requests' and app.can_read_request(entity_id))
      or (entity = 'supplier_quotes' and app.can_read_quote(entity_id))
      or app.is_purchasing() or app.is_admin() or app.is_auditor()
    )
  );
drop policy if exists wr_attachments on public.attachments;
create policy wr_attachments on public.attachments for all to authenticated
  using (created_by = auth.uid() or app.is_purchasing() or app.is_admin())
  with check (created_by = auth.uid() or app.is_purchasing() or app.is_admin());

drop policy if exists sel_comments on public.comments;
create policy sel_comments on public.comments for select to authenticated
  using (app.can_read_request(request_id) and (not is_internal or app.is_purchasing() or app.is_admin()));
drop policy if exists ins_comments on public.comments;
create policy ins_comments on public.comments for insert to authenticated
  with check (created_by = auth.uid() and app.can_read_request(request_id));

drop policy if exists sel_notifications on public.notifications;
create policy sel_notifications on public.notifications for select to authenticated
  using (user_id = auth.uid());
drop policy if exists upd_notifications on public.notifications;
create policy upd_notifications on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ---------- Storage: buckets privados ----------
insert into storage.buckets (id, name, public) values
  ('demand-attachments','demand-attachments', false),
  ('quote-attachments','quote-attachments', false),
  ('supplier-documents','supplier-documents', false),
  ('purchase-orders','purchase-orders', false),
  ('receipt-documents','receipt-documents', false)
on conflict (id) do nothing;

-- Acesso a arquivo segue a permissão do registro-pai: só autenticados, e escrita
-- restrita a compras/admin nos buckets de processo. Download sempre por URL assinada.
drop policy if exists st_sel_buckets on storage.objects;
create policy st_sel_buckets on storage.objects for select to authenticated
  using (bucket_id in ('demand-attachments','quote-attachments','supplier-documents',
                       'purchase-orders','receipt-documents'));

drop policy if exists st_ins_buckets on storage.objects;
create policy st_ins_buckets on storage.objects for insert to authenticated
  with check (
    bucket_id in ('demand-attachments','quote-attachments','supplier-documents',
                  'purchase-orders','receipt-documents')
    -- bloqueia executáveis
    and lower(right(name, 4)) not in ('.exe','.bat','.cmd','.com','.msi','.scr')
    and lower(right(name, 3)) not in ('.sh','.ps1')
  );

drop policy if exists st_upd_buckets on storage.objects;
create policy st_upd_buckets on storage.objects for update to authenticated
  using (owner = auth.uid() or app.is_admin());


-- ============ 0020_supplier_portal.sql ============
-- 0020 — Portal externo do fornecedor: convites, tokens com hash, propostas e isolamento
-- Princípio: o token ORIGINAL nunca é armazenado. Só o hash SHA-256.

create table if not exists public.sourcing_invitations (
  id                uuid primary key default gen_random_uuid(),
  sourcing_round_id uuid not null references public.sourcing_rounds(id) on delete cascade,
  supplier_id       uuid not null references public.suppliers(id),
  contact_id        uuid references public.supplier_contacts(id),
  invited_email     citext not null,
  invitation_status public.invitation_status not null default 'RASCUNHO',
  access_mode       text not null default 'LINK' check (access_mode in ('LINK','LINK_OTP','CONTA')),
  expires_at        timestamptz,
  first_access_at   timestamptz,
  last_access_at    timestamptz,
  responded_at      timestamptz,
  declined_at       timestamptz,
  decline_reason    text,
  revoked_at        timestamptz,
  created_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id) default auth.uid(),
  constraint sourcing_invitations_uk unique (sourcing_round_id, supplier_id, invited_email)
);
create index if not exists ix_invitations_round on public.sourcing_invitations(sourcing_round_id);

create table if not exists public.sourcing_invitation_tokens (
  id             uuid primary key default gen_random_uuid(),
  invitation_id  uuid not null references public.sourcing_invitations(id) on delete cascade,
  token_hash     text not null unique,          -- SHA-256 do token; original NUNCA gravado
  expires_at     timestamptz not null,
  used_at        timestamptz,
  revoked_at     timestamptz,
  failed_attempts int not null default 0,
  last_attempt_at timestamptz,
  otp_hash       text,                          -- OTP também só em hash
  otp_expires_at timestamptz,
  created_at     timestamptz not null default now()
);
create index if not exists ix_inv_tokens_invitation on public.sourcing_invitation_tokens(invitation_id);

create table if not exists public.supplier_participation_responses (
  id            uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.sourcing_invitations(id) on delete cascade,
  will_participate boolean not null,
  reason        text,
  accepted_terms boolean not null default false,
  accepted_nda   boolean not null default false,
  contact_name  text,
  contact_phone text,
  created_at    timestamptz not null default now()
);

-- Rascunho da proposta do fornecedor (não é proposta oficial até o envio)
create table if not exists public.supplier_quote_drafts (
  id            uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.sourcing_invitations(id) on delete cascade,
  payload       jsonb not null default '{}'::jsonb,
  updated_at    timestamptz not null default now(),
  constraint supplier_quote_drafts_uk unique (invitation_id)
);

create table if not exists public.supplier_quote_submissions (
  id            uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.sourcing_invitations(id),
  quote_id      uuid references public.supplier_quotes(id),
  version_no    int not null default 1,
  protocol      text not null unique,
  payload_hash  text not null,                  -- integridade da versão enviada
  submitted_at  timestamptz not null default now(),
  submitted_ip  inet,
  user_agent    text,
  constraint submissions_uk unique (invitation_id, version_no)
);

create table if not exists public.sourcing_messages (
  id            uuid primary key default gen_random_uuid(),
  round_id      uuid not null references public.sourcing_rounds(id) on delete cascade,
  invitation_id uuid references public.sourcing_invitations(id),   -- null = comunicado a todos
  direction     text not null check (direction in ('FORNECEDOR_PARA_COMPRADOR','COMPRADOR_PARA_FORNECEDOR')),
  is_broadcast  boolean not null default false,
  body          text not null,
  created_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id)
);
create index if not exists ix_sourcing_messages_round on public.sourcing_messages(round_id);

create table if not exists public.quote_opening_events (
  id          uuid primary key default gen_random_uuid(),
  round_id    uuid not null references public.sourcing_rounds(id),
  opened_by   uuid references auth.users(id),
  reason      text,
  created_at  timestamptz not null default now()
);

create table if not exists public.supplier_access_logs (
  id            bigint generated always as identity primary key,
  invitation_id uuid references public.sourcing_invitations(id),
  event         text not null,       -- TOKEN_OK, TOKEN_INVALIDO, OTP_OK, OTP_FALHA, ENVIO
  ip_address    inet,
  user_agent    text,
  created_at    timestamptz not null default now()
);
create index if not exists ix_access_logs_invitation on public.supplier_access_logs(invitation_id);

-- ---------- Funções de token (executadas pelo servidor, nunca pelo browser) ----------
-- Grava só o hash. Quem gera o token é o Route Handler; aqui só registramos.
create or replace function app.fn_register_invitation_token(
  p_invitation_id uuid, p_token_hash text, p_expires_at timestamptz
) returns uuid
language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_id uuid;
begin
  insert into public.sourcing_invitation_tokens (invitation_id, token_hash, expires_at)
  values (p_invitation_id, p_token_hash, p_expires_at)
  returning id into v_id;

  update public.sourcing_invitations
     set invitation_status = 'ENVIADO', expires_at = p_expires_at
   where id = p_invitation_id;
  return v_id;
end;
$$;

-- Valida o hash e devolve o contexto do convite. Aplica expiração, revogação e rate limit.
create or replace function app.fn_validate_invitation_token(p_token_hash text)
returns table (
  invitation_id uuid, round_id uuid, supplier_id uuid, supplier_name text,
  request_id uuid, request_number text, request_title text,
  invited_email citext, deadline_at timestamptz, mode text, status public.invitation_status
)
language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_tok public.sourcing_invitation_tokens%rowtype;
begin
  select * into v_tok from public.sourcing_invitation_tokens t where t.token_hash = p_token_hash;

  if not found then
    insert into public.supplier_access_logs(event) values ('TOKEN_INVALIDO');
    raise exception 'Link inválido' using errcode = '42501';
  end if;

  -- rate limit: 10 tentativas falhas bloqueiam o token
  if v_tok.failed_attempts >= 10 then
    raise exception 'Muitas tentativas. Solicite um novo link ao comprador.' using errcode = '42501';
  end if;
  if v_tok.revoked_at is not null then
    raise exception 'Este link foi revogado' using errcode = '42501';
  end if;
  if v_tok.expires_at < now() then
    update public.sourcing_invitations set invitation_status='EXPIRADO' where id = v_tok.invitation_id;
    raise exception 'Este link expirou' using errcode = '42501';
  end if;

  update public.sourcing_invitations
     set first_access_at = coalesce(first_access_at, now()),
         last_access_at  = now(),
         invitation_status = case when invitation_status = 'ENVIADO' then 'ACESSADO'
                                  else invitation_status end
   where id = v_tok.invitation_id;

  insert into public.supplier_access_logs(invitation_id, event)
  values (v_tok.invitation_id, 'TOKEN_OK');

  return query
  select i.id, sr.id, i.supplier_id, s.legal_name, r.id, r.number, r.title,
         i.invited_email, sr.deadline_at, sr.mode, i.invitation_status
  from public.sourcing_invitations i
  join public.sourcing_rounds sr on sr.id = i.sourcing_round_id
  join public.purchase_requests r on r.id = sr.request_id
  join public.suppliers s on s.id = i.supplier_id
  where i.id = v_tok.invitation_id;
end;
$$;

-- Registra falha de tentativa (chamado pelo servidor quando o hash não confere)
create or replace function app.fn_register_token_failure(p_token_hash text)
returns void language plpgsql security definer
set search_path = app, public, pg_temp
as $$
begin
  update public.sourcing_invitation_tokens
     set failed_attempts = failed_attempts + 1, last_attempt_at = now()
   where token_hash = p_token_hash;
end;
$$;

-- ---------- Submissão definitiva da proposta pelo fornecedor ----------
-- Recalcula TUDO no banco. O que o fornecedor manda de total é ignorado.
create or replace function app.fn_submit_supplier_quote(
  p_invitation_id uuid,
  p_header jsonb,
  p_items  jsonb
) returns table (protocol text, total_cost numeric)
language plpgsql security definer
-- 'extensions' precisa estar no search_path: no Supabase o pgcrypto (digest) mora lá,
-- não em public. Sem isso, digest() não resolve e a submissão falha em produção.
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_inv    public.sourcing_invitations%rowtype;
  v_round  public.sourcing_rounds%rowtype;
  v_quote  uuid;
  v_ver    int;
  v_proto  text;
  it       jsonb;
  v_total  numeric(18,2);
begin
  select * into v_inv from public.sourcing_invitations where id = p_invitation_id for update;
  if not found then raise exception 'Convite não encontrado' using errcode='P0002'; end if;
  if v_inv.revoked_at is not null then raise exception 'Convite revogado' using errcode='42501'; end if;

  select * into v_round from public.sourcing_rounds where id = v_inv.sourcing_round_id;
  -- Prazo é validado no banco: não adianta o navegador mentir.
  if v_round.deadline_at is not null and v_round.deadline_at < now() then
    raise exception 'O prazo para envio de propostas encerrou' using errcode='P0001';
  end if;
  if not v_round.is_open then
    raise exception 'Esta rodada está encerrada' using errcode='P0001';
  end if;

  -- A versão é contada sobre supplier_quotes (fonte autoritativa da rodada+fornecedor),
  -- não sobre as submissões: o comprador pode já ter registrado uma proposta manualmente.
  select coalesce(max(version_no),0) + 1 into v_ver
    from public.supplier_quotes
   where round_id = v_inv.sourcing_round_id and supplier_id = v_inv.supplier_id;

  -- versão anterior deixa de ser a vigente (nunca sobrescreve)
  update public.supplier_quotes set is_current = false
   where round_id = v_inv.sourcing_round_id and supplier_id = v_inv.supplier_id;

  insert into public.supplier_quotes (
    round_id, supplier_id, version_no, is_current, reference, quote_date, valid_until,
    payment_terms, delivery_days, freight_type, freight_amount, insurance_amount,
    taxes_amount, discount_amount, warranty, commercial_notes, contact_name,
    status, submitted_at
  ) values (
    v_inv.sourcing_round_id, v_inv.supplier_id, v_ver, true,
    p_header->>'reference', current_date, (p_header->>'valid_until')::date,
    p_header->>'payment_terms', nullif(p_header->>'delivery_days','')::int,
    p_header->>'freight_type',
    coalesce((p_header->>'freight_amount')::numeric, 0),
    coalesce((p_header->>'insurance_amount')::numeric, 0),
    coalesce((p_header->>'taxes_amount')::numeric, 0),
    coalesce((p_header->>'discount_amount')::numeric, 0),
    p_header->>'warranty', p_header->>'commercial_notes', p_header->>'contact_name',
    'RECEBIDA', now()
  ) returning id into v_quote;

  -- Itens: só aceita request_item_id que pertence À DEMANDA da rodada.
  -- Isso impede o fornecedor de injetar item de outro processo.
  for it in select * from jsonb_array_elements(p_items) loop
    if not exists (
      select 1 from public.purchase_request_items pri
      join public.sourcing_rounds sr on sr.request_id = pri.request_id
      where pri.id = (it->>'request_item_id')::uuid and sr.id = v_inv.sourcing_round_id
    ) then
      raise exception 'Item inválido para esta cotação' using errcode='42501';
    end if;

    insert into public.supplier_quote_items (
      quote_id, request_item_id, will_quote, offered_description, brand, model,
      quantity_offered, unit_price, discount_amount, taxes_amount, delivery_days,
      technical_fit, is_equivalent, notes
    ) values (
      v_quote, (it->>'request_item_id')::uuid,
      coalesce((it->>'will_quote')::boolean, true),
      it->>'offered_description', it->>'brand', it->>'model',
      coalesce((it->>'quantity_offered')::numeric, 0),
      coalesce((it->>'unit_price')::numeric, 0),
      coalesce((it->>'discount_amount')::numeric, 0),
      coalesce((it->>'taxes_amount')::numeric, 0),
      nullif(it->>'delivery_days','')::int,
      coalesce(it->>'technical_fit','ATENDE'),
      coalesce((it->>'is_equivalent')::boolean, false),
      it->>'notes'
    );
  end loop;

  perform app.fn_recalc_quote(v_quote);
  select q.total_cost into v_total from public.supplier_quotes q where q.id = v_quote;

  v_proto := 'PROP-' || to_char(now(),'YYYYMMDD') || '-' || upper(substr(replace(v_quote::text,'-',''),1,8));

  insert into public.supplier_quote_submissions
    (invitation_id, quote_id, version_no, protocol, payload_hash)
  values (p_invitation_id, v_quote, v_ver, v_proto,
          encode(digest(p_header::text || p_items::text, 'sha256'), 'hex'));

  update public.supplier_quotes set protocol = v_proto where id = v_quote;

  update public.sourcing_invitations
     set invitation_status='RESPONDIDO', responded_at=now() where id = p_invitation_id;
  update public.sourcing_suppliers set status='RESPONDIDO'
   where round_id = v_inv.sourcing_round_id and supplier_id = v_inv.supplier_id;

  insert into public.supplier_access_logs(invitation_id, event) values (p_invitation_id, 'ENVIO');

  -- notifica o comprador responsável
  insert into public.notifications (user_id, type, title, body, link)
  select r.assigned_buyer_id, 'PROPOSTA_RECEBIDA',
         'Nova proposta recebida', s.legal_name || ' enviou proposta (' || v_proto || ')',
         '/demandas/' || r.id || '/comparativo'
  from public.sourcing_rounds sr
  join public.purchase_requests r on r.id = sr.request_id
  join public.suppliers s on s.id = v_inv.supplier_id
  where sr.id = v_inv.sourcing_round_id and r.assigned_buyer_id is not null;

  return query select v_proto, v_total;
end;
$$;

-- ---------- Recusa de participação ----------
create or replace function app.fn_decline_invitation(p_invitation_id uuid, p_reason text)
returns void language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_inv public.sourcing_invitations%rowtype;
begin
  select * into v_inv from public.sourcing_invitations where id = p_invitation_id;
  if not found then raise exception 'Convite não encontrado' using errcode='P0002'; end if;

  update public.sourcing_invitations
     set invitation_status='RECUSADO', declined_at=now(), decline_reason=p_reason
   where id = p_invitation_id;
  update public.sourcing_suppliers set status='RECUSADO', decline_reason=p_reason
   where round_id = v_inv.sourcing_round_id and supplier_id = v_inv.supplier_id;
end;
$$;

-- ---------- Abertura de envelope fechado (registrada e justificada) ----------
create or replace function app.fn_open_sealed_round(p_round_id uuid, p_reason text)
returns void language plpgsql security definer
set search_path = app, public, pg_temp
as $$
begin
  if not (app.is_purchasing() or app.is_admin()) then
    raise exception 'Sem permissão para abrir propostas' using errcode='42501';
  end if;
  update public.sourcing_rounds
     set opened_at = now(), opened_by = auth.uid(), is_open = false
   where id = p_round_id;
  insert into public.quote_opening_events (round_id, opened_by, reason)
  values (p_round_id, auth.uid(), p_reason);
end;
$$;

-- ---------- RLS: isolamento absoluto entre fornecedores ----------
-- O portal NÃO usa a sessão do usuário interno: tudo passa pelo servidor (service role)
-- após validação de token. Por isso as tabelas do portal são fechadas para 'authenticated'
-- em escrita, e a leitura é limitada à equipe de compras.
alter table public.sourcing_invitations              enable row level security;
alter table public.sourcing_invitation_tokens         enable row level security;
alter table public.supplier_participation_responses   enable row level security;
alter table public.supplier_quote_drafts              enable row level security;
alter table public.supplier_quote_submissions         enable row level security;
alter table public.sourcing_messages                  enable row level security;
alter table public.quote_opening_events               enable row level security;
alter table public.supplier_access_logs               enable row level security;

drop policy if exists sel_invitations on public.sourcing_invitations;
create policy sel_invitations on public.sourcing_invitations for select to authenticated
  using (app.can_read_round(sourcing_round_id));
drop policy if exists wr_invitations on public.sourcing_invitations;
create policy wr_invitations on public.sourcing_invitations for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

-- TOKENS: nenhuma policy. Nem compras lê hash de token pela API. Só funções definer.

drop policy if exists sel_participation on public.supplier_participation_responses;
create policy sel_participation on public.supplier_participation_responses for select to authenticated
  using (exists (select 1 from public.sourcing_invitations i
                 where i.id = invitation_id and app.can_read_round(i.sourcing_round_id)));

drop policy if exists sel_submissions on public.supplier_quote_submissions;
create policy sel_submissions on public.supplier_quote_submissions for select to authenticated
  using (exists (select 1 from public.sourcing_invitations i
                 where i.id = invitation_id and app.can_read_round(i.sourcing_round_id)));

drop policy if exists sel_messages on public.sourcing_messages;
create policy sel_messages on public.sourcing_messages for select to authenticated
  using (app.can_read_round(round_id));
drop policy if exists wr_messages on public.sourcing_messages;
create policy wr_messages on public.sourcing_messages for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

drop policy if exists sel_opening on public.quote_opening_events;
create policy sel_opening on public.quote_opening_events for select to authenticated
  using (app.can_read_round(round_id) or app.is_auditor());

drop policy if exists sel_access_logs on public.supplier_access_logs;
create policy sel_access_logs on public.supplier_access_logs for select to authenticated
  using (app.is_admin() or app.is_auditor()
         or exists (select 1 from public.sourcing_invitations i
                    where i.id = invitation_id and app.can_read_round(i.sourcing_round_id)));

-- Painel de acompanhamento da rodada
create or replace view public.v_round_tracking as
select sr.id as round_id, sr.request_id, sr.round_no, sr.deadline_at, sr.mode,
  count(i.id)                                                        as convidados,
  count(*) filter (where i.invitation_status in ('ENVIADO','ENTREGUE','ACESSADO',
                    'PARTICIPACAO_CONFIRMADA','PROPOSTA_EM_RASCUNHO','RESPONDIDO')) as enviados,
  count(*) filter (where i.first_access_at is not null)               as acessados,
  count(*) filter (where i.invitation_status = 'RESPONDIDO')          as responderam,
  count(*) filter (where i.invitation_status = 'RECUSADO')            as recusaram,
  count(*) filter (where i.invitation_status = 'EXPIRADO')            as expirados,
  count(*) filter (where i.responded_at is null and i.declined_at is null) as sem_resposta
from public.sourcing_rounds sr
left join public.sourcing_invitations i on i.sourcing_round_id = sr.id
group by sr.id, sr.request_id, sr.round_no, sr.deadline_at, sr.mode;

grant execute on function app.fn_open_sealed_round(uuid, text) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['sourcing_invitations','supplier_quote_submissions','quote_opening_events'] loop
    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format('create trigger tg_audit after insert or update or delete on public.%I
                    for each row execute function app.tg_audit()', t);
  end loop;
end $$;


-- ============ 0021_analytics.sql ============
-- 0021 — Esquema estrela (analytics). Views sobre o operacional: sem duplicar dado.
-- Grão declarado em cada fato. Materializar depois é troca de "create view" por
-- "create materialized view" + refresh agendado (ver README).

-- ---------- Dimensões ----------
create or replace view analytics.dim_date as
select d::date                        as date_key,
       extract(year  from d)::int     as ano,
       extract(quarter from d)::int   as trimestre,
       extract(month from d)::int     as mes,
       to_char(d, 'TMMonth')          as mes_nome,
       extract(day from d)::int       as dia,
       extract(isodow from d)::int    as dia_semana,
       (extract(isodow from d) >= 6)  as fim_de_semana
from generate_series(date_trunc('year', now()) - interval '2 years',
                     date_trunc('year', now()) + interval '3 years', '1 day') d;

create or replace view analytics.dim_company as
select id as company_key, name, legal_name, cnpj from public.companies;

create or replace view analytics.dim_business_unit as
select bu.id as business_unit_key, bu.name, bu.code, bu.company_id
from public.business_units bu;

create or replace view analytics.dim_department as
select d.id as department_key, d.name, d.code, d.business_unit_id
from public.departments d;

create or replace view analytics.dim_cost_center as
select cc.id as cost_center_key, cc.name, cc.code, cc.department_id
from public.cost_centers cc;

create or replace view analytics.dim_supplier as
select s.id as supplier_key, s.legal_name, s.trade_name, s.cnpj,
       s.city, s.state, s.status, s.rating
from public.suppliers s;

create or replace view analytics.dim_category as
select c.id as category_key, c.name from public.categories c;

create or replace view analytics.dim_requester as
select p.id as requester_key, p.full_name from public.profiles p;

create or replace view analytics.dim_buyer as
select p.id as buyer_key, p.full_name from public.profiles p;

create or replace view analytics.dim_status as
select unnest(enum_range(null::public.request_status))::text as status_key;

create or replace view analytics.dim_approval_result as
select unnest(enum_range(null::public.approval_decision))::text as approval_result_key;

-- ---------- Fatos ----------
-- Grão: 1 linha por DEMANDA
create or replace view analytics.fact_purchase_request as
select r.id as request_key, r.number, r.company_id as company_key,
       r.business_unit_id as business_unit_key, r.department_id as department_key,
       r.cost_center_id as cost_center_key, r.category_id as category_key,
       r.created_by as requester_key, r.assigned_buyer_id as buyer_key,
       r.status::text as status_key, r.priority::text as prioridade,
       r.purchase_type::text as tipo, r.is_emergency as emergencial,
       r.created_at::date as data_criacao, r.needed_at as data_necessaria,
       r.estimated_total as valor_estimado,
       (select count(*) from public.purchase_request_items i where i.request_id = r.id) as qtd_itens,
       (select count(distinct q.supplier_id) from public.sourcing_rounds sr
         join public.supplier_quotes q on q.round_id = sr.id
        where sr.request_id = r.id) as qtd_propostas,
       -- horas até a primeira cotação (indicador de SLA de compras)
       (select extract(epoch from (min(sr.created_at) - r.created_at))/3600
          from public.sourcing_rounds sr where sr.request_id = r.id) as horas_ate_primeira_cotacao
from public.purchase_requests r;

-- Grão: 1 linha por ITEM SOLICITADO
create or replace view analytics.fact_purchase_request_item as
select i.id as request_item_key, i.request_id as request_key,
       r.department_id as department_key, r.category_id as category_key,
       i.line_no, i.description, i.quantity as quantidade,
       i.unit_price as valor_unitario_estimado, i.total_estimated as valor_total_estimado,
       r.created_at::date as data_criacao
from public.purchase_request_items i
join public.purchase_requests r on r.id = i.request_id;

-- Grão: 1 linha por PROPOSTA (fornecedor × versão)
create or replace view analytics.fact_supplier_quote as
select q.id as quote_key, sr.request_id as request_key, q.supplier_id as supplier_key,
       q.round_id as round_key, q.version_no as versao, q.is_current as vigente,
       q.status, q.items_subtotal as subtotal, q.freight_amount as frete,
       q.taxes_amount as impostos, q.discount_amount as desconto,
       q.total_cost as custo_total, q.delivery_days as prazo_dias,
       q.created_at::date as data_proposta
from public.supplier_quotes q
join public.sourcing_rounds sr on sr.id = q.round_id;

-- Grão: 1 linha por ITEM × FORNECEDOR × VERSÃO DE PROPOSTA
create or replace view analytics.fact_supplier_quote_item as
select qi.id as quote_item_key, qi.quote_id as quote_key,
       qi.request_item_id as request_item_key, q.supplier_id as supplier_key,
       sr.request_id as request_key, q.version_no as versao,
       qi.quantity_offered as quantidade, qi.unit_price as valor_unitario,
       qi.line_total as valor_total, qi.delivery_days as prazo_dias,
       qi.technical_fit as atendimento_tecnico, qi.unavailable as indisponivel
from public.supplier_quote_items qi
join public.supplier_quotes q on q.id = qi.quote_id
join public.sourcing_rounds sr on sr.id = q.round_id;

-- Grão: 1 linha por AÇÃO DE APROVAÇÃO
create or replace view analytics.fact_approval as
select a.id as approval_key, ai.request_id as request_key,
       a.approver_id as approver_key, a.decision::text as approval_result_key,
       a.step_no as etapa, a.amount_at_decision as valor,
       a.created_at::date as data_decisao,
       extract(epoch from (a.created_at - ai.created_at))/3600 as horas_ate_decisao
from public.approval_actions a
join public.approval_instances ai on ai.id = a.instance_id;

-- Grão: 1 linha por PEDIDO
create or replace view analytics.fact_purchase_order as
select o.id as order_key, o.number, o.request_id as request_key,
       o.supplier_id as supplier_key, o.status::text as status,
       o.total_amount as valor_total, o.issued_at::date as data_emissao,
       r.department_id as department_key, r.category_id as category_key
from public.purchase_orders o
join public.purchase_requests r on r.id = o.request_id;

-- Grão: 1 linha por ITEM RECEBIDO
create or replace view analytics.fact_receipt as
select ri.id as receipt_item_key, rc.id as receipt_key, rc.order_id as order_key,
       o.supplier_id as supplier_key, o.request_id as request_key,
       ri.quantity_received as quantidade_recebida, rc.received_at as data_recebimento,
       rc.has_divergence as divergencia, rc.accepted as aceito
from public.receipt_items ri
join public.receipts rc on rc.id = ri.receipt_id
join public.purchase_orders o on o.id = rc.order_id;

-- Leitura para autenticados (as views herdam a RLS das tabelas-base).
grant usage on schema analytics to authenticated;
grant select on all tables in schema analytics to authenticated;


-- ============ 0022_notifications.sql ============
-- 0022 — Notificações automáticas por trigger (não dependem do frontend)

-- Notifica compras quando uma demanda é enviada; notifica o requisitante nas mudanças.
create or replace function app.tg_notify_status_change()
returns trigger language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare
  v_req public.purchase_requests%rowtype;
  v_title text;
begin
  select * into v_req from public.purchase_requests where id = new.request_id;

  -- 1) Demanda enviada → avisa a área de compras
  if new.to_status = 'ENVIADA' then
    insert into public.notifications (user_id, type, title, body, link, priority)
    select ur.user_id, 'NOVA_DEMANDA', 'Nova demanda enviada',
           v_req.number || ' — ' || v_req.title,
           '/demandas/' || v_req.id, v_req.priority
    from public.user_roles ur
    join public.roles ro on ro.id = ur.role_id
    where ro.code in ('COMPRADOR','COORDENADOR_COMPRAS') and ur.is_active;
  end if;

  -- 2) Avisa o autor da demanda nas mudanças relevantes
  if new.to_status in ('AGUARDANDO_INFORMACOES','APROVADA','REJEITADA','PEDIDO_EMITIDO','ENCERRADA')
     and v_req.created_by is not null and v_req.created_by <> auth.uid() then
    v_title := case new.to_status
      when 'AGUARDANDO_INFORMACOES' then 'Compras solicitou informações'
      when 'APROVADA'        then 'Sua demanda foi aprovada'
      when 'REJEITADA'       then 'Sua demanda foi rejeitada'
      when 'PEDIDO_EMITIDO'  then 'Pedido de compra emitido'
      else 'Demanda encerrada' end;
    insert into public.notifications (user_id, type, title, body, link, priority)
    values (v_req.created_by, 'STATUS_DEMANDA', v_title,
            v_req.number || ' — ' || v_req.title, '/demandas/' || v_req.id, v_req.priority);
  end if;

  return new;
end;
$$;
drop trigger if exists tg_notify_status on public.status_history;
create trigger tg_notify_status after insert on public.status_history
  for each row execute function app.tg_notify_status_change();

-- Notifica aprovadores quando um fluxo de aprovação é aberto.
create or replace function app.tg_notify_approval()
returns trigger language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_req public.purchase_requests%rowtype;
begin
  select * into v_req from public.purchase_requests where id = new.request_id;

  -- aprovadores nominais da etapa
  insert into public.notifications (user_id, type, title, body, link, priority)
  select s.approver_user_id, 'APROVACAO_PENDENTE', 'Aprovação pendente',
         v_req.number || ' — ' || v_req.title, '/aprovacoes', v_req.priority
  from public.approval_instance_steps s
  where s.instance_id = new.id and s.approver_user_id is not null;

  -- aprovadores por papel
  insert into public.notifications (user_id, type, title, body, link, priority)
  select ur.user_id, 'APROVACAO_PENDENTE', 'Aprovação pendente',
         v_req.number || ' — ' || v_req.title, '/aprovacoes', v_req.priority
  from public.approval_instance_steps s
  join public.roles ro on ro.code = s.approver_role
  join public.user_roles ur on ur.role_id = ro.id and ur.is_active
  where s.instance_id = new.id and s.approver_role is not null;

  return new;
end;
$$;
drop trigger if exists tg_notify_approval on public.approval_instances;
create trigger tg_notify_approval after insert on public.approval_instances
  for each row execute function app.tg_notify_approval();

-- Marca notificações como lidas
create or replace function app.fn_mark_notifications_read(p_ids uuid[] default null)
returns int language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_count int;
begin
  update public.notifications
     set read_at = now()
   where user_id = auth.uid() and read_at is null
     and (p_ids is null or id = any(p_ids));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
grant execute on function app.fn_mark_notifications_read(uuid[]) to authenticated;


-- ============ 0023_public_rpc_bridge.sql ============
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


-- ============ 0024_business_unit_isolation.sql ============
-- 0024 — Isolamento por unidade de negócio (posto, agropecuária, supermercado)
-- Modelo: usuário pertence a 1+ unidades; só vê dados delas. Papel VE_TODAS_UNIDADES
-- (diretoria/matriz) enxerga tudo. Fornecedor é único, marcado com as unidades que atende.

-- ---------- Papel que enxerga todas as unidades ----------
insert into public.roles (code, name, description) values
  ('VE_TODAS_UNIDADES', 'Visão global (matriz)',
   'Enxerga dados de todas as unidades de negócio')
on conflict (code) do nothing;

-- ---------- Vínculo usuário → unidade(s) ----------
create table if not exists public.user_business_units (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  business_unit_id uuid not null references public.business_units(id) on delete cascade,
  is_primary       boolean not null default false,
  created_at       timestamptz not null default now(),
  constraint user_business_units_uk unique (user_id, business_unit_id)
);
create index if not exists ix_ubu_user on public.user_business_units(user_id);
create index if not exists ix_ubu_bu on public.user_business_units(business_unit_id);

-- ---------- Fornecedor → unidades que atende (híbrido) ----------
create table if not exists public.supplier_business_units (
  supplier_id      uuid not null references public.suppliers(id) on delete cascade,
  business_unit_id uuid not null references public.business_units(id) on delete cascade,
  primary key (supplier_id, business_unit_id)
);
create index if not exists ix_sbu_bu on public.supplier_business_units(business_unit_id);

-- ---------- Helpers ----------
-- Vê todas as unidades? (papel global ou admin)
create or replace function app.sees_all_units()
returns boolean language sql stable security definer
set search_path = app, public, pg_temp
as $$ select app.is_admin() or app.has_role('VE_TODAS_UNIDADES'); $$;

-- Unidades do usuário atual
create or replace function app.user_units()
returns setof uuid language sql stable security definer
set search_path = app, public, pg_temp
as $$ select business_unit_id from public.user_business_units where user_id = auth.uid(); $$;

-- Pode acessar esta unidade?
create or replace function app.in_business_unit(p_bu uuid)
returns boolean language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select app.sees_all_units()
      or exists (select 1 from public.user_business_units
                 where user_id = auth.uid() and business_unit_id = p_bu);
$$;

grant execute on function app.sees_all_units() to authenticated;
grant execute on function app.user_units() to authenticated;
grant execute on function app.in_business_unit(uuid) to authenticated;

-- ---------- Atualizar can_read_request: soma a checagem de unidade ----------
-- Regra final de leitura de demanda:
--   vê tudo (matriz)  OU  é dono/comprador  OU  (pertence à unidade da demanda)
create or replace function app.can_read_request(p_request_id uuid)
returns boolean language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select exists (
    select 1 from public.purchase_requests r
    where r.id = p_request_id
      and (
        app.sees_all_units()
        or r.created_by = auth.uid()
        or r.assigned_buyer_id = auth.uid()
        or (
          -- membro da unidade da demanda (ou, se a demanda não tem unidade, do setor)
          (r.business_unit_id is not null and app.in_business_unit(r.business_unit_id))
          or (r.business_unit_id is null and app.in_department(r.department_id))
        )
        or (app.is_purchasing() and (
              r.business_unit_id is null or app.in_business_unit(r.business_unit_id)))
      )
  );
$$;

-- ---------- RLS: demandas respeitam unidade ----------
drop policy if exists sel_requests on public.purchase_requests;
create policy sel_requests on public.purchase_requests for select to authenticated
  using (
    app.sees_all_units()
    or created_by = auth.uid()
    or assigned_buyer_id = auth.uid()
    or (business_unit_id is not null and app.in_business_unit(business_unit_id))
    or (business_unit_id is null and app.in_department(department_id))
    or (app.is_purchasing() and (business_unit_id is null or app.in_business_unit(business_unit_id)))
  );

-- Criar demanda: requisitante só na sua unidade (quando informada)
drop policy if exists ins_requests on public.purchase_requests;
create policy ins_requests on public.purchase_requests for insert to authenticated
  with check (
    created_by = auth.uid()
    and (app.is_admin() or app.has_role('REQUISITANTE'))
    and (business_unit_id is null or app.in_business_unit(business_unit_id))
    and (app.in_department(department_id) or app.is_admin())
  );

-- ---------- RLS: fornecedores respeitam unidade (híbrido) ----------
-- Vê o fornecedor quem: vê tudo, OU compras, OU o fornecedor atende alguma unidade sua,
-- OU o fornecedor ainda não foi marcado com nenhuma unidade (recém-cadastrado).
drop policy if exists sel_suppliers on public.suppliers;
create policy sel_suppliers on public.suppliers for select to authenticated
  using (
    (deleted_at is null or app.is_admin() or app.is_auditor())
    and (
      app.sees_all_units()
      or app.is_purchasing()
      or app.is_auditor()
      or not exists (select 1 from public.supplier_business_units sbu where sbu.supplier_id = id)
      or exists (
        select 1 from public.supplier_business_units sbu
        where sbu.supplier_id = id and app.in_business_unit(sbu.business_unit_id))
    )
  );

-- Marcação fornecedor↔unidade: leitura conforme fornecedor; escrita compras/admin.
alter table public.user_business_units     enable row level security;
alter table public.supplier_business_units enable row level security;

drop policy if exists sel_ubu on public.user_business_units;
create policy sel_ubu on public.user_business_units for select to authenticated
  using (user_id = auth.uid() or app.is_admin() or app.is_auditor());
drop policy if exists wr_ubu on public.user_business_units;
create policy wr_ubu on public.user_business_units for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

drop policy if exists sel_sbu on public.supplier_business_units;
create policy sel_sbu on public.supplier_business_units for select to authenticated
  using (true);
drop policy if exists wr_sbu on public.supplier_business_units;
create policy wr_sbu on public.supplier_business_units for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

-- auditoria
do $$
declare t text;
begin
  foreach t in array array['user_business_units','supplier_business_units'] loop
    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format('create trigger tg_audit after insert or update or delete on public.%I
                    for each row execute function app.tg_audit()', t);
  end loop;
end $$;
