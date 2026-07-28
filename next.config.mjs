-- 0013 — Contatos, categorias, documentos, avaliações e dados bancários (isolados)

-- ---------- Contatos ----------
create table if not exists public.supplier_contacts (
  id          uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  name        text not null,
  title       text,
  email       citext,
  phone       text,
  is_primary  boolean not null default false,
  notes       text,
  deleted_at  timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists ix_supplier_contacts_supplier on public.supplier_contacts(supplier_id);

-- ---------- Categorias atendidas ----------
create table if not exists public.supplier_categories (
  supplier_id uuid not null references public.suppliers(id) on delete cascade,
  category_id uuid not null references public.categories(id),
  primary key (supplier_id, category_id)
);

-- ---------- Documentos / certidões (arquivo físico no bucket supplier-documents) ----------
create table if not exists public.supplier_documents (
  id            uuid primary key default gen_random_uuid(),
  supplier_id   uuid not null references public.suppliers(id) on delete cascade,
  doc_type      text not null,                 -- CERTIDAO, CONTRATO_SOCIAL, ATESTADO, OUTRO
  title         text not null,
  storage_path  text not null,                 -- nome físico (UUID) no bucket
  original_name text,
  mime_type     text,
  size_bytes    bigint,
  valid_until   date,                          -- vencimento (certidões)
  deleted_at    timestamptz,                   -- exclusão lógica
  created_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id)
);
create index if not exists ix_supplier_docs_supplier on public.supplier_documents(supplier_id);
create index if not exists ix_supplier_docs_validade on public.supplier_documents(valid_until);

-- ---------- Avaliações (alimentam rating médio) ----------
create table if not exists public.supplier_evaluations (
  id           uuid primary key default gen_random_uuid(),
  supplier_id  uuid not null references public.suppliers(id) on delete cascade,
  score        numeric(3,2) not null check (score >= 0 and score <= 5),
  criteria     jsonb not null default '{}'::jsonb,   -- notas por critério (prazo, qualidade, ...)
  comment      text,
  period       text,
  created_at   timestamptz not null default now(),
  created_by   uuid references auth.users(id)
);
create index if not exists ix_supplier_evals_supplier on public.supplier_evaluations(supplier_id);

-- ---------- Dados bancários (SENSÍVEL — tabela isolada, RLS restrita) ----------
create table if not exists public.supplier_bank_accounts (
  id            uuid primary key default gen_random_uuid(),
  supplier_id   uuid not null references public.suppliers(id) on delete cascade,
  bank_code     text,
  bank_name     text,
  agency        text,
  account       text,
  account_type  text,
  pix_key       text,
  holder_name   text,
  holder_document text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  created_by    uuid references auth.users(id)
);
create index if not exists ix_supplier_bank_supplier on public.supplier_bank_accounts(supplier_id);

-- Recalcula rating médio do fornecedor a cada avaliação.
create or replace function app.tg_recalc_supplier_rating()
returns trigger language plpgsql
security definer
set search_path = app, public, pg_temp
as $$
declare v_sup uuid;
begin
  v_sup := coalesce(new.supplier_id, old.supplier_id);
  update public.suppliers s
     set rating = (select round(avg(e.score),2) from public.supplier_evaluations e
                   where e.supplier_id = v_sup)
   where s.id = v_sup;
  return null;
end;
$$;
drop trigger if exists tg_recalc_rating on public.supplier_evaluations;
create trigger tg_recalc_rating after insert or update or delete on public.supplier_evaluations
  for each row execute function app.tg_recalc_supplier_rating();

-- updated_at + auditoria nas tabelas relacionadas com essa coluna
do $$
declare t text;
begin
  foreach t in array array['supplier_contacts','supplier_bank_accounts'] loop
    execute format('drop trigger if exists tg_touch on public.%I', t);
    execute format('create trigger tg_touch before update on public.%I
                    for each row execute function app.tg_touch_updated_at()', t);
  end loop;
  foreach t in array array['supplier_contacts','supplier_categories','supplier_documents',
                           'supplier_evaluations','supplier_bank_accounts'] loop
    execute format('drop trigger if exists tg_audit on public.%I', t);
    execute format('create trigger tg_audit after insert or update or delete on public.%I
                    for each row execute function app.tg_audit()', t);
  end loop;
end $$;
