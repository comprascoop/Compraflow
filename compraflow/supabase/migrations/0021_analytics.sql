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
