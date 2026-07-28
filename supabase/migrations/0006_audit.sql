-- 0006 — Auditoria imutável + triggers de suporte
-- audit_logs recebe INSERT via trigger e nada mais. Sem UPDATE/DELETE (garantido por RLS na 0007).

create table if not exists public.audit_logs (
  id          bigint generated always as identity primary key,
  actor_id    uuid references auth.users(id),
  entity      text not null,          -- nome da tabela
  entity_id   uuid,
  action      text not null,          -- INSERT | UPDATE | DELETE | (ações de domínio)
  old_values  jsonb,
  new_values  jsonb,
  context     jsonb,                  -- ip, user_agent, versão da recomendação, etc.
  created_at  timestamptz not null default now()
);
create index if not exists ix_audit_entity on public.audit_logs(entity, entity_id);
create index if not exists ix_audit_created on public.audit_logs(created_at);

-- Toca updated_at automaticamente.
create or replace function app.tg_touch_updated_at()
returns trigger language plpgsql
set search_path = app, public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Trigger genérico de auditoria. Anexar às tabelas críticas.
create or replace function app.tg_audit()
returns trigger
language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare
  v_old jsonb;
  v_new jsonb;
  v_id  uuid;
begin
  if tg_op = 'DELETE' then
    v_old := to_jsonb(old); v_new := null; v_id := (old).id;
  elsif tg_op = 'UPDATE' then
    v_old := to_jsonb(old); v_new := to_jsonb(new); v_id := (new).id;
  else
    v_old := null; v_new := to_jsonb(new); v_id := (new).id;
  end if;

  insert into public.audit_logs(actor_id, entity, entity_id, action, old_values, new_values)
  values (auth.uid(), tg_table_name, v_id, tg_op, v_old, v_new);

  if tg_op = 'DELETE' then return old; else return new; end if;
end;
$$;

-- Anexa updated_at + auditoria nas tabelas de cadastro já existentes.
do $$
declare t text;
begin
  foreach t in array array[
    'companies','business_units','departments','cost_centers','profiles',
    'roles','user_roles','user_departments'
  ]
  loop
    execute format('drop trigger if exists tg_touch on public.%I', t);
    -- profiles/roles não têm updated_at nas de RBAC simples; só anexa onde a coluna existe.
    if exists (select 1 from information_schema.columns
               where table_schema='public' and table_name=t and column_name='updated_at') then
      execute format(
        'create trigger tg_touch before update on public.%I
         for each row execute function app.tg_touch_updated_at()', t);
    end if;

    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format(
      'create trigger tg_audit after insert or update or delete on public.%I
       for each row execute function app.tg_audit()', t);
  end loop;
end $$;
