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
