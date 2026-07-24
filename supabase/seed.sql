-- Garante que pgcrypto (crypt/gen_salt) seja encontrado tanto no Supabase
-- (onde vive em 'extensions') quanto em Postgres puro (onde pode estar em 'public').
set search_path = public, extensions;

-- ============================================================================
-- SEED — rodado automaticamente pelo `supabase db reset`.
-- ⚠️ Cria usuários com senha: APENAS AMBIENTE LOCAL. Senha de todos: Compra@123
-- ============================================================================

insert into public.roles (code, name, description) values
  ('ADMINISTRADOR','Administrador','Configuração total do sistema'),
  ('REQUISITANTE','Requisitante','Cria e acompanha demandas'),
  ('GESTOR_SETOR','Gestor do setor','Aprova demandas do próprio setor'),
  ('COMPRADOR','Comprador','Conduz cotações e recomendações'),
  ('COORDENADOR_COMPRAS','Coordenador de compras','Supervisiona a área de compras'),
  ('APROVADOR_FINANCEIRO','Aprovador financeiro','Aprova/rejeita no âmbito financeiro'),
  ('AUDITOR','Auditor','Somente leitura de processos e trilhas')
on conflict (code) do nothing;

insert into public.permissions (code, description) values
  ('requests.create','Criar demanda'),('requests.submit','Enviar demanda'),
  ('sourcing.manage','Gerir cotações'),('recommendations.create','Recomendar fornecedor'),
  ('approvals.decide','Decidir aprovação'),('orders.issue','Emitir pedido'),
  ('suppliers.manage','Gerir fornecedores'),('suppliers.approve','Homologar fornecedores'),
  ('admin.manage','Administrar'),('audit.read','Consultar auditoria')
on conflict (code) do nothing;

insert into public.companies (id, name, legal_name, cnpj) values
  ('a0000000-0000-0000-0000-000000000001','Empresa Demo','Empresa Demonstração LTDA','11222333000181')
on conflict (id) do nothing;

insert into public.business_units (id, company_id, name, code) values
  ('b0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000001','Matriz','MTZ'),
  ('b0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000001','Filial Norte','FN'),
  ('b0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000001','Filial Sul','FS')
on conflict (id) do nothing;

insert into public.departments (id, business_unit_id, name, code) values
  ('c0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','Administrativo','ADM'),
  ('c0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000001','Operações','OPE'),
  ('c0000000-0000-0000-0000-000000000003','b0000000-0000-0000-0000-000000000001','Manutenção','MAN'),
  ('c0000000-0000-0000-0000-000000000004','b0000000-0000-0000-0000-000000000001','Tecnologia','TEC'),
  ('c0000000-0000-0000-0000-000000000005','b0000000-0000-0000-0000-000000000001','Financeiro','FIN'),
  ('c0000000-0000-0000-0000-000000000006','b0000000-0000-0000-0000-000000000001','Compras','CMP')
on conflict (id) do nothing;

insert into public.cost_centers (id, department_id, name, code) values
  ('d0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','Operações — Geral','OPE-001'),
  ('d0000000-0000-0000-0000-000000000002','c0000000-0000-0000-0000-000000000003','Manutenção — Predial','MAN-001'),
  ('d0000000-0000-0000-0000-000000000003','c0000000-0000-0000-0000-000000000004','TI — Infraestrutura','TEC-001'),
  ('d0000000-0000-0000-0000-000000000004','c0000000-0000-0000-0000-000000000001','Administrativo — Geral','ADM-001')
on conflict (id) do nothing;

insert into public.categories (id, name) values
  ('e0000000-0000-0000-0000-000000000001','Materiais de escritório'),
  ('e0000000-0000-0000-0000-000000000002','Equipamentos de TI'),
  ('e0000000-0000-0000-0000-000000000003','Serviços de manutenção'),
  ('e0000000-0000-0000-0000-000000000004','Insumos operacionais')
on conflict (id) do nothing;

insert into public.units_of_measure (code, name) values
  ('UN','Unidade'),('CX','Caixa'),('KG','Quilograma'),('L','Litro'),
  ('M','Metro'),('H','Hora'),('SV','Serviço')
on conflict (code) do nothing;

insert into public.suppliers (id, legal_name, trade_name, cnpj, state, city, status, average_lead_time_days, default_payment_terms) values
  ('f0000000-0000-0000-0000-000000000001','Alfa Materiais e Suprimentos LTDA','Alfa Suprimentos','11222333000181','GO','Goiânia','HOMOLOGADO',7,'30 dias'),
  ('f0000000-0000-0000-0000-000000000002','Beta Equipamentos Industriais S.A.','Beta Equip','19274022000178','SP','Campinas','HOMOLOGADO',15,'28/56 dias'),
  ('f0000000-0000-0000-0000-000000000003','Gamma Serviços de Manutenção EIRELI','Gamma Manutenção','45448325000170','GO','Anápolis','HOMOLOGADO_COM_RESTRICAO',10,'À vista'),
  ('f0000000-0000-0000-0000-000000000004','Delta Tecnologia e Informática LTDA','Delta Tech','33014556000196','DF','Brasília','PENDENTE_DE_HOMOLOGACAO',5,'30/60/90 dias'),
  ('f0000000-0000-0000-0000-000000000005','Epsilon Comércio de Peças LTDA','Epsilon Peças','60746948000112','MG','Uberlândia','HOMOLOGADO',12,'21 dias')
on conflict (id) do nothing;

-- ---------- Matriz de aprovação ----------
-- Até R$ 5.000: gestor do setor. Acima: diretor financeiro.
insert into public.approval_rules (id, name, min_amount, max_amount, priority_order) values
  ('11111111-0000-0000-0000-000000000001','Compras até R$ 5.000', 0, 5000, 10),
  ('11111111-0000-0000-0000-000000000002','Compras acima de R$ 5.000', 5000.01, null, 20)
on conflict (id) do nothing;

insert into public.approval_rule_steps (rule_id, step_no, approver_role, use_dept_manager, min_approvals) values
  ('11111111-0000-0000-0000-000000000001', 1, null, true, 1),
  ('11111111-0000-0000-0000-000000000002', 1, 'APROVADOR_FINANCEIRO', false, 1)
on conflict (rule_id, step_no) do nothing;

-- ---------- Usuários demo ----------
do $$
declare
  v_pass text := crypt('Compra@123', gen_salt('bf'));
  demo constant jsonb := '[
    {"email":"admin@compraflow.local","name":"Ana Admin","roles":["ADMINISTRADOR"]},
    {"email":"requisitante@compraflow.local","name":"Rui Requisitante","roles":["REQUISITANTE"]},
    {"email":"gestor@compraflow.local","name":"Gina Gestora","roles":["GESTOR_SETOR"]},
    {"email":"comprador@compraflow.local","name":"Caio Comprador","roles":["COMPRADOR"]},
    {"email":"coordenador@compraflow.local","name":"Cora Coordenadora","roles":["COORDENADOR_COMPRAS","COMPRADOR"]},
    {"email":"diretor@compraflow.local","name":"Davi Diretor","roles":["APROVADOR_FINANCEIRO"]},
    {"email":"auditor@compraflow.local","name":"Aline Auditora","roles":["AUDITOR"]}
  ]'::jsonb;
  item jsonb; v_uid uuid; v_role text;
begin
  for item in select * from jsonb_array_elements(demo) loop
    select id into v_uid from auth.users where email = item->>'email';
    if v_uid is null then
      v_uid := gen_random_uuid();
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, recovery_token, email_change_token_new, email_change
      ) values (
        '00000000-0000-0000-0000-000000000000', v_uid, 'authenticated', 'authenticated',
        item->>'email', v_pass, now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('full_name', item->>'name'),
        now(), now(), '', '', '', ''
      );
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (gen_random_uuid(), v_uid, v_uid::text,
              jsonb_build_object('sub', v_uid::text, 'email', item->>'email'), 'email', now(), now(), now());
    end if;

    update public.profiles set full_name = item->>'name' where id = v_uid;

    for v_role in select jsonb_array_elements_text(item->'roles') loop
      insert into public.user_roles (user_id, role_id)
      select v_uid, id from public.roles where code = v_role
      on conflict (user_id, role_id) do nothing;
    end loop;
  end loop;

  -- vínculos de setor
  insert into public.user_departments (user_id, department_id, is_manager, is_primary)
  select u.id, 'c0000000-0000-0000-0000-000000000002', false, true
  from auth.users u where u.email = 'requisitante@compraflow.local' on conflict do nothing;

  insert into public.user_departments (user_id, department_id, is_manager, is_primary)
  select u.id, 'c0000000-0000-0000-0000-000000000002', true, true
  from auth.users u where u.email = 'gestor@compraflow.local' on conflict do nothing;

  -- comprador e coordenador no setor Compras
  insert into public.user_departments (user_id, department_id, is_primary)
  select u.id, 'c0000000-0000-0000-0000-000000000006', true
  from auth.users u where u.email in ('comprador@compraflow.local','coordenador@compraflow.local')
  on conflict do nothing;
end $$;

-- ---------- Demandas demo ----------
do $$
declare v_req uuid := (select id from auth.users where email='requisitante@compraflow.local');
        v_buy uuid := (select id from auth.users where email='comprador@compraflow.local');
        v_id1 uuid; v_id2 uuid; v_id3 uuid; v_round uuid; v_q uuid;
        v_it1 uuid; v_it2 uuid;
begin
  if v_req is null then return; end if;

  -- 1) Rascunho
  insert into public.purchase_requests (company_id, business_unit_id, department_id, cost_center_id, category_id, title, purchase_type, priority, status, needed_at, justification, created_by)
  values ('a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000002','d0000000-0000-0000-0000-000000000001','e0000000-0000-0000-0000-000000000001',
          'Compra de material de escritório','PRODUTO','NORMAL','RASCUNHO', current_date + 15, 'Reposição trimestral', v_req)
  returning id into v_id1;
  insert into public.purchase_request_items (request_id, line_no, description, quantity, unit_price)
  values (v_id1,1,'Resma de papel A4 (caixa c/ 10)',20,28.90),(v_id1,2,'Caneta esferográfica azul (cx 50)',10,42.00);

  -- 2) Enviada
  insert into public.purchase_requests (company_id, business_unit_id, department_id, cost_center_id, category_id, title, purchase_type, priority, status, needed_at, justification, created_by)
  values ('a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000004','d0000000-0000-0000-0000-000000000003','e0000000-0000-0000-0000-000000000002',
          'Notebooks para equipe de TI','PRODUTO','ALTA','ENVIADA', current_date + 30, 'Substituição de equipamentos obsoletos', v_req)
  returning id into v_id2;
  insert into public.purchase_request_items (request_id, line_no, description, quantity, unit_price)
  values (v_id2,1,'Notebook i5 16GB 512GB SSD',5,4200.00);
  insert into public.status_history (request_id, from_status, to_status, comment, changed_by)
  values (v_id2,'RASCUNHO','ENVIADA','Enviada para compras', v_req);

  -- 3) Em cotação COM 3 propostas (destrava o mapa comparativo)
  insert into public.purchase_requests (company_id, business_unit_id, department_id, cost_center_id, category_id, title, purchase_type, priority, status, needed_at, justification, created_by, assigned_buyer_id)
  values ('a0000000-0000-0000-0000-000000000001','b0000000-0000-0000-0000-000000000001','c0000000-0000-0000-0000-000000000003','d0000000-0000-0000-0000-000000000002','e0000000-0000-0000-0000-000000000003',
          'Manutenção preventiva de ar-condicionado','SERVICO','NORMAL','COTACOES_RECEBIDAS', current_date + 20, 'Contrato semestral', v_req, v_buy)
  returning id into v_id3;
  insert into public.purchase_request_items (request_id, line_no, description, quantity, unit_price)
  values (v_id3,1,'Manutenção preventiva (por unidade)',12,180.00) returning id into v_it1;
  insert into public.purchase_request_items (request_id, line_no, description, quantity, unit_price)
  values (v_id3,2,'Troca de filtro',12,45.00) returning id into v_it2;

  insert into public.status_history (request_id, from_status, to_status, changed_by) values
    (v_id3,'RASCUNHO','ENVIADA', v_req),(v_id3,'ENVIADA','EM_ANALISE_POR_COMPRAS', v_buy),
    (v_id3,'EM_ANALISE_POR_COMPRAS','EM_COTACAO', v_buy),(v_id3,'EM_COTACAO','COTACOES_RECEBIDAS', v_buy);

  insert into public.sourcing_rounds (request_id, round_no, deadline_at, created_by)
  values (v_id3, 1, now() + interval '7 days', v_buy) returning id into v_round;

  insert into public.sourcing_suppliers (round_id, supplier_id, status) values
    (v_round,'f0000000-0000-0000-0000-000000000003','RESPONDIDO'),
    (v_round,'f0000000-0000-0000-0000-000000000001','RESPONDIDO'),
    (v_round,'f0000000-0000-0000-0000-000000000005','RESPONDIDO');

  -- Proposta A (Gamma) — menor preço unitário no item 1
  insert into public.supplier_quotes (round_id, supplier_id, reference, quote_date, valid_until, payment_terms, delivery_days, freight_amount, status, created_by)
  values (v_round,'f0000000-0000-0000-0000-000000000003','PROP-2026-A', current_date, current_date+30,'À vista',10, 0,'VALIDA', v_buy) returning id into v_q;
  insert into public.supplier_quote_items (quote_id, request_item_id, quantity_offered, unit_price, delivery_days, technical_fit)
  values (v_q, v_it1, 12, 165.00, 10, 'ATENDE'), (v_q, v_it2, 12, 49.00, 10, 'ATENDE');

  -- Proposta B (Alfa) — frete maior, prazo melhor
  insert into public.supplier_quotes (round_id, supplier_id, reference, quote_date, valid_until, payment_terms, delivery_days, freight_amount, status, created_by)
  values (v_round,'f0000000-0000-0000-0000-000000000001','PROP-2026-B', current_date, current_date+20,'30 dias',5, 180.00,'VALIDA', v_buy) returning id into v_q;
  insert into public.supplier_quote_items (quote_id, request_item_id, quantity_offered, unit_price, delivery_days, technical_fit)
  values (v_q, v_it1, 12, 172.00, 5, 'ATENDE'), (v_q, v_it2, 12, 42.00, 5, 'ATENDE');

  -- Proposta C (Epsilon) — atende parcialmente
  insert into public.supplier_quotes (round_id, supplier_id, reference, quote_date, valid_until, payment_terms, delivery_days, freight_amount, status, created_by)
  values (v_round,'f0000000-0000-0000-0000-000000000005','PROP-2026-C', current_date, current_date+15,'21 dias',12, 90.00,'VALIDA', v_buy) returning id into v_q;
  insert into public.supplier_quote_items (quote_id, request_item_id, quantity_offered, unit_price, delivery_days, technical_fit)
  values (v_q, v_it1, 12, 158.00, 12, 'ATENDE_PARCIALMENTE'), (v_q, v_it2, 12, 55.00, 12, 'ATENDE');
end $$;
