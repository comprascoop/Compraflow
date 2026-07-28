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
