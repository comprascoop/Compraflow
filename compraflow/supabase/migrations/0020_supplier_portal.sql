-- 0020 — Portal externo do fornecedor: convites, tokens com hash, propostas e isolamento
-- Princípio: o token ORIGINAL nunca é armazenado. Só o hash SHA-256.

create table if not exists public.sourcing_invitations (
  id                uuid primary key default gen_random_uuid(),
  sourcing_round_id uuid not null references public.sourcing_rounds(id) on delete cascade,
  supplier_id       uuid not null references public.suppliers(id),
  contact_id        uuid references public.supplier_contacts(id),
  invited_email     citext not null,
  invitation_status public.invitation_status not null default 'RASCUNHO',
  access_mode       text not null default 'LINK' check (access_mode in ('LINK','LINK_OTP','CONTA')),
  expires_at        timestamptz,
  first_access_at   timestamptz,
  last_access_at    timestamptz,
  responded_at      timestamptz,
  declined_at       timestamptz,
  decline_reason    text,
  revoked_at        timestamptz,
  created_at        timestamptz not null default now(),
  created_by        uuid references auth.users(id) default auth.uid(),
  constraint sourcing_invitations_uk unique (sourcing_round_id, supplier_id, invited_email)
);
create index if not exists ix_invitations_round on public.sourcing_invitations(sourcing_round_id);

create table if not exists public.sourcing_invitation_tokens (
  id             uuid primary key default gen_random_uuid(),
  invitation_id  uuid not null references public.sourcing_invitations(id) on delete cascade,
  token_hash     text not null unique,          -- SHA-256 do token; original NUNCA gravado
  expires_at     timestamptz not null,
  used_at        timestamptz,
  revoked_at     timestamptz,
  failed_attempts int not null default 0,
  last_attempt_at timestamptz,
  otp_hash       text,                          -- OTP também só em hash
  otp_expires_at timestamptz,
  created_at     timestamptz not null default now()
);
create index if not exists ix_inv_tokens_invitation on public.sourcing_invitation_tokens(invitation_id);

create table if not exists public.supplier_participation_responses (
  id            uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.sourcing_invitations(id) on delete cascade,
  will_participate boolean not null,
  reason        text,
  accepted_terms boolean not null default false,
  accepted_nda   boolean not null default false,
  contact_name  text,
  contact_phone text,
  created_at    timestamptz not null default now()
);

-- Rascunho da proposta do fornecedor (não é proposta oficial até o envio)
create table if not exists public.supplier_quote_drafts (
  id            uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.sourcing_invitations(id) on delete cascade,
  payload       jsonb not null default '{}'::jsonb,
  updated_at    timestamptz not null default now(),
  constraint supplier_quote_drafts_uk unique (invitation_id)
);

create table if not exists public.supplier_quote_submissions (
  id            uuid primary key default gen_random_uuid(),
  invitation_id uuid not null references public.sourcing_invitations(id),
  quote_id      uuid references public.supplier_quotes(id),
  version_no    int not null default 1,
  protocol      text not null unique,
  payload_hash  text not null,                  -- integridade da versão enviada
  submitted_at  timestamptz not null default now(),
  submitted_ip  inet,
  user_agent    text,
  constraint submissions_uk unique (invitation_id, version_no)
);

create table if not exists public.sourcing_messages (
  id            uuid primary key default gen_random_uuid(),
  round_id      uuid not null references public.sourcing_rounds(id) on delete cascade,
  invitation_id uuid references public.sourcing_invitations(id),   -- null = comunicado a todos
  direction     text not null check (direction in ('FORNECEDOR_PARA_COMPRADOR','COMPRADOR_PARA_FORNECEDOR')),
  is_broadcast  boolean not null default false,
  body          text not null,
  created_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id)
);
create index if not exists ix_sourcing_messages_round on public.sourcing_messages(round_id);

create table if not exists public.quote_opening_events (
  id          uuid primary key default gen_random_uuid(),
  round_id    uuid not null references public.sourcing_rounds(id),
  opened_by   uuid references auth.users(id),
  reason      text,
  created_at  timestamptz not null default now()
);

create table if not exists public.supplier_access_logs (
  id            bigint generated always as identity primary key,
  invitation_id uuid references public.sourcing_invitations(id),
  event         text not null,       -- TOKEN_OK, TOKEN_INVALIDO, OTP_OK, OTP_FALHA, ENVIO
  ip_address    inet,
  user_agent    text,
  created_at    timestamptz not null default now()
);
create index if not exists ix_access_logs_invitation on public.supplier_access_logs(invitation_id);

-- ---------- Funções de token (executadas pelo servidor, nunca pelo browser) ----------
-- Grava só o hash. Quem gera o token é o Route Handler; aqui só registramos.
create or replace function app.fn_register_invitation_token(
  p_invitation_id uuid, p_token_hash text, p_expires_at timestamptz
) returns uuid
language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_id uuid;
begin
  insert into public.sourcing_invitation_tokens (invitation_id, token_hash, expires_at)
  values (p_invitation_id, p_token_hash, p_expires_at)
  returning id into v_id;

  update public.sourcing_invitations
     set invitation_status = 'ENVIADO', expires_at = p_expires_at
   where id = p_invitation_id;
  return v_id;
end;
$$;

-- Valida o hash e devolve o contexto do convite. Aplica expiração, revogação e rate limit.
create or replace function app.fn_validate_invitation_token(p_token_hash text)
returns table (
  invitation_id uuid, round_id uuid, supplier_id uuid, supplier_name text,
  request_id uuid, request_number text, request_title text,
  invited_email citext, deadline_at timestamptz, mode text, status public.invitation_status
)
language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_tok public.sourcing_invitation_tokens%rowtype;
begin
  select * into v_tok from public.sourcing_invitation_tokens t where t.token_hash = p_token_hash;

  if not found then
    insert into public.supplier_access_logs(event) values ('TOKEN_INVALIDO');
    raise exception 'Link inválido' using errcode = '42501';
  end if;

  -- rate limit: 10 tentativas falhas bloqueiam o token
  if v_tok.failed_attempts >= 10 then
    raise exception 'Muitas tentativas. Solicite um novo link ao comprador.' using errcode = '42501';
  end if;
  if v_tok.revoked_at is not null then
    raise exception 'Este link foi revogado' using errcode = '42501';
  end if;
  if v_tok.expires_at < now() then
    update public.sourcing_invitations set invitation_status='EXPIRADO' where id = v_tok.invitation_id;
    raise exception 'Este link expirou' using errcode = '42501';
  end if;

  update public.sourcing_invitations
     set first_access_at = coalesce(first_access_at, now()),
         last_access_at  = now(),
         invitation_status = case when invitation_status = 'ENVIADO' then 'ACESSADO'
                                  else invitation_status end
   where id = v_tok.invitation_id;

  insert into public.supplier_access_logs(invitation_id, event)
  values (v_tok.invitation_id, 'TOKEN_OK');

  return query
  select i.id, sr.id, i.supplier_id, s.legal_name, r.id, r.number, r.title,
         i.invited_email, sr.deadline_at, sr.mode, i.invitation_status
  from public.sourcing_invitations i
  join public.sourcing_rounds sr on sr.id = i.sourcing_round_id
  join public.purchase_requests r on r.id = sr.request_id
  join public.suppliers s on s.id = i.supplier_id
  where i.id = v_tok.invitation_id;
end;
$$;

-- Registra falha de tentativa (chamado pelo servidor quando o hash não confere)
create or replace function app.fn_register_token_failure(p_token_hash text)
returns void language plpgsql security definer
set search_path = app, public, pg_temp
as $$
begin
  update public.sourcing_invitation_tokens
     set failed_attempts = failed_attempts + 1, last_attempt_at = now()
   where token_hash = p_token_hash;
end;
$$;

-- ---------- Submissão definitiva da proposta pelo fornecedor ----------
-- Recalcula TUDO no banco. O que o fornecedor manda de total é ignorado.
create or replace function app.fn_submit_supplier_quote(
  p_invitation_id uuid,
  p_header jsonb,
  p_items  jsonb
) returns table (protocol text, total_cost numeric)
language plpgsql security definer
-- 'extensions' precisa estar no search_path: no Supabase o pgcrypto (digest) mora lá,
-- não em public. Sem isso, digest() não resolve e a submissão falha em produção.
set search_path = app, public, extensions, pg_temp
as $$
declare
  v_inv    public.sourcing_invitations%rowtype;
  v_round  public.sourcing_rounds%rowtype;
  v_quote  uuid;
  v_ver    int;
  v_proto  text;
  it       jsonb;
  v_total  numeric(18,2);
begin
  select * into v_inv from public.sourcing_invitations where id = p_invitation_id for update;
  if not found then raise exception 'Convite não encontrado' using errcode='P0002'; end if;
  if v_inv.revoked_at is not null then raise exception 'Convite revogado' using errcode='42501'; end if;

  select * into v_round from public.sourcing_rounds where id = v_inv.sourcing_round_id;
  -- Prazo é validado no banco: não adianta o navegador mentir.
  if v_round.deadline_at is not null and v_round.deadline_at < now() then
    raise exception 'O prazo para envio de propostas encerrou' using errcode='P0001';
  end if;
  if not v_round.is_open then
    raise exception 'Esta rodada está encerrada' using errcode='P0001';
  end if;

  -- A versão é contada sobre supplier_quotes (fonte autoritativa da rodada+fornecedor),
  -- não sobre as submissões: o comprador pode já ter registrado uma proposta manualmente.
  select coalesce(max(version_no),0) + 1 into v_ver
    from public.supplier_quotes
   where round_id = v_inv.sourcing_round_id and supplier_id = v_inv.supplier_id;

  -- versão anterior deixa de ser a vigente (nunca sobrescreve)
  update public.supplier_quotes set is_current = false
   where round_id = v_inv.sourcing_round_id and supplier_id = v_inv.supplier_id;

  insert into public.supplier_quotes (
    round_id, supplier_id, version_no, is_current, reference, quote_date, valid_until,
    payment_terms, delivery_days, freight_type, freight_amount, insurance_amount,
    taxes_amount, discount_amount, warranty, commercial_notes, contact_name,
    status, submitted_at
  ) values (
    v_inv.sourcing_round_id, v_inv.supplier_id, v_ver, true,
    p_header->>'reference', current_date, (p_header->>'valid_until')::date,
    p_header->>'payment_terms', nullif(p_header->>'delivery_days','')::int,
    p_header->>'freight_type',
    coalesce((p_header->>'freight_amount')::numeric, 0),
    coalesce((p_header->>'insurance_amount')::numeric, 0),
    coalesce((p_header->>'taxes_amount')::numeric, 0),
    coalesce((p_header->>'discount_amount')::numeric, 0),
    p_header->>'warranty', p_header->>'commercial_notes', p_header->>'contact_name',
    'RECEBIDA', now()
  ) returning id into v_quote;

  -- Itens: só aceita request_item_id que pertence À DEMANDA da rodada.
  -- Isso impede o fornecedor de injetar item de outro processo.
  for it in select * from jsonb_array_elements(p_items) loop
    if not exists (
      select 1 from public.purchase_request_items pri
      join public.sourcing_rounds sr on sr.request_id = pri.request_id
      where pri.id = (it->>'request_item_id')::uuid and sr.id = v_inv.sourcing_round_id
    ) then
      raise exception 'Item inválido para esta cotação' using errcode='42501';
    end if;

    insert into public.supplier_quote_items (
      quote_id, request_item_id, will_quote, offered_description, brand, model,
      quantity_offered, unit_price, discount_amount, taxes_amount, delivery_days,
      technical_fit, is_equivalent, notes
    ) values (
      v_quote, (it->>'request_item_id')::uuid,
      coalesce((it->>'will_quote')::boolean, true),
      it->>'offered_description', it->>'brand', it->>'model',
      coalesce((it->>'quantity_offered')::numeric, 0),
      coalesce((it->>'unit_price')::numeric, 0),
      coalesce((it->>'discount_amount')::numeric, 0),
      coalesce((it->>'taxes_amount')::numeric, 0),
      nullif(it->>'delivery_days','')::int,
      coalesce(it->>'technical_fit','ATENDE'),
      coalesce((it->>'is_equivalent')::boolean, false),
      it->>'notes'
    );
  end loop;

  perform app.fn_recalc_quote(v_quote);
  select q.total_cost into v_total from public.supplier_quotes q where q.id = v_quote;

  v_proto := 'PROP-' || to_char(now(),'YYYYMMDD') || '-' || upper(substr(replace(v_quote::text,'-',''),1,8));

  insert into public.supplier_quote_submissions
    (invitation_id, quote_id, version_no, protocol, payload_hash)
  values (p_invitation_id, v_quote, v_ver, v_proto,
          encode(digest(p_header::text || p_items::text, 'sha256'), 'hex'));

  update public.supplier_quotes set protocol = v_proto where id = v_quote;

  update public.sourcing_invitations
     set invitation_status='RESPONDIDO', responded_at=now() where id = p_invitation_id;
  update public.sourcing_suppliers set status='RESPONDIDO'
   where round_id = v_inv.sourcing_round_id and supplier_id = v_inv.supplier_id;

  insert into public.supplier_access_logs(invitation_id, event) values (p_invitation_id, 'ENVIO');

  -- notifica o comprador responsável
  insert into public.notifications (user_id, type, title, body, link)
  select r.assigned_buyer_id, 'PROPOSTA_RECEBIDA',
         'Nova proposta recebida', s.legal_name || ' enviou proposta (' || v_proto || ')',
         '/demandas/' || r.id || '/comparativo'
  from public.sourcing_rounds sr
  join public.purchase_requests r on r.id = sr.request_id
  join public.suppliers s on s.id = v_inv.supplier_id
  where sr.id = v_inv.sourcing_round_id and r.assigned_buyer_id is not null;

  return query select v_proto, v_total;
end;
$$;

-- ---------- Recusa de participação ----------
create or replace function app.fn_decline_invitation(p_invitation_id uuid, p_reason text)
returns void language plpgsql security definer
set search_path = app, public, pg_temp
as $$
declare v_inv public.sourcing_invitations%rowtype;
begin
  select * into v_inv from public.sourcing_invitations where id = p_invitation_id;
  if not found then raise exception 'Convite não encontrado' using errcode='P0002'; end if;

  update public.sourcing_invitations
     set invitation_status='RECUSADO', declined_at=now(), decline_reason=p_reason
   where id = p_invitation_id;
  update public.sourcing_suppliers set status='RECUSADO', decline_reason=p_reason
   where round_id = v_inv.sourcing_round_id and supplier_id = v_inv.supplier_id;
end;
$$;

-- ---------- Abertura de envelope fechado (registrada e justificada) ----------
create or replace function app.fn_open_sealed_round(p_round_id uuid, p_reason text)
returns void language plpgsql security definer
set search_path = app, public, pg_temp
as $$
begin
  if not (app.is_purchasing() or app.is_admin()) then
    raise exception 'Sem permissão para abrir propostas' using errcode='42501';
  end if;
  update public.sourcing_rounds
     set opened_at = now(), opened_by = auth.uid(), is_open = false
   where id = p_round_id;
  insert into public.quote_opening_events (round_id, opened_by, reason)
  values (p_round_id, auth.uid(), p_reason);
end;
$$;

-- ---------- RLS: isolamento absoluto entre fornecedores ----------
-- O portal NÃO usa a sessão do usuário interno: tudo passa pelo servidor (service role)
-- após validação de token. Por isso as tabelas do portal são fechadas para 'authenticated'
-- em escrita, e a leitura é limitada à equipe de compras.
alter table public.sourcing_invitations              enable row level security;
alter table public.sourcing_invitation_tokens         enable row level security;
alter table public.supplier_participation_responses   enable row level security;
alter table public.supplier_quote_drafts              enable row level security;
alter table public.supplier_quote_submissions         enable row level security;
alter table public.sourcing_messages                  enable row level security;
alter table public.quote_opening_events               enable row level security;
alter table public.supplier_access_logs               enable row level security;

drop policy if exists sel_invitations on public.sourcing_invitations;
create policy sel_invitations on public.sourcing_invitations for select to authenticated
  using (app.can_read_round(sourcing_round_id));
drop policy if exists wr_invitations on public.sourcing_invitations;
create policy wr_invitations on public.sourcing_invitations for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

-- TOKENS: nenhuma policy. Nem compras lê hash de token pela API. Só funções definer.

drop policy if exists sel_participation on public.supplier_participation_responses;
create policy sel_participation on public.supplier_participation_responses for select to authenticated
  using (exists (select 1 from public.sourcing_invitations i
                 where i.id = invitation_id and app.can_read_round(i.sourcing_round_id)));

drop policy if exists sel_submissions on public.supplier_quote_submissions;
create policy sel_submissions on public.supplier_quote_submissions for select to authenticated
  using (exists (select 1 from public.sourcing_invitations i
                 where i.id = invitation_id and app.can_read_round(i.sourcing_round_id)));

drop policy if exists sel_messages on public.sourcing_messages;
create policy sel_messages on public.sourcing_messages for select to authenticated
  using (app.can_read_round(round_id));
drop policy if exists wr_messages on public.sourcing_messages;
create policy wr_messages on public.sourcing_messages for all to authenticated
  using (app.is_purchasing() or app.is_admin())
  with check (app.is_purchasing() or app.is_admin());

drop policy if exists sel_opening on public.quote_opening_events;
create policy sel_opening on public.quote_opening_events for select to authenticated
  using (app.can_read_round(round_id) or app.is_auditor());

drop policy if exists sel_access_logs on public.supplier_access_logs;
create policy sel_access_logs on public.supplier_access_logs for select to authenticated
  using (app.is_admin() or app.is_auditor()
         or exists (select 1 from public.sourcing_invitations i
                    where i.id = invitation_id and app.can_read_round(i.sourcing_round_id)));

-- Painel de acompanhamento da rodada
create or replace view public.v_round_tracking as
select sr.id as round_id, sr.request_id, sr.round_no, sr.deadline_at, sr.mode,
  count(i.id)                                                        as convidados,
  count(*) filter (where i.invitation_status in ('ENVIADO','ENTREGUE','ACESSADO',
                    'PARTICIPACAO_CONFIRMADA','PROPOSTA_EM_RASCUNHO','RESPONDIDO')) as enviados,
  count(*) filter (where i.first_access_at is not null)               as acessados,
  count(*) filter (where i.invitation_status = 'RESPONDIDO')          as responderam,
  count(*) filter (where i.invitation_status = 'RECUSADO')            as recusaram,
  count(*) filter (where i.invitation_status = 'EXPIRADO')            as expirados,
  count(*) filter (where i.responded_at is null and i.declined_at is null) as sem_resposta
from public.sourcing_rounds sr
left join public.sourcing_invitations i on i.sourcing_round_id = sr.id
group by sr.id, sr.request_id, sr.round_no, sr.deadline_at, sr.mode;

grant execute on function app.fn_open_sealed_round(uuid, text) to authenticated;

do $$
declare t text;
begin
  foreach t in array array['sourcing_invitations','supplier_quote_submissions','quote_opening_events'] loop
    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format('create trigger tg_audit after insert or update or delete on public.%I
                    for each row execute function app.tg_audit()', t);
  end loop;
end $$;
