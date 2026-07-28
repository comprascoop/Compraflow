# CompraFlow

Sistema de gestão de compras corporativas — Next.js + Supabase.
Máquina de estados no banco, RLS em todas as tabelas, auditoria imutável, matriz de aprovação,
mapa comparativo e portal externo de cotação para fornecedores.

---

> 📘 **Passo a passo detalhado de deploy: [`docs/DEPLOY.md`](docs/DEPLOY.md)**

## Subir sem Docker (GitHub + Vercel + Supabase Cloud)

### 1. Criar o banco (navegador, ~3 min)

1. Crie um projeto grátis em https://supabase.com → anote a senha do banco.
2. No painel do projeto: **SQL Editor** → **New query**.
3. Cole o conteúdo de **`supabase/_TUDO_EM_UM.sql`** (todas as 22 migrations na ordem) → **Run**.
4. Nova query → cole **`supabase/seed.sql`** → **Run**. Isso cria usuários demo e dados de exemplo.
5. **Settings → API → Exposed schemas**: adicione `app` na lista (fica `public, graphql_public, app`).
   Sem isso as RPCs de transição de estado não funcionam.
6. **Settings → API**: copie a `URL`, a `anon key` e a `service_role key`.

> Se preferir CLI (também sem Docker): `supabase link --project-ref SEU_REF && supabase db push`.

### 2. Rodar local

```bash
cd web
cp .env.local.example .env.local     # preencha com as 3 chaves do passo 1.6
npm install
npm run dev                          # http://localhost:3000
```

### 3. Publicar na Vercel

1. Suba o repo no GitHub.
2. Vercel → **Add New Project** → importe o repo.
3. **Root Directory**: deixe a raiz (o `vercel.json` já aponta o build para `web/`).
4. Em **Environment Variables**, cadastre as três:

| Variável | Valor | Exposta ao browser? |
|---|---|---|
| `NEXT_PUBLIC_SUPABASE_URL` | URL do projeto | sim |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | anon key | sim |
| `SUPABASE_SERVICE_ROLE_KEY` | service role key | **NÃO** — sem prefixo `NEXT_PUBLIC_` |

5. Deploy. Depois, em **Supabase → Authentication → URL Configuration**, ponha a URL da Vercel
   em *Site URL* e em *Redirect URLs*.

> ⚠️ A `service_role key` ignora RLS. Ela só é usada nos Route Handlers do portal
> (`src/app/api/portal/*`), que rodam no servidor. Nunca a prefixe com `NEXT_PUBLIC_`.

---

## Usuários demo (senha: `Compra@123`)

| E-mail | Papel |
|---|---|
| `requisitante@compraflow.local` | Requisitante |
| `comprador@compraflow.local` | Comprador |
| `coordenador@compraflow.local` | Coordenador + Comprador |
| `gestor@compraflow.local` | Gestor do setor |
| `diretor@compraflow.local` | Aprovador financeiro |
| `admin@compraflow.local` | Administrador |
| `auditor@compraflow.local` | Auditor |

**Antes de ir para produção:** apague esses usuários e crie os reais pelo painel Auth.
O `seed.sql` é só para validação.

---

## Roteiro de validação

1. **Requisitante** → *Demandas* → abre o rascunho → **Enviar**.
2. **Comprador** → *Fila* → abre a demanda de ar-condicionado → **Workspace de cotação**.
3. Convide fornecedores e registre uma proposta → veja o total ser recalculado pelo banco.
4. **Mapa comparativo** → escolha fornecedores diferentes por item → recomende e envie para aprovação.
5. **Diretor** → *Aprovações* → aprovar/rejeitar.
6. **Comprador** → demanda aprovada → **Gerar pedido de compra**.

### Portal do fornecedor
O convite gera um link individual em `/fornecedor/convite/[token]`. Para testar sem e-mail,
chame o endpoint autenticado como comprador — ele devolve os links (o token aparece **uma vez**):

```bash
curl -X POST http://localhost:3000/api/convites/gerar \
  -H "Content-Type: application/json" \
  -d '{"round_id":"<id da rodada>","suppliers":[{"supplier_id":"<id>","email":"contato@fornecedor.com"}]}'
```

Abra o link retornado em uma aba anônima: o fornecedor confirma participação, preenche preços
e envia. A proposta cai automaticamente no mapa comparativo do comprador.

---

## O que é garantido pelo banco (não dá para burlar pelo front)

- **Status** só muda por `app.fn_transition_request()` — valida papel, setor, campos e justificativa.
- **Totais** de item, proposta, recomendação e pedido são calculados por trigger/coluna gerada.
- **Custo total** = subtotal − desconto + impostos + frete + seguro (fórmula única, testada).
- **Decisões de aprovação** são *append-only*: não existe policy de UPDATE/DELETE.
- **Alterar proposta** após início da aprovação **invalida** as aprovações e registra o motivo.
- **Escolher fora do menor preço** exige justificativa (check constraint).
- **Token do portal** é guardado só como hash SHA-256; o original nunca vai ao banco.
- **Fornecedor não cota item de outra demanda** — validado dentro da função de submissão.
- **Dados bancários** ficam em tabela isolada, visível só a admin/coordenador.

## Estrutura

```
compraflow/
├── supabase/
│   ├── migrations/          # 22 migrations idempotentes, em ordem
│   ├── _TUDO_EM_UM.sql      # todas concatenadas (para colar no SQL Editor)
│   ├── seed.sql             # usuários demo, matriz de aprovação, cotações
│   └── config.toml          # expõe o schema `app` (necessário para as RPCs)
├── web/                     # Next.js (App Router, TS strict)
│   ├── src/app/(app)/       # área interna autenticada
│   ├── src/app/fornecedor/  # portal externo (sem sessão, acesso por token)
│   ├── src/app/api/         # Route Handlers (service role, só no servidor)
│   └── src/services/        # camada de dados
├── vercel.json
└── docs/ARQUITETURA.md
```

## Migrations

| Arquivo | Conteúdo |
|---|---|
| 0001–0007 | schemas, enums, organização, RBAC, **helpers de RLS**, auditoria |
| 0008–0011 | catálogos, demandas, itens, **máquina de estados**, RLS |
| 0012–0014 | fornecedores (CNPJ validado no banco), documentos, homologação |
| 0015–0016 | cotação, propostas, **mapa comparativo**, recomendação por item |
| 0017 | **matriz de aprovação**, decisões imutáveis, invalidação |
| 0018–0019 | pedidos, recebimento, anexos, RLS operacional, buckets privados |
| 0020 | **portal do fornecedor** (convites, tokens com hash, submissão, isolamento) |
| 0021 | **analytics** (esquema estrela: dimensões e fatos) |
| 0022 | notificações automáticas por trigger |

### Materializar o analytics (quando o volume crescer)

As views em `analytics.*` leem direto do operacional. Para materializar:
troque `create or replace view` por `create materialized view` na 0021 e agende o refresh
(`select cron.schedule('refresh_analytics','0 * * * *','refresh materialized view analytics.fact_purchase_request')`,
com a extensão `pg_cron` habilitada no Supabase).

## O que ainda não está implementado

- Envio real de e-mail dos convites (o link é gerado; falta plugar Resend/SendGrid)
- OTP por e-mail para cotações de alto valor (tabela e campos prontos: `otp_hash`, `otp_expires_at`)
- Importação/exportação de propostas por planilha Excel
- Exportação do mapa comparativo para PDF
- Leilão reverso (fora do MVP por decisão de escopo)
- Suíte de testes automatizados (a validação hoje é manual, pelo roteiro acima)
- Telas de administração para matriz de aprovação e numerações (hoje via Studio)
