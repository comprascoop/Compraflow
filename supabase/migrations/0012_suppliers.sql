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
