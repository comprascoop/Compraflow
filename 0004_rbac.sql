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
