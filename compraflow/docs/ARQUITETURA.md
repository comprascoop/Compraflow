# CompraFlow — Arquitetura

Este documento é o "passo 0" pedido na seção 34 do escopo: arquitetura, permissões,
tabelas, estratégia de RLS, fluxo da demanda e decisões de UX. Serve de contrato antes
de cada nova etapa de implementação.

## 1. Visão de módulos (diagrama textual)

```
                         ┌──────────────────────────────┐
                         │        Next.js (App Router)   │
                         │  ── app interno ──  ── portal ─│
                         │  /(app)             /fornecedor│
                         └───────────────┬──────────────-┘
                                         │ TanStack Query + camada services/
                                         │ (nunca Supabase espalhado em componente)
                                         ▼
        ┌──────────────────────────── Supabase ──────────────────────────────┐
        │                                                                     │
        │  Auth ──── profiles ──── RBAC (roles/permissions/user_roles)        │
        │                                    │                                │
        │  Postgres (public)                 │  helpers app.* (SECURITY DEF.) │
        │    org: companies>bu>dept>cc       │  → base de toda RLS            │
        │    demandas: purchase_requests ... │                                │
        │    cotação: sourcing_* / quotes    │  RPCs de transição de estado   │
        │    aprovação: approval_*           │  triggers de auditoria         │
        │    pedido/recebimento              │                                │
        │    portal externo: sourcing_invit* │                                │
        │                                    ▼                                │
        │  Storage (buckets privados)   analytics (dims/facts p/ dashboards)  │
        │  Edge Functions (ops privilegiadas: convite/OTP/e-mail/submissão)   │
        └─────────────────────────────────────────────────────────────────────┘
```

Regra estrutural: **o front nunca altera status nem valor aprovado diretamente**.
Toda transição de estado, recálculo de total e emissão de pedido passa por RPC no banco
ou Edge Function. O front dispara intenção, o banco decide e registra.

## 2. Modelo de permissões (RBAC + escopo)

- `roles` / `permissions` / `role_permissions`: catálogo.
- `user_roles`: N:N — um usuário tem vários papéis.
- `user_departments`: escopo por setor; `is_manager = true` marca o gestor aprovador.
- Autorização real = **RLS no Postgres**. Esconder botão no front é só cosmético.

Papéis de sistema: `ADMINISTRADOR`, `REQUISITANTE`, `GESTOR_SETOR`, `COMPRADOR`,
`COORDENADOR_COMPRAS`, `APROVADOR_FINANCEIRO`, `AUDITOR`.

## 3. Estratégia de RLS (ponto crítico)

1. **Deny by default**: RLS ligado em toda tabela exposta; sem policy = sem acesso.
2. **Helpers `SECURITY DEFINER`** no schema `app` (`has_role`, `is_admin`, `in_department`,
   `manages_department`, `user_departments`). Rodam como owner e **bypassam a RLS das
   tabelas de papel** → nenhuma policy que os chame entra em recursão. Esse é o motivo de
   não colocarmos a lógica de papéis inline nas policies.
3. `search_path` travado em toda função definer (`app, public, pg_temp`).
4. `service_role` só existe no servidor (Edge Functions). **Nunca no navegador.**
5. Arquivos herdam a permissão do registro-pai (aplicado nas policies de Storage, etapa 21).

## 4. Máquina de estados da demanda

Estados no enum `request_status` (17 estados). A transição não é livre: será uma tabela
`request_status_transitions` (de → para → papel exigido) + RPC `fn_transition_request()`
que valida papel, setor, campos obrigatórios, existência de cotações e aprovações, e grava
em `status_history` + `audit_logs`. O front chama a RPC; nunca faz `update status`.

Caminho feliz:
`RASCUNHO → ENVIADA → [AGUARDANDO_APROVACAO_DO_SETOR] → EM_ANALISE_POR_COMPRAS →
EM_COTACAO → COTACOES_RECEBIDAS → EM_ANALISE_DE_COTACOES → AGUARDANDO_APROVACAO_FINANCEIRA →
APROVADA → PEDIDO_EMITIDO → EM_ENTREGA → RECEBIDA → ENCERRADA`.
Ramais: `AGUARDANDO_INFORMACOES`, `REJEITADA`, `CANCELADA`.

## 5. Decisões de UX

- Duas cascas separadas: app interno (sidebar densa, alta densidade) × portal do fornecedor
  (`/fornecedor/*`, navegação linear por etapas, sem sidebar admin). Não compartilham sessão.
- Chips de status consistentes por enum; timeline por processo; tabelas com filtros/paginação
  **no servidor**; skeleton loading; empty states úteis; confirmação em ações destrutivas.
- Mobile-first na caixa de aprovações do diretor.

## 6. Convenções de banco

- PK `uuid` (`gen_random_uuid()`); dinheiro `numeric(18,2)`; quantidade `numeric(18,4)`;
  datas `timestamptz`; JSONB só com justificativa.
- Cadastros: soft delete (`deleted_at`). Transacionais: **sem delete físico** (garantido por
  ausência de policy de DELETE +, nas transacionais, revogação explícita).
- Colunas de auditoria: `created_at/updated_at/created_by/updated_by`; trigger `tg_touch`
  e `tg_audit` anexados por tabela.

## 7. Roadmap (ordem 34 do escopo) — status

| Etapa | Escopo | Status |
|------:|--------|--------|
| 1–4 | Projeto, auth, banco operacional, RLS | **feito** (0001–0019) |
| 5 | Administração | parcial (homologação em tela; resto via Studio) |
| 6–8 | Demandas, fila, fornecedores | **feito** |
| 9–10 | Cotação + mapa comparativo | **feito** |
| 11 | Aprovações (matriz) | **feito** |
| 12–13 | Pedidos + recebimento | **feito** |
| 14 | Dashboards e analytics | **feito** (0021: esquema estrela em views) |
| 15–16 | Auditoria + notificações | **feito** (0022: triggers) |
| 17 | Testes + documentação | docs feitas; testes automatizados pendentes |
| — | Portal externo do fornecedor | **feito** (0020 + /fornecedor + Route Handlers) | pendente | pendente (depende de 9–10) |

## 8. Decisões arquiteturais (ADRs resumidos)

- **ADR-01**: transições de estado só via RPC no banco (integridade > conveniência do front).
- **ADR-02**: RLS com helpers `SECURITY DEFINER` para evitar recursão de policy.
- **ADR-03**: papéis em tabela (não enum) porque admin gerencia papéis/permissões em runtime.
- **ADR-04**: auditoria por trigger, imutável via RLS (sem insert/update/delete pela API).
- **ADR-05**: analytics em schema próprio via views/materialized views (sem duplicar dado).

## 9. Melhorias futuras

Leilão reverso; antivírus em upload; portal externo com conta recorrente; i18n;
particionamento de `audit_logs` por período; materialized views agendadas (pg_cron).
