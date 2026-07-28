-- 0014 — RLS das tabelas de fornecedor + RPC de homologação

alter table public.supplier_contacts       enable row level security;
alter table public.supplier_categories      enable row level security;
alter table public.supplier_documents       enable row level security;
alter table public.supplier_evaluations     enable row level security;
alter table public.supplier_bank_accounts   enable row level security;

-- Contatos e categorias: leitura para autenticados; escrita compras/admin.
do $$
declare t text;
begin
  foreach t in array array['supplier_contacts','supplier_categories','supplier_documents'] loop
    execute format('drop policy if exists sel_%1$s on public.%1$s', t);
    execute format('drop policy if exists wr_%1$s on public.%1$s', t);
  end loop;
end $$;

create policy sel_supplier_contacts on public.supplier_contacts for select to authenticated
  using (deleted_at is null or app.is_admin());
create policy wr_supplier_contacts on public.supplier_contacts for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

create policy sel_supplier_categories on public.supplier_categories for select to authenticated
  using (true);
create policy wr_supplier_categories on public.supplier_categories for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

create policy sel_supplier_documents on public.supplier_documents for select to authenticated
  using (deleted_at is null or app.is_admin() or app.is_auditor());
create policy wr_supplier_documents on public.supplier_documents for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

-- Avaliações: internas — só compras/admin/auditor leem; compras/admin escrevem.
drop policy if exists sel_supplier_evaluations on public.supplier_evaluations;
create policy sel_supplier_evaluations on public.supplier_evaluations for select to authenticated
  using (app.is_purchasing() or app.is_admin() or app.is_auditor());
drop policy if exists wr_supplier_evaluations on public.supplier_evaluations;
create policy wr_supplier_evaluations on public.supplier_evaluations for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

-- Dados bancários: SENSÍVEL — só ADMIN e COORDENADOR de compras.
drop policy if exists sel_supplier_bank on public.supplier_bank_accounts;
create policy sel_supplier_bank on public.supplier_bank_accounts for select to authenticated
  using (app.is_admin() or app.has_role('COORDENADOR_COMPRAS'));
drop policy if exists wr_supplier_bank on public.supplier_bank_accounts;
create policy wr_supplier_bank on public.supplier_bank_accounts for all to authenticated
  using (app.is_admin() or app.has_role('COORDENADOR_COMPRAS'))
  with check (app.is_admin() or app.has_role('COORDENADOR_COMPRAS'));

-- ---------- RPC de homologação / mudança de status do fornecedor ----------
-- Só ADMIN ou COORDENADOR_COMPRAS. Registra motivo em audit_logs com contexto.
create or replace function app.fn_set_supplier_status(
  p_supplier_id uuid,
  p_status      public.supplier_status,
  p_reason      text default null,
  p_valid_until date default null
)
returns public.supplier_status
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare v_old public.supplier_status;
begin
  if not (app.is_admin() or app.has_role('COORDENADOR_COMPRAS')) then
    raise exception 'Sem permissão para homologar fornecedores' using errcode = '42501';
  end if;

  if p_status in ('HOMOLOGADO','HOMOLOGADO_COM_RESTRICAO','BLOQUEADO')
     and (p_reason is null or length(trim(p_reason)) = 0) then
    raise exception 'Justificativa obrigatória para % ', p_status using errcode = 'P0001';
  end if;

  select status into v_old from public.suppliers where id = p_supplier_id for update;
  if not found then
    raise exception 'Fornecedor não encontrado' using errcode = 'P0002';
  end if;

  update public.suppliers
     set status = p_status,
         homologation_valid_until = coalesce(p_valid_until, homologation_valid_until),
         updated_by = auth.uid()
   where id = p_supplier_id;

  insert into public.audit_logs(actor_id, entity, entity_id, action, old_values, new_values, context)
  values (auth.uid(), 'suppliers', p_supplier_id, 'STATUS_FORNECEDOR',
          jsonb_build_object('status', v_old),
          jsonb_build_object('status', p_status),
          jsonb_build_object('reason', p_reason, 'valid_until', p_valid_until));

  return p_status;
end;
$$;

grant execute on function app.fn_set_supplier_status(uuid, public.supplier_status, text, date) to authenticated;
grant execute on function app.is_valid_cnpj(text) to authenticated;
