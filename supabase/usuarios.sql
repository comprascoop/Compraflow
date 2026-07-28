-- ============================================================================
-- ⚠️ ORDEM DE EXECUÇÃO OBRIGATÓRIA:
--    1) _TUDO_EM_UM.sql  (as migrations)
--    2) seed.sql         (empresa, setores, unidades, fornecedores)
--    3) usuarios.sql     (este arquivo — cria/repara usuários e vincula às unidades)
-- Rodar este arquivo ANTES do seed deixa os usuários sem vínculo de unidade.
-- ============================================================================
-- ============================================================================
-- USUÁRIOS — criar, reparar e configurar (tudo por SQL)
-- ============================================================================
-- Rode este arquivo INTEIRO no SQL Editor do Supabase. Ele é idempotente:
-- pode rodar quantas vezes quiser.
--
--   Bloco 1 → cria os usuários que faltam
--   Bloco 2 → repara usuários já existentes (o motivo de login falhar)
--   Bloco 3 → atribui papéis
--   Bloco 4 → vincula setores
--   Bloco 5 → conferência
--
-- Senha de todos: Compra@123
-- ============================================================================

set search_path = public, extensions;

-- ---------------------------------------------------------------------------
-- BLOCO 0 — garantir unidades de negócio (idempotente; independe do seed)
-- ---------------------------------------------------------------------------
insert into public.business_units (id, company_id, name, code)
select 'b0000000-0000-0000-0000-0000000000a1', c.id, 'Posto de Combustível', 'POSTO'
from public.companies c order by c.created_at limit 1
on conflict (id) do nothing;
insert into public.business_units (id, company_id, name, code)
select 'b0000000-0000-0000-0000-0000000000a2', c.id, 'Loja Agropecuária', 'AGRO'
from public.companies c order by c.created_at limit 1
on conflict (id) do nothing;
insert into public.business_units (id, company_id, name, code)
select 'b0000000-0000-0000-0000-0000000000a3', c.id, 'Supermercado', 'SUPER'
from public.companies c order by c.created_at limit 1
on conflict (id) do nothing;


-- ---------------------------------------------------------------------------
-- BLOCO 1 + 2 — criar e reparar
-- ---------------------------------------------------------------------------
-- Por que "reparar": o serviço de Auth do Supabase (GoTrue) lê colunas de token
-- que NÃO aceitam NULL. Um INSERT que deixe qualquer uma delas nula gera um
-- usuário que existe na tabela mas cujo login é sempre recusado.
-- O bloco abaixo preenche todas com string vazia, seja qual for a versão do GoTrue.
do $$
declare
  v_pass  text := crypt('Compra@123', gen_salt('bf'));
  v_uid   uuid;
  v_email text;
  v_nome  text;
  demo constant jsonb := '[
    {"email":"admin@compraflow.local",        "nome":"Ana Admin"},
    {"email":"requisitante@compraflow.local", "nome":"Rui Requisitante"},
    {"email":"gestor@compraflow.local",       "nome":"Gina Gestora"},
    {"email":"comprador@compraflow.local",    "nome":"Caio Comprador"},
    {"email":"coordenador@compraflow.local",  "nome":"Cora Coordenadora"},
    {"email":"diretor@compraflow.local",      "nome":"Davi Diretor"},
    {"email":"auditor@compraflow.local",      "nome":"Aline Auditora"}
  ]'::jsonb;
  item jsonb;
begin
  for item in select * from jsonb_array_elements(demo) loop
    v_email := item->>'email';
    v_nome  := item->>'nome';

    select id into v_uid from auth.users where lower(email) = lower(v_email);

    if v_uid is null then
      -- ----- cria -----
      v_uid := gen_random_uuid();
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change
      ) values (
        '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
        lower(v_email), v_pass, now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('full_name', v_nome, 'email_verified', true),
        now(), now(), '', '', '', ''
      );
    else
      -- ----- repara: redefine a senha e confirma o e-mail -----
      update auth.users
         set encrypted_password = v_pass,
             email_confirmed_at = coalesce(email_confirmed_at, now()),
             aud  = 'authenticated',
             role = 'authenticated',
             raw_app_meta_data = '{"provider":"email","providers":["email"]}'::jsonb,
             raw_user_meta_data = jsonb_build_object('full_name', v_nome, 'email_verified', true),
             banned_until = null,
             deleted_at = null,
             updated_at = now()
       where id = v_uid;
    end if;

    -- ----- identidade (o GoTrue exige uma por provedor) -----
    if not exists (select 1 from auth.identities
                   where user_id = v_uid and provider = 'email') then
      insert into auth.identities (
        id, provider_id, user_id, identity_data, provider,
        last_sign_in_at, created_at, updated_at
      ) values (
        gen_random_uuid(), v_uid::text, v_uid,
        jsonb_build_object('sub', v_uid::text, 'email', lower(v_email), 'email_verified', true),
        'email', now(), now(), now()
      );
    end if;

    -- ----- garante profile -----
    insert into public.profiles (id, full_name, email)
    values (v_uid, v_nome, lower(v_email))
    on conflict (id) do update set full_name = excluded.full_name;
  end loop;
end $$;

-- Zera QUALQUER coluna de token que esteja NULL, em qualquer versão do GoTrue.
-- É esta linha que costuma destravar o "Invalid login credentials" teimoso.
do $$
declare c record;
begin
  for c in
    select column_name from information_schema.columns
     where table_schema = 'auth' and table_name = 'users'
       and data_type in ('character varying','text')
       and column_name in ('confirmation_token','recovery_token','email_change',
                           'email_change_token_new','email_change_token_current',
                           'phone_change','phone_change_token','reauthentication_token')
  loop
    execute format('update auth.users set %I = %L where %I is null', c.column_name, '', c.column_name);
  end loop;
end $$;


-- ---------------------------------------------------------------------------
-- BLOCO 3 — papéis
-- ---------------------------------------------------------------------------
-- Papéis válidos: ADMINISTRADOR, REQUISITANTE, GESTOR_SETOR, COMPRADOR,
--                 COORDENADOR_COMPRAS, APROVADOR_FINANCEIRO, AUDITOR
insert into public.user_roles (user_id, role_id)
select u.id, r.id
from auth.users u
join (values
  ('admin@compraflow.local',        'ADMINISTRADOR'),
  ('requisitante@compraflow.local', 'REQUISITANTE'),
  ('gestor@compraflow.local',       'GESTOR_SETOR'),
  ('comprador@compraflow.local',    'COMPRADOR'),
  ('coordenador@compraflow.local',  'COORDENADOR_COMPRAS'),
  ('coordenador@compraflow.local',  'COMPRADOR'),
  ('diretor@compraflow.local',      'APROVADOR_FINANCEIRO'),
  ('auditor@compraflow.local',      'AUDITOR')
) as v(email, papel) on lower(u.email) = lower(v.email)
join public.roles r on r.code = v.papel
on conflict (user_id, role_id) do nothing;


-- ---------------------------------------------------------------------------
-- BLOCO 4 — setores (obrigatório p/ requisitante criar demanda)
-- ---------------------------------------------------------------------------
insert into public.user_departments (user_id, department_id, is_manager, is_primary)
select u.id, d.id, v.gestor, true
from auth.users u
join (values
  ('requisitante@compraflow.local', 'Operações', false),
  ('gestor@compraflow.local',       'Operações', true),
  ('comprador@compraflow.local',    'Compras',   false),
  ('coordenador@compraflow.local',  'Compras',   false)
) as v(email, setor, gestor) on lower(u.email) = lower(v.email)
join public.departments d on d.name = v.setor
on conflict (user_id, department_id) do nothing;




-- ---------------------------------------------------------------------------
-- BLOCO 4b — vínculo com UNIDADES DE NEGÓCIO (isolamento multisetorial)
-- ---------------------------------------------------------------------------
-- Comprador/coordenador atendem TODAS as unidades. Admin e diretor têm visão global.
insert into public.user_business_units (user_id, business_unit_id, is_primary)
select u.id, bu.id, false
from auth.users u
cross join public.business_units bu
where lower(u.email) in ('comprador@compraflow.local','coordenador@compraflow.local')
  and bu.code in ('POSTO','AGRO','SUPER')
on conflict (user_id, business_unit_id) do nothing;

-- papel de visão global para admin e diretor
insert into public.user_roles (user_id, role_id)
select u.id, r.id
from auth.users u
join public.roles r on r.code = 'VE_TODAS_UNIDADES'
where lower(u.email) in ('admin@compraflow.local','diretor@compraflow.local')
on conflict (user_id, role_id) do nothing;

-- requisitante e gestor demo → unidade Operações continua; para testar multisetor,
-- vincule-os a POSTO/AGRO/SUPER pela tela de Administração.

-- ---------------------------------------------------------------------------
-- BLOCO 5 — conferência
-- ---------------------------------------------------------------------------
select u.email,
       u.email_confirmed_at is not null                              as confirmado,
       (select count(*) from auth.identities i where i.user_id=u.id) as identidades,
       coalesce(string_agg(distinct r.code, ', '), '(sem papel)')    as papeis,
       coalesce(string_agg(distinct d.name, ', '), '(sem setor)')    as setores
from auth.users u
left join public.user_roles ur on ur.user_id = u.id
left join public.roles r on r.id = ur.role_id
left join public.user_departments ud on ud.user_id = u.id
left join public.departments d on d.id = ud.department_id
where u.email like '%@compraflow.local'
group by u.email, u.email_confirmed_at, u.id
order by u.email;
