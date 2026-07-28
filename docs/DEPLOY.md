# Passo a passo — Supabase + Vercel

Guia completo, do zero até a aplicação no ar. Nenhum passo exige Docker.

---

# PARTE 1 — Banco de dados no Supabase

## 1.1 Criar o projeto

1. Acesse **https://supabase.com** → *Sign in* (dá para entrar com a conta do GitHub).
2. **New project**.
3. Preencha:
   - **Name**: `compraflow`
   - **Database Password**: gere uma senha forte e **guarde num gerenciador de senhas**.
     Você vai precisar dela se um dia conectar por `psql`. Ela não aparece de novo.
   - **Region**: `South America (São Paulo)` — menor latência para o Brasil.
   - **Pricing Plan**: Free.
4. **Create new project** e espere ~2 minutos até o provisionamento terminar.

## 1.2 Rodar as migrations

1. Menu lateral → **SQL Editor** → botão **New query**.
2. Abra o arquivo do seu repositório: **`supabase/_TUDO_EM_UM.sql`**.
3. Copie **todo** o conteúdo (são ~3.000 linhas) e cole no editor.
4. Clique em **Run** (ou `Ctrl+Enter`).
5. Aguarde. O esperado é **"Success. No rows returned"**.

> Se aparecerem mensagens amarelas de `NOTICE: ... already exists, skipping`, está **certo**.
> As migrations são idempotentes de propósito — dá para rodar de novo sem quebrar nada.

### Conferir se deu certo

Nova query, cole e rode:

```sql
select
  (select count(*) from information_schema.tables
    where table_schema = 'public' and table_type = 'BASE TABLE')      as tabelas,
  (select count(*) from pg_tables t join pg_class c on c.relname = t.tablename
    where t.schemaname = 'public' and c.relrowsecurity)               as tabelas_com_rls,
  (select count(*) from information_schema.routines
    where routine_schema = 'app')                                     as funcoes_app,
  (select count(*) from storage.buckets)                              as buckets;
```

Você deve ver algo próximo de: **43 tabelas**, **43 com RLS**, **~20 funções** e **5 buckets**.
Se `tabelas_com_rls` vier bem menor que `tabelas`, algo não rodou — role o log do editor
procurando a primeira linha em vermelho.

## 1.3 Expor o schema `app` ⚠️ PASSO CRÍTICO

Sem isto, **nada funciona**: enviar demanda, aprovar, gerar pedido — tudo passa por RPCs
que vivem no schema `app`, e o Supabase só expõe na API os schemas que você autorizar.

1. Menu lateral → **Settings** (engrenagem) → **API**.
2. Procure **Exposed schemas** (em algumas versões fica em *Data API*).
3. O campo mostra `public, graphql_public`. Adicione `app`, ficando:
   ```
   public, graphql_public, app
   ```
4. **Save**.

> Sintoma de quem esqueceu deste passo: a tela abre normalmente, mas ao clicar em "Enviar"
> aparece um erro tipo `function public.fn_transition_request does not exist` ou
> `schema "app" does not exist`. É sempre isto.

## 1.4 Rodar o seed (dados de demonstração)

1. **SQL Editor** → **New query**.
2. Cole todo o conteúdo de **`supabase/seed.sql`** → **Run**.

Isso cria: 1 empresa, 3 unidades, 6 setores, 4 centros de custo, 4 categorias,
7 unidades de medida, 5 fornecedores, a matriz de aprovação, **7 usuários de teste**
e 3 demandas — uma delas já com 3 propostas para você ver o mapa comparativo funcionando.

### Conferir

```sql
select
  (select count(*) from auth.users)               as usuarios,
  (select count(*) from public.suppliers)         as fornecedores,
  (select count(*) from public.purchase_requests) as demandas,
  (select count(*) from public.supplier_quotes)   as propostas,
  (select count(*) from public.approval_rules)    as regras_aprovacao;
```

Esperado: **7, 5, 3, 3, 2**.

> ⚠️ O seed cria usuários com a senha `Compra@123`. Isso é **só para validação**.
> Antes de usar pra valer, veja a seção "Antes de ir para produção" no fim deste guia.

## 1.5 Pegar as chaves

**Settings → API**. Anote os três valores:

| Onde aparece | Nome que vamos usar | Pode ir pro browser? |
|---|---|---|
| **Project URL** | `NEXT_PUBLIC_SUPABASE_URL` | sim |
| **Project API keys → anon / public** | `NEXT_PUBLIC_SUPABASE_ANON_KEY` | sim |
| **Project API keys → service_role** | `SUPABASE_SERVICE_ROLE_KEY` | **NÃO** |

> A `service_role` **ignora todas as políticas de RLS**. Quem tiver essa chave lê e escreve
> qualquer linha de qualquer tabela. Ela só é usada no servidor (nos Route Handlers do portal
> do fornecedor). Nunca a coloque em variável com prefixo `NEXT_PUBLIC_`, nunca a comite,
> nunca a cole em chat ou issue.

---

# PARTE 2 — Rodar na sua máquina (recomendado antes da Vercel)

Vale testar local primeiro: se algo estiver errado, o erro aparece na hora, não num log de deploy.

```bash
cd web
cp .env.local.example .env.local
```

Edite o `.env.local` com as chaves do passo 1.5:

```
NEXT_PUBLIC_SUPABASE_URL=https://xxxxxxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOi...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOi...
```

```bash
npm install
npm run dev
```

Abra **http://localhost:3000** → entre com `comprador@compraflow.local` / `Compra@123`.

Se logar e ver o painel com dados, o banco está certo e você pode subir pra Vercel.

---

# PARTE 3 — Deploy na Vercel

## 3.1 Importar o projeto

1. Acesse **https://vercel.com** → entre com a conta do GitHub.
2. **Add New…** → **Project**.
3. Encontre o repositório do CompraFlow → **Import**.

## 3.2 Configurar o build

O `vercel.json` na raiz já aponta o build para a pasta `web/`. Então:

- **Root Directory**: deixe **na raiz** (não selecione `web`).
- **Framework Preset**: Next.js (detecta sozinho).
- **Build Command / Output Directory**: não mexa — vêm do `vercel.json`.

> Alternativa: se preferir, defina **Root Directory = `web`** e **apague o `vercel.json`**.
> As duas formas funcionam; o que não pode é misturar (root em `web` + `vercel.json` mandando
> entrar em `web` de novo → erro de "diretório não encontrado").

## 3.3 Cadastrar as variáveis de ambiente

Ainda na tela de import, abra **Environment Variables** e cadastre as três, uma por vez.
Marque os três ambientes (Production, Preview, Development) em cada:

| Key | Value |
|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | sua Project URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | sua anon key |
| `SUPABASE_SERVICE_ROLE_KEY` | sua service_role key |

Confira o nome da terceira: **sem** `NEXT_PUBLIC_`. Um prefixo errado aqui embute a chave
no JavaScript que vai pro navegador de qualquer visitante.

## 3.4 Deploy

Clique em **Deploy** e espere ~2 minutos. No fim você recebe uma URL do tipo
`https://compraflow-xxxx.vercel.app`.

## 3.5 Autorizar a URL no Supabase ⚠️

Voltando ao Supabase:

1. **Authentication** → **URL Configuration**.
2. **Site URL**: `https://sua-url.vercel.app`
3. **Redirect URLs**: adicione `https://sua-url.vercel.app/**`
4. **Save**.

> Sem isso, o login pode até funcionar, mas recuperação de senha e confirmação de e-mail
> vão redirecionar para `localhost:3000`.

## 3.6 Testar em produção

Abra a URL da Vercel e siga este roteiro:

1. Entre como `requisitante@compraflow.local` → **Demandas** → abra o rascunho → **Enviar**.
   *Se der erro de função/schema, volte ao passo 1.3.*
2. Saia. Entre como `comprador@compraflow.local` → **Fila de compras** → abra a demanda de
   ar-condicionado → **Mapa comparativo**. Devem aparecer 3 propostas com os totais calculados.
3. Escolha um fornecedor por item → escreva a justificativa → **Recomendar e enviar para aprovação**.
4. Entre como `diretor@compraflow.local` → **Aprovações** → **Aprovar**.
5. Volte como comprador → na demanda → **Gerar pedido de compra**.

### Testar o portal do fornecedor

O portal é a parte que usa a `service_role`, então é o melhor teste de que a variável do
servidor foi cadastrada certo.

1. Logado como comprador, abra o **Workspace de cotação** de uma demanda e crie uma rodada
   (se ainda não houver).
2. Pegue o `round_id` — no SQL Editor:
   ```sql
   select sr.id as round_id, r.number, r.title
   from public.sourcing_rounds sr
   join public.purchase_requests r on r.id = sr.request_id;
   ```
3. Pegue um `supplier_id`:
   ```sql
   select id, legal_name from public.suppliers limit 5;
   ```
4. No navegador, **já logado como comprador**, abra o console (F12) e rode:
   ```js
   const r = await fetch('/api/convites/gerar', {
     method: 'POST',
     headers: { 'Content-Type': 'application/json' },
     body: JSON.stringify({
       round_id: 'COLE_O_ROUND_ID',
       suppliers: [{ supplier_id: 'COLE_O_SUPPLIER_ID', email: 'contato@fornecedor.com' }]
     })
   });
   console.log(await r.json());
   ```
5. Copie a `url` retornada e abra **numa janela anônima** (para provar que não depende de login).
6. Confirme participação, preencha os preços, envie. Você recebe um **protocolo**.
7. Volte ao mapa comparativo como comprador: a proposta já está lá.

> Se o passo 4 devolver *"SUPABASE_SERVICE_ROLE_KEY não configurada no servidor"*,
> a variável não foi cadastrada na Vercel (ou foi cadastrada só em Preview).
> Cadastre e **refaça o deploy** — variáveis novas só valem em builds novos.

---

# Problemas comuns

| Sintoma | Causa | Solução |
|---|---|---|
| `schema "app" does not exist` / `function ... does not exist` | schema `app` não exposto | Passo 1.3 |
| Login funciona mas as listas vêm vazias | usuário sem papel ou sem setor | Rode o seed (1.4) ou atribua papéis (abaixo) |
| `SUPABASE_SERVICE_ROLE_KEY não configurada` | variável ausente na Vercel | Passo 3.3 + **redeploy** |
| Build falha com "No Next.js version detected" | Root Directory errado | Passo 3.2 |
| Redireciona pro `localhost` após login | URL não autorizada | Passo 3.5 |
| `permission denied for schema app` | faltou o `grant` (rodou só parte do SQL) | Rode o `_TUDO_EM_UM.sql` inteiro de novo |
| Envio de proposta do fornecedor falha com `function digest does not exist` | `search_path` sem `extensions` | Já corrigido na 0020 — confirme que está usando a versão atual do arquivo |

---

# Antes de ir para produção

Faça isto **antes** de cadastrar qualquer dado real:

1. **Apague os usuários de demonstração:**
   ```sql
   delete from auth.users where email like '%@compraflow.local';
   ```
2. **Crie os usuários reais** em *Authentication → Users → Add user* (marque
   *Auto Confirm User*).
3. **Atribua papéis** a cada um:
   ```sql
   -- papéis disponíveis: ADMINISTRADOR, REQUISITANTE, GESTOR_SETOR, COMPRADOR,
   -- COORDENADOR_COMPRAS, APROVADOR_FINANCEIRO, AUDITOR
   insert into public.user_roles (user_id, role_id)
   select u.id, r.id
   from auth.users u, public.roles r
   where u.email = 'pessoa@suaempresa.com.br' and r.code = 'COMPRADOR';
   ```
4. **Vincule ao setor** (obrigatório para requisitante e gestor):
   ```sql
   insert into public.user_departments (user_id, department_id, is_manager, is_primary)
   select u.id, d.id, false, true
   from auth.users u, public.departments d
   where u.email = 'pessoa@suaempresa.com.br' and d.name = 'Operações';
   ```
   Para gestor que aprova o setor, use `is_manager = true`.
5. **Substitua os dados de exemplo** (empresa, setores, centros de custo, categorias,
   fornecedores) pelos reais.
6. **Revise a matriz de aprovação** — o seed vem com uma faixa até R$ 5.000 (gestor) e
   outra acima (diretor financeiro):
   ```sql
   select id, name, min_amount, max_amount from public.approval_rules order by priority_order;
   ```
7. **Ative backups** — no plano Free o Supabase mantém backup diário por 7 dias.
   Para produção séria, avalie o plano Pro (PITR).
8. **Confirme que o `.env.local` não foi commitado**: `git log --all -- web/.env.local`
   não deve retornar nada. Se retornar, **rotacione as chaves** no Supabase imediatamente.
