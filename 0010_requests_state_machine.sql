-- 0024 — Isolamento por unidade de negócio (posto, agropecuária, supermercado)
-- Modelo: usuário pertence a 1+ unidades; só vê dados delas. Papel VE_TODAS_UNIDADES
-- (diretoria/matriz) enxerga tudo. Fornecedor é único, marcado com as unidades que atende.

-- ---------- Papel que enxerga todas as unidades ----------
insert into public.roles (code, name, description) values
  ('VE_TODAS_UNIDADES', 'Visão global (matriz)',
   'Enxerga dados de todas as unidades de negócio')
on conflict (code) do nothing;

-- ---------- Vínculo usuário → unidade(s) ----------
create table if not exists public.user_business_units (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  business_unit_id uuid not null references public.business_units(id) on delete cascade,
  is_primary       boolean not null default false,
  created_at       timestamptz not null default now(),
  constraint user_business_units_uk unique (user_id, business_unit_id)
);
create index if not exists ix_ubu_user on public.user_business_units(user_id);
create index if not exists ix_ubu_bu on public.user_business_units(business_unit_id);

-- ---------- Fornecedor → unidades que atende (híbrido) ----------
create table if not exists public.supplier_business_units (
  supplier_id      uuid not null references public.suppliers(id) on delete cascade,
  business_unit_id uuid not null references public.business_units(id) on delete cascade,
  primary key (supplier_id, business_unit_id)
);
create index if not exists ix_sbu_bu on public.supplier_business_units(business_unit_id);

-- ---------- Helpers ----------
-- Vê todas as unidades? (papel global ou admin)
create or replace function app.sees_all_units()
returns boolean language sql stable security definer
set search_path = app, public, pg_temp
as $$ select app.is_admin() or app.has_role('VE_TODAS_UNIDADES'); $$;

-- Unidades do usuário atual
create or replace function app.user_units()
returns setof uuid language sql stable security definer
set search_path = app, public, pg_temp
as $$ select business_unit_id from public.user_business_units where user_id = auth.uid(); $$;

-- Pode acessar esta unidade?
create or replace function app.in_business_unit(p_bu uuid)
returns boolean language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select app.sees_all_units()
      or exists (select 1 from public.user_business_units
                 where user_id = auth.uid() and business_unit_id = p_bu);
$$;

grant execute on function app.sees_all_units() to authenticated;
grant execute on function app.user_units() to authenticated;
grant execute on function app.in_business_unit(uuid) to authenticated;

-- ---------- Atualizar can_read_request: soma a checagem de unidade ----------
-- Regra final de leitura de demanda:
--   vê tudo (matriz)  OU  é dono/comprador  OU  (pertence à unidade da demanda)
create or replace function app.can_read_request(p_request_id uuid)
returns boolean language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select exists (
    select 1 from public.purchase_requests r
    where r.id = p_request_id
      and (
        app.sees_all_units()
        or r.created_by = auth.uid()
        or r.assigned_buyer_id = auth.uid()
        or (
          -- membro da unidade da demanda (ou, se a demanda não tem unidade, do setor)
          (r.business_unit_id is not null and app.in_business_unit(r.business_unit_id))
          or (r.business_unit_id is null and app.in_department(r.department_id))
        )
        or (app.is_purchasing() and (
              r.business_unit_id is null or app.in_business_unit(r.business_unit_id)))
      )
  );
$$;

-- ---------- RLS: demandas respeitam unidade ----------
drop policy if exists sel_requests on public.purchase_requests;
create policy sel_requests on public.purchase_requests for select to authenticated
  using (
    app.sees_all_units()
    or created_by = auth.uid()
    or assigned_buyer_id = auth.uid()
    or (business_unit_id is not null and app.in_business_unit(business_unit_id))
    or (business_unit_id is null and app.in_department(department_id))
    or (app.is_purchasing() and (business_unit_id is null or app.in_business_unit(business_unit_id)))
  );

-- Criar demanda: requisitante só na sua unidade (quando informada)
drop policy if exists ins_requests on public.purchase_requests;
create policy ins_requests on public.purchase_requests for insert to authenticated
  with check (
    created_by = auth.uid()
    and (app.is_admin() or app.has_role('REQUISITANTE'))
    and (business_unit_id is null or app.in_business_unit(business_unit_id))
    and (app.in_department(department_id) or app.is_admin())
  );

-- ---------- RLS: fornecedores respeitam unidade (híbrido) ----------
-- Vê o fornecedor quem: vê tudo, OU compras, OU o fornecedor atende alguma unidade sua,
-- OU o fornecedor ainda não foi marcado com nenhuma unidade (recém-cadastrado).
drop policy if exists sel_suppliers on public.suppliers;
create policy sel_suppliers on public.suppliers for select to authenticated
  using (
    (deleted_at is null or app.is_admin() or app.is_auditor())
    and (
      app.sees_all_units()
      or app.is_purchasing()
      or app.is_auditor()
      or not exists (select 1 from public.supplier_business_units sbu where sbu.supplier_id = id)
      or exists (
        select 1 from public.supplier_business_units sbu
        where sbu.supplier_id = id and app.in_business_unit(sbu.business_unit_id))
    )
  );

-- Marcação fornecedor↔unidade: leitura conforme fornecedor; escrita compras/admin.
alter table public.user_business_units     enable row level security;
alter table public.supplier_business_units enable row level security;

drop policy if exists sel_ubu on public.user_business_units;
create policy sel_ubu on public.user_business_units for select to authenticated
  using (user_id = auth.uid() or app.is_admin() or app.is_auditor());
drop policy if exists wr_ubu on public.user_business_units;
create policy wr_ubu on public.user_business_units for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

drop policy if exists sel_sbu on public.supplier_business_units;
create policy sel_sbu on public.supplier_business_units for select to authenticated
  using (true);
drop policy if exists wr_sbu on public.supplier_business_units;
create policy wr_sbu on public.supplier_business_units for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

-- auditoria
do $$
declare t text;
begin
  foreach t in array array['user_business_units','supplier_business_units'] loop
    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format('create trigger tg_audit after insert or update or delete on public.%I
                    for each row execute function app.tg_audit()', t);
  end loop;
end $$;
