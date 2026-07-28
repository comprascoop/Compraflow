-- 0010 — Máquina de estados da demanda (tabela de transições + RPC)
-- O front NUNCA faz "update status". Só chama app.fn_transition_request().

-- ---------- Transições permitidas ----------
-- required_role: papel exigido (NULL = não exige papel específico)
-- allow_owner: o criador da demanda pode disparar
-- allow_dept_manager: o gestor (is_manager) do setor da demanda pode disparar
-- requires_items: exige título/centro de custo e ao menos 1 item
-- Coordenador de compras recebe TAMBÉM o papel COMPRADOR no cadastro do usuário
-- (spec: "coordenador possui as permissões do comprador"), por isso COMPRADOR cobre ambos.
create table if not exists public.request_status_transitions (
  from_status        public.request_status not null,
  to_status          public.request_status not null,
  required_role      text,
  allow_owner        boolean not null default false,
  allow_dept_manager boolean not null default false,
  requires_items     boolean not null default false,
  requires_comment   boolean not null default false,
  description        text,
  primary key (from_status, to_status)
);

insert into public.request_status_transitions
  (from_status, to_status, required_role, allow_owner, allow_dept_manager, requires_items, requires_comment, description)
values
  ('RASCUNHO','ENVIADA',                       null, true,  false, true,  false, 'Requisitante envia a demanda'),
  ('RASCUNHO','CANCELADA',                     null, true,  false, false, true,  'Cancelar rascunho'),
  ('ENVIADA','AGUARDANDO_APROVACAO_DO_SETOR',  null, false, true,  false, false, 'Rota com aprovação de setor habilitada'),
  ('ENVIADA','EM_ANALISE_POR_COMPRAS',        'COMPRADOR', false, false, false, false, 'Compras assume (sem etapa de setor)'),
  ('ENVIADA','CANCELADA',                      null, true,  false, false, true,  'Cancelar antes da cotação'),
  ('AGUARDANDO_APROVACAO_DO_SETOR','EM_ANALISE_POR_COMPRAS', null, false, true, false, false, 'Gestor aprova → compras'),
  ('AGUARDANDO_APROVACAO_DO_SETOR','RASCUNHO', null, false, true,  false, true,  'Gestor devolve p/ ajuste'),
  ('AGUARDANDO_APROVACAO_DO_SETOR','REJEITADA',null, false, true,  false, true,  'Gestor rejeita'),
  ('EM_ANALISE_POR_COMPRAS','AGUARDANDO_INFORMACOES','COMPRADOR', false, false, false, true, 'Comprador pede complemento'),
  ('EM_ANALISE_POR_COMPRAS','EM_COTACAO',      'COMPRADOR', false, false, false, false, 'Abrir cotação'),
  ('AGUARDANDO_INFORMACOES','EM_ANALISE_POR_COMPRAS', null, true, false, false, false, 'Requisitante responde'),
  ('EM_COTACAO','COTACOES_RECEBIDAS',          'COMPRADOR', false, false, false, false, 'Encerrar recebimento de propostas'),
  ('COTACOES_RECEBIDAS','EM_ANALISE_DE_COTACOES','COMPRADOR', false, false, false, false, 'Analisar cotações'),
  ('EM_ANALISE_DE_COTACOES','AGUARDANDO_APROVACAO_FINANCEIRA','COMPRADOR', false, false, false, false, 'Enviar p/ aprovação'),
  ('AGUARDANDO_APROVACAO_FINANCEIRA','APROVADA','APROVADOR_FINANCEIRO', false, false, false, false, 'Diretor aprova'),
  ('AGUARDANDO_APROVACAO_FINANCEIRA','REJEITADA','APROVADOR_FINANCEIRO', false, false, false, true,  'Diretor rejeita'),
  ('AGUARDANDO_APROVACAO_FINANCEIRA','EM_ANALISE_DE_COTACOES','APROVADOR_FINANCEIRO', false, false, false, true, 'Diretor solicita ajuste'),
  ('APROVADA','PEDIDO_EMITIDO',                'COMPRADOR', false, false, false, false, 'Gerar pedido'),
  ('PEDIDO_EMITIDO','EM_ENTREGA',              'COMPRADOR', false, false, false, false, 'Pedido enviado ao fornecedor'),
  ('EM_ENTREGA','RECEBIDA',                    'COMPRADOR', true,  false, false, false, 'Confirmar recebimento'),
  ('RECEBIDA','ENCERRADA',                     'COMPRADOR', false, false, false, false, 'Encerrar demanda')
on conflict (from_status, to_status) do nothing;

-- ---------- Helpers de acesso à demanda (usados pela RLS de itens/histórico) ----------
create or replace function app.can_read_request(p_request_id uuid)
returns boolean
language sql stable security definer
set search_path = app, public, pg_temp
as $$
  select exists (
    select 1 from public.purchase_requests r
    where r.id = p_request_id
      and (
        r.created_by = auth.uid()
        or r.assigned_buyer_id = auth.uid()
        or app.in_department(r.department_id)
        or app.is_purchasing()
        or app.is_admin()
        or app.is_auditor()
      )
  );
$$;

-- ---------- RPC de transição ----------
create or replace function app.fn_transition_request(
  p_request_id uuid,
  p_to_status  public.request_status,
  p_comment    text default null,
  p_context    jsonb default '{}'::jsonb
)
returns public.request_status
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare
  v_req  public.purchase_requests%rowtype;
  v_tr   public.request_status_transitions%rowtype;
  v_ok   boolean := false;
  v_items int;
begin
  if auth.uid() is null then
    raise exception 'Não autenticado' using errcode = '28000';
  end if;

  select * into v_req from public.purchase_requests where id = p_request_id for update;
  if not found then
    raise exception 'Demanda % não encontrada', p_request_id using errcode = 'P0002';
  end if;

  select * into v_tr from public.request_status_transitions
   where from_status = v_req.status and to_status = p_to_status;
  if not found then
    raise exception 'Transição inválida: % → %', v_req.status, p_to_status using errcode = 'P0001';
  end if;

  -- Autorização
  v_ok := app.is_admin();
  if not v_ok and v_tr.required_role is not null then
    v_ok := app.has_role(v_tr.required_role);
  end if;
  if not v_ok and v_tr.allow_owner then
    v_ok := (v_req.created_by = auth.uid());
  end if;
  if not v_ok and v_tr.allow_dept_manager then
    v_ok := app.manages_department(v_req.department_id);
  end if;
  if not v_ok then
    raise exception 'Sem permissão para % → %', v_req.status, p_to_status using errcode = '42501';
  end if;

  -- Validações de conteúdo
  if v_tr.requires_comment and (p_comment is null or length(trim(p_comment)) = 0) then
    raise exception 'Justificativa obrigatória para esta transição' using errcode = 'P0001';
  end if;

  if v_tr.requires_items then
    if v_req.title is null or v_req.cost_center_id is null then
      raise exception 'Título e centro de custo são obrigatórios para envio' using errcode = 'P0001';
    end if;
    select count(*) into v_items from public.purchase_request_items where request_id = p_request_id;
    if v_items = 0 then
      raise exception 'A demanda precisa de ao menos um item' using errcode = 'P0001';
    end if;
    if v_req.is_emergency and (v_req.emergency_reason is null or length(trim(v_req.emergency_reason))=0) then
      raise exception 'Compra emergencial exige justificativa da emergência' using errcode = 'P0001';
    end if;
  end if;

  -- Aplica
  update public.purchase_requests
     set status = p_to_status, updated_by = auth.uid()
   where id = p_request_id;

  insert into public.status_history(request_id, from_status, to_status, comment, context, changed_by)
  values (p_request_id, v_req.status, p_to_status, p_comment, p_context, auth.uid());

  return p_to_status;
end;
$$;

-- RPC para um comprador assumir a demanda (define assigned_buyer_id)
create or replace function app.fn_assign_buyer(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
begin
  if not (app.is_purchasing() or app.is_admin()) then
    raise exception 'Apenas compras pode assumir demandas' using errcode = '42501';
  end if;
  update public.purchase_requests
     set assigned_buyer_id = auth.uid(), updated_by = auth.uid()
   where id = p_request_id;
end;
$$;

grant execute on function app.fn_transition_request(uuid, public.request_status, text, jsonb) to authenticated;
grant execute on function app.fn_assign_buyer(uuid) to authenticated;
grant execute on function app.can_read_request(uuid) to authenticated;
