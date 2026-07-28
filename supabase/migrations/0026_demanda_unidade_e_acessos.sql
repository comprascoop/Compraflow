-- 0026 — Demanda passa a ser vinculada à UNIDADE DE NEGÓCIO (não mais ao setor).
--        + catálogo de papéis legível (usado no cadastro de acessos).

-- Setor deixa de ser obrigatório: a unidade de negócio é o escopo da demanda.
alter table public.purchase_requests alter column department_id drop not null;

-- Criar demanda: requisitante (ou admin), na sua unidade. Setor vira opcional.
drop policy if exists ins_requests on public.purchase_requests;
create policy ins_requests on public.purchase_requests for insert to authenticated
  with check (
    created_by = auth.uid()
    and (app.is_admin() or app.has_role('REQUISITANTE'))
    and (business_unit_id is null or app.in_business_unit(business_unit_id))
    and (department_id is null or app.in_department(department_id) or app.is_admin())
  );

-- Catálogo de papéis (roles): leitura por qualquer autenticado.
-- Necessário para montar as opções de acesso na tela de Administração.
-- (Escrita continua bloqueada — papéis são de sistema.)
drop policy if exists sel_roles on public.roles;
create policy sel_roles on public.roles for select to authenticated using (true);
