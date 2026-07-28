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
