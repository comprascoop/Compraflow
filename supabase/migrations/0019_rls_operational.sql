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
