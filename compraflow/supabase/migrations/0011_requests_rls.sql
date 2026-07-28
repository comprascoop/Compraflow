-- 0011 — RLS das demandas, itens, histórico e transições

alter table public.purchase_requests           enable row level security;
alter table public.purchase_request_items       enable row level security;
alter table public.status_history               enable row level security;
alter table public.request_status_transitions   enable row level security;
alter table public.number_sequences             enable row level security;

-- ---------- purchase_requests ----------
-- Leitura: dono, comprador atribuído, membros do setor, área de compras, admin, auditor.
drop policy if exists sel_requests on public.purchase_requests;
create policy sel_requests on public.purchase_requests for select to authenticated
  using (
    created_by = auth.uid()
    or assigned_buyer_id = auth.uid()
    or app.in_department(department_id)
    or app.is_purchasing()
    or app.is_admin()
    or app.is_auditor()
  );

-- Criação: requisitante (ou admin), sempre em nome próprio e num setor a que pertence.
drop policy if exists ins_requests on public.purchase_requests;
create policy ins_requests on public.purchase_requests for insert to authenticated
  with check (
    created_by = auth.uid()
    and (app.is_admin() or (app.has_role('REQUISITANTE') and app.in_department(department_id)))
  );

-- Edição de campos: só o dono enquanto RASCUNHO, ou compras/admin.
-- (Mudança de STATUS não passa por aqui — é via RPC definer.)
drop policy if exists upd_requests on public.purchase_requests;
create policy upd_requests on public.purchase_requests for update to authenticated
  using (
    (created_by = auth.uid() and status = 'RASCUNHO')
    or app.is_purchasing()
    or app.is_admin()
  )
  with check (
    (created_by = auth.uid() and status = 'RASCUNHO')
    or app.is_purchasing()
    or app.is_admin()
  );
-- Sem policy de DELETE => demanda nunca é excluída fisicamente.

-- ---------- purchase_request_items ----------
drop policy if exists sel_request_items on public.purchase_request_items;
create policy sel_request_items on public.purchase_request_items for select to authenticated
  using (app.can_read_request(request_id));

-- Inserir/editar/remover itens só enquanto a demanda-mãe é RASCUNHO e do próprio dono (ou compras/admin).
drop policy if exists wr_request_items on public.purchase_request_items;
create policy wr_request_items on public.purchase_request_items for all to authenticated
  using (
    exists (select 1 from public.purchase_requests r
            where r.id = request_id
              and ((r.created_by = auth.uid() and r.status = 'RASCUNHO')
                   or app.is_purchasing() or app.is_admin()))
  )
  with check (
    exists (select 1 from public.purchase_requests r
            where r.id = request_id
              and ((r.created_by = auth.uid() and r.status = 'RASCUNHO')
                   or app.is_purchasing() or app.is_admin()))
  );

-- ---------- status_history ----------
-- Leitura conforme acesso à demanda; escrita SÓ via RPC definer (sem policy de insert).
drop policy if exists sel_status_history on public.status_history;
create policy sel_status_history on public.status_history for select to authenticated
  using (app.can_read_request(request_id));

-- ---------- request_status_transitions ----------
-- Catálogo somente leitura (UI precisa saber ações disponíveis); escrita só ADMIN.
drop policy if exists sel_transitions on public.request_status_transitions;
create policy sel_transitions on public.request_status_transitions for select to authenticated
  using (true);
drop policy if exists wr_transitions on public.request_status_transitions;
create policy wr_transitions on public.request_status_transitions for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- ---------- number_sequences ----------
-- Sem policies de leitura/escrita p/ usuários. Só funções definer tocam nela.
