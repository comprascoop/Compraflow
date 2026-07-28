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
