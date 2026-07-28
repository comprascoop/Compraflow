-- 0007 — RLS do núcleo (org + RBAC + auditoria)
-- Princípio: deny by default. Habilita RLS e cria policies explícitas.
-- Sem policy = nenhum acesso (exceto owner/service_role, que ignoram RLS).

alter table public.companies       enable row level security;
alter table public.business_units  enable row level security;
alter table public.departments     enable row level security;
alter table public.cost_centers    enable row level security;
alter table public.profiles        enable row level security;
alter table public.roles           enable row level security;
alter table public.permissions     enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles      enable row level security;
alter table public.user_departments enable row level security;
alter table public.audit_logs      enable row level security;

-- ---------- Cadastros organizacionais ----------
-- Leitura: qualquer autenticado (estrutura da empresa não é sigilosa e é referência de formulários).
-- Escrita: só ADMIN.
do $$
declare t text;
begin
  foreach t in array array['companies','business_units','departments','cost_centers'] loop
    execute format('drop policy if exists sel_%1$s on public.%1$s', t);
    execute format(
      'create policy sel_%1$s on public.%1$s for select to authenticated
       using (deleted_at is null or app.is_admin())', t);

    execute format('drop policy if exists ins_%1$s on public.%1$s', t);
    execute format(
      'create policy ins_%1$s on public.%1$s for insert to authenticated
       with check (app.is_admin())', t);

    execute format('drop policy if exists upd_%1$s on public.%1$s', t);
    execute format(
      'create policy upd_%1$s on public.%1$s for update to authenticated
       using (app.is_admin()) with check (app.is_admin())', t);
    -- Sem policy de DELETE => exclusão física bloqueada. Usar soft delete (deleted_at).
  end loop;
end $$;

-- ---------- profiles ----------
drop policy if exists sel_profiles on public.profiles;
create policy sel_profiles on public.profiles for select to authenticated
  using (id = auth.uid() or app.is_admin() or app.is_auditor());

drop policy if exists upd_profiles_self on public.profiles;
create policy upd_profiles_self on public.profiles for update to authenticated
  using (id = auth.uid() or app.is_admin())
  with check (id = auth.uid() or app.is_admin());

-- ---------- roles / permissions / role_permissions ----------
-- Leitura para autenticados (a UI precisa exibir nomes de papéis); escrita só ADMIN.
do $$
declare t text;
begin
  foreach t in array array['roles','permissions','role_permissions'] loop
    execute format('drop policy if exists sel_%1$s on public.%1$s', t);
    execute format('create policy sel_%1$s on public.%1$s for select to authenticated using (true)', t);
    execute format('drop policy if exists wr_%1$s on public.%1$s', t);
    execute format('create policy wr_%1$s on public.%1$s for all to authenticated
                    using (app.is_admin()) with check (app.is_admin())', t);
  end loop;
end $$;

-- ---------- user_roles ----------
-- Usuário vê os próprios papéis; ADMIN vê/gerencia todos.
drop policy if exists sel_user_roles on public.user_roles;
create policy sel_user_roles on public.user_roles for select to authenticated
  using (user_id = auth.uid() or app.is_admin() or app.is_auditor());

drop policy if exists wr_user_roles on public.user_roles;
create policy wr_user_roles on public.user_roles for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- ---------- user_departments ----------
drop policy if exists sel_user_departments on public.user_departments;
create policy sel_user_departments on public.user_departments for select to authenticated
  using (user_id = auth.uid() or app.is_admin() or app.is_auditor());

drop policy if exists wr_user_departments on public.user_departments;
create policy wr_user_departments on public.user_departments for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- ---------- audit_logs ----------
-- Leitura: ADMIN e AUDITOR. Escrita: NENHUMA via API (só o trigger DEFINER insere).
-- Sem policy de insert/update/delete => imutável do ponto de vista do usuário autenticado.
drop policy if exists sel_audit on public.audit_logs;
create policy sel_audit on public.audit_logs for select to authenticated
  using (app.is_admin() or app.is_auditor());
