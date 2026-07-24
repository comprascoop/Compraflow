-- 0017 — Matriz de aprovação configurável + instâncias + decisões imutáveis

create table if not exists public.approval_rules (
  id             uuid primary key default gen_random_uuid(),
  name           text not null,
  company_id     uuid references public.companies(id),
  business_unit_id uuid references public.business_units(id),
  department_id  uuid references public.departments(id),
  cost_center_id uuid references public.cost_centers(id),
  category_id    uuid references public.categories(id),
  purchase_type  public.purchase_type,
  is_emergency   boolean,
  min_amount     numeric(18,2) not null default 0,
  max_amount     numeric(18,2),                  -- null = sem teto
  currency       char(3) not null default 'BRL',
  priority_order int not null default 100,        -- menor = avaliada antes
  is_active      boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  constraint approval_rules_amount_ck check (max_amount is null or max_amount >= min_amount)
);

create table if not exists public.approval_rule_steps (
  id             uuid primary key default gen_random_uuid(),
  rule_id        uuid not null references public.approval_rules(id) on delete cascade,
  step_no        int not null,
  mode           text not null default 'SEQUENCIAL' check (mode in ('SEQUENCIAL','PARALELA')),
  approver_user_id uuid references auth.users(id),
  approver_role  text,                            -- código do papel
  use_dept_manager boolean not null default false,
  min_approvals  int not null default 1 check (min_approvals >= 1),
  unanimous      boolean not null default false,
  deadline_hours int,
  created_at     timestamptz not null default now(),
  constraint rule_steps_uk unique (rule_id, step_no),
  -- a etapa precisa apontar para alguém
  constraint rule_steps_target_ck check (
    approver_user_id is not null or approver_role is not null or use_dept_manager
  )
);

-- Instância = execução da matriz para uma recomendação específica.
create table if not exists public.approval_instances (
  id                uuid primary key default gen_random_uuid(),
  request_id        uuid not null references public.purchase_requests(id),
  recommendation_id uuid not null references public.recommendations(id),
  rule_id           uuid references public.approval_rules(id),
  amount            numeric(18,2) not null,
  status            text not null default 'EM_ANDAMENTO'
                    check (status in ('EM_ANDAMENTO','APROVADA','REJEITADA','CANCELADA')),
  current_step      int not null default 1,
  created_at        timestamptz not null default now(),
  closed_at         timestamptz
);
create index if not exists ix_approval_inst_request on public.approval_instances(request_id);

create table if not exists public.approval_instance_steps (
  id            uuid primary key default gen_random_uuid(),
  instance_id   uuid not null references public.approval_instances(id) on delete cascade,
  step_no       int not null,
  mode          text not null default 'SEQUENCIAL',
  approver_user_id uuid references auth.users(id),
  approver_role text,
  min_approvals int not null default 1,
  status        text not null default 'PENDENTE'
                check (status in ('PENDENTE','APROVADA','REJEITADA','PULADA')),
  deadline_at   timestamptz,
  created_at    timestamptz not null default now(),
  constraint inst_steps_uk unique (instance_id, step_no)
);

-- Decisões: append-only. Sem UPDATE/DELETE (garantido por RLS na 0019).
create table if not exists public.approval_actions (
  id              uuid primary key default gen_random_uuid(),
  instance_id     uuid not null references public.approval_instances(id),
  step_no         int not null,
  approver_id     uuid not null references auth.users(id),
  decision        public.approval_decision not null,
  comment         text,
  ip_address      inet,
  user_agent      text,
  recommendation_version int,
  amount_at_decision numeric(18,2),
  quote_snapshot  jsonb,
  created_at      timestamptz not null default now()
);
create index if not exists ix_approval_actions_inst on public.approval_actions(instance_id);

-- ---------- Seleção da regra aplicável ----------
create or replace function app.fn_find_approval_rule(p_request_id uuid, p_amount numeric)
returns uuid
language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select ar.id
  from public.approval_rules ar
  join public.purchase_requests r on r.id = p_request_id
  where ar.is_active
    and (ar.company_id       is null or ar.company_id = r.company_id)
    and (ar.business_unit_id is null or ar.business_unit_id = r.business_unit_id)
    and (ar.department_id    is null or ar.department_id = r.department_id)
    and (ar.cost_center_id   is null or ar.cost_center_id = r.cost_center_id)
    and (ar.category_id      is null or ar.category_id = r.category_id)
    and (ar.purchase_type    is null or ar.purchase_type = r.purchase_type)
    and (ar.is_emergency     is null or ar.is_emergency = r.is_emergency)
    and p_amount >= ar.min_amount
    and (ar.max_amount is null or p_amount <= ar.max_amount)
  order by ar.priority_order, ar.min_amount desc
  limit 1;
$$;

-- ---------- Abrir fluxo de aprovação a partir da recomendação ----------
create or replace function app.fn_start_approval(p_recommendation_id uuid)
returns uuid
language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare
  v_rec  public.recommendations%rowtype;
  v_rule uuid;
  v_inst uuid;
  s      record;
begin
  if not (app.is_purchasing() or app.is_admin()) then
    raise exception 'Apenas compras pode enviar para aprovação' using errcode = '42501';
  end if;

  select * into v_rec from public.recommendations where id = p_recommendation_id;
  if not found then raise exception 'Recomendação não encontrada' using errcode='P0002'; end if;

  v_rule := app.fn_find_approval_rule(v_rec.request_id, v_rec.total_amount);
  if v_rule is null then
    raise exception 'Nenhuma regra de aprovação aplicável para o valor %', v_rec.total_amount
      using errcode = 'P0001';
  end if;

  insert into public.approval_instances (request_id, recommendation_id, rule_id, amount)
  values (v_rec.request_id, p_recommendation_id, v_rule, v_rec.total_amount)
  returning id into v_inst;

  for s in select * from public.approval_rule_steps where rule_id = v_rule order by step_no loop
    insert into public.approval_instance_steps
      (instance_id, step_no, mode, approver_user_id, approver_role, min_approvals, deadline_at)
    values (v_inst, s.step_no, s.mode, s.approver_user_id, s.approver_role, s.min_approvals,
            case when s.deadline_hours is not null then now() + (s.deadline_hours || ' hours')::interval end);
  end loop;

  perform app.fn_transition_request(v_rec.request_id, 'AGUARDANDO_APROVACAO_FINANCEIRA', 'Enviada para aprovação');
  return v_inst;
end;
$$;

-- ---------- Registrar decisão ----------
create or replace function app.fn_decide_approval(
  p_instance_id uuid,
  p_decision    public.approval_decision,
  p_comment     text default null
)
returns text
language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare
  v_inst public.approval_instances%rowtype;
  v_step public.approval_instance_steps%rowtype;
  v_rec  public.recommendations%rowtype;
  v_authorized boolean := false;
  v_approvals int;
  v_next int;
begin
  select * into v_inst from public.approval_instances where id = p_instance_id for update;
  if not found then raise exception 'Instância não encontrada' using errcode='P0002'; end if;
  if v_inst.status <> 'EM_ANDAMENTO' then
    raise exception 'Este fluxo já foi encerrado' using errcode='P0001';
  end if;

  select * into v_step from public.approval_instance_steps
   where instance_id = p_instance_id and step_no = v_inst.current_step;

  -- autorização: usuário nominal, papel, ou admin
  if v_step.approver_user_id is not null and v_step.approver_user_id = auth.uid() then
    v_authorized := true;
  elsif v_step.approver_role is not null and app.has_role(v_step.approver_role) then
    v_authorized := true;
  elsif app.is_admin() then
    v_authorized := true;
  end if;
  if not v_authorized then
    raise exception 'Você não é aprovador desta etapa' using errcode='42501';
  end if;

  if p_decision in ('REJEITADO','AJUSTE_SOLICITADO')
     and (p_comment is null or length(trim(p_comment)) = 0) then
    raise exception 'Comentário obrigatório para rejeitar ou solicitar ajustes' using errcode='P0001';
  end if;

  select * into v_rec from public.recommendations where id = v_inst.recommendation_id;

  insert into public.approval_actions
    (instance_id, step_no, approver_id, decision, comment, recommendation_version, amount_at_decision)
  values (p_instance_id, v_inst.current_step, auth.uid(), p_decision, p_comment,
          v_rec.version_no, v_inst.amount);

  if p_decision = 'REJEITADO' then
    update public.approval_instances set status='REJEITADA', closed_at=now() where id=p_instance_id;
    update public.approval_instance_steps set status='REJEITADA'
      where instance_id=p_instance_id and step_no=v_inst.current_step;
    perform app.fn_transition_request(v_inst.request_id, 'REJEITADA', coalesce(p_comment,'Rejeitada na aprovação'));
    return 'REJEITADA';

  elsif p_decision = 'AJUSTE_SOLICITADO' then
    update public.approval_instances set status='CANCELADA', closed_at=now() where id=p_instance_id;
    perform app.fn_transition_request(v_inst.request_id, 'EM_ANALISE_DE_COTACOES', coalesce(p_comment,'Ajustes solicitados'));
    return 'AJUSTE_SOLICITADO';

  elsif p_decision = 'APROVADO' then
    select count(*) into v_approvals from public.approval_actions
     where instance_id=p_instance_id and step_no=v_inst.current_step and decision='APROVADO';

    if v_approvals >= v_step.min_approvals then
      update public.approval_instance_steps set status='APROVADA'
        where instance_id=p_instance_id and step_no=v_inst.current_step;

      select min(step_no) into v_next from public.approval_instance_steps
       where instance_id=p_instance_id and status='PENDENTE';

      if v_next is null then
        update public.approval_instances set status='APROVADA', closed_at=now() where id=p_instance_id;
        perform app.fn_transition_request(v_inst.request_id, 'APROVADA', 'Aprovação concluída');
        return 'APROVADA';
      else
        update public.approval_instances set current_step=v_next where id=p_instance_id;
        return 'PROXIMA_ETAPA';
      end if;
    end if;
    return 'AGUARDANDO_DEMAIS_APROVADORES';
  end if;

  return 'REGISTRADO';
end;
$$;

-- ---------- Invalidação: alterar cotação após início da aprovação derruba as aprovações ----------
create or replace function app.tg_invalidate_approvals()
returns trigger language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_request uuid; v_inst uuid;
begin
  select sr.request_id into v_request
    from public.sourcing_rounds sr where sr.id = new.round_id;

  select ai.id into v_inst from public.approval_instances ai
   where ai.request_id = v_request and ai.status = 'EM_ANDAMENTO' limit 1;

  if v_inst is not null then
    update public.approval_instances set status='CANCELADA', closed_at=now() where id=v_inst;
    insert into public.audit_logs(actor_id, entity, entity_id, action, context)
    values (auth.uid(), 'approval_instances', v_inst, 'APROVACOES_INVALIDADAS',
            jsonb_build_object('motivo','Proposta alterada após início da aprovação',
                               'quote_id', new.id));
  end if;
  return new;
end;
$$;
drop trigger if exists tg_invalidate_approvals on public.supplier_quotes;
create trigger tg_invalidate_approvals after update of total_cost, supplier_id, status
  on public.supplier_quotes
  for each row execute function app.tg_invalidate_approvals();

grant execute on function app.fn_find_approval_rule(uuid, numeric) to authenticated;
grant execute on function app.fn_start_approval(uuid) to authenticated;
grant execute on function app.fn_decide_approval(uuid, public.approval_decision, text) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['approval_rules','approval_rule_steps','approval_instances','approval_actions'] loop
    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format('create trigger tg_audit after insert or update or delete on public.%I
                    for each row execute function app.tg_audit()', t);
  end loop;
end $$;
