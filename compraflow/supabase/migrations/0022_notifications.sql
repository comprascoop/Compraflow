-- 0022 — Notificações automáticas por trigger (não dependem do frontend)

-- Notifica compras quando uma demanda é enviada; notifica o requisitante nas mudanças.
create or replace function app.tg_notify_status_change()
returns trigger language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare
  v_req public.purchase_requests%rowtype;
  v_title text;
begin
  select * into v_req from public.purchase_requests where id = new.request_id;

  -- 1) Demanda enviada → avisa a área de compras
  if new.to_status = 'ENVIADA' then
    insert into public.notifications (user_id, type, title, body, link, priority)
    select ur.user_id, 'NOVA_DEMANDA', 'Nova demanda enviada',
           v_req.number || ' — ' || v_req.title,
           '/demandas/' || v_req.id, v_req.priority
    from public.user_roles ur
    join public.roles ro on ro.id = ur.role_id
    where ro.code in ('COMPRADOR','COORDENADOR_COMPRAS') and ur.is_active;
  end if;

  -- 2) Avisa o autor da demanda nas mudanças relevantes
  if new.to_status in ('AGUARDANDO_INFORMACOES','APROVADA','REJEITADA','PEDIDO_EMITIDO','ENCERRADA')
     and v_req.created_by is not null and v_req.created_by <> auth.uid() then
    v_title := case new.to_status
      when 'AGUARDANDO_INFORMACOES' then 'Compras solicitou informações'
      when 'APROVADA'        then 'Sua demanda foi aprovada'
      when 'REJEITADA'       then 'Sua demanda foi rejeitada'
      when 'PEDIDO_EMITIDO'  then 'Pedido de compra emitido'
      else 'Demanda encerrada' end;
    insert into public.notifications (user_id, type, title, body, link, priority)
    values (v_req.created_by, 'STATUS_DEMANDA', v_title,
            v_req.number || ' — ' || v_req.title, '/demandas/' || v_req.id, v_req.priority);
  end if;

  return new;
end;
$$;
drop trigger if exists tg_notify_status on public.status_history;
create trigger tg_notify_status after insert on public.status_history
  for each row execute function app.tg_notify_status_change();

-- Notifica aprovadores quando um fluxo de aprovação é aberto.
create or replace function app.tg_notify_approval()
returns trigger language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_req public.purchase_requests%rowtype;
begin
  select * into v_req from public.purchase_requests where id = new.request_id;

  -- aprovadores nominais da etapa
  insert into public.notifications (user_id, type, title, body, link, priority)
  select s.approver_user_id, 'APROVACAO_PENDENTE', 'Aprovação pendente',
         v_req.number || ' — ' || v_req.title, '/aprovacoes', v_req.priority
  from public.approval_instance_steps s
  where s.instance_id = new.id and s.approver_user_id is not null;

  -- aprovadores por papel
  insert into public.notifications (user_id, type, title, body, link, priority)
  select ur.user_id, 'APROVACAO_PENDENTE', 'Aprovação pendente',
         v_req.number || ' — ' || v_req.title, '/aprovacoes', v_req.priority
  from public.approval_instance_steps s
  join public.roles ro on ro.code = s.approver_role
  join public.user_roles ur on ur.role_id = ro.id and ur.is_active
  where s.instance_id = new.id and s.approver_role is not null;

  return new;
end;
$$;
drop trigger if exists tg_notify_approval on public.approval_instances;
create trigger tg_notify_approval after insert on public.approval_instances
  for each row execute function app.tg_notify_approval();

-- Marca notificações como lidas
create or replace function app.fn_mark_notifications_read(p_ids uuid[] default null)
returns int language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_count int;
begin
  update public.notifications
     set read_at = now()
   where user_id = auth.uid() and read_at is null
     and (p_ids is null or id = any(p_ids));
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
grant execute on function app.fn_mark_notifications_read(uuid[]) to authenticated;
