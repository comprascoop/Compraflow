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
