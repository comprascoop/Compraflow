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
