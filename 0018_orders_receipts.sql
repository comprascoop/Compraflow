-- 0002 — Tipos enumerados
-- Padrão idempotente: cria o type e ignora se já existe.

do $$ begin
  create type public.priority as enum ('BAIXA','NORMAL','ALTA','CRITICA');
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.purchase_type as enum
    ('PRODUTO','SERVICO','CONTRATO','RENOVACAO','COMPRA_EMERGENCIAL');
exception when duplicate_object then null; end $$;

-- Máquina de estados da demanda (seção 5)
do $$ begin
  create type public.request_status as enum (
    'RASCUNHO','ENVIADA','AGUARDANDO_APROVACAO_DO_SETOR','EM_ANALISE_POR_COMPRAS',
    'AGUARDANDO_INFORMACOES','EM_COTACAO','COTACOES_RECEBIDAS','EM_ANALISE_DE_COTACOES',
    'AGUARDANDO_APROVACAO_TECNICA','AGUARDANDO_APROVACAO_FINANCEIRA','APROVADA','REJEITADA',
    'PEDIDO_EMITIDO','EM_ENTREGA','RECEBIDA','ENCERRADA','CANCELADA'
  );
exception when duplicate_object then null; end $$;

-- Estados do pedido (seção 14)
do $$ begin
  create type public.purchase_order_status as enum (
    'RASCUNHO','EMITIDO','ENVIADO','CONFIRMADO_PELO_FORNECEDOR',
    'PARCIALMENTE_RECEBIDO','RECEBIDO','CANCELADO','ENCERRADO'
  );
exception when duplicate_object then null; end $$;

-- Status do fornecedor (seção 16)
do $$ begin
  create type public.supplier_status as enum (
    'EM_CADASTRO','PENDENTE_DE_HOMOLOGACAO','HOMOLOGADO',
    'HOMOLOGADO_COM_RESTRICAO','BLOQUEADO','INATIVO'
  );
exception when duplicate_object then null; end $$;

-- Estados do convite do portal externo (portal seção 18)
do $$ begin
  create type public.invitation_status as enum (
    'RASCUNHO','AGUARDANDO_ENVIO','ENVIADO','ENTREGUE','EMAIL_FALHOU','ACESSADO',
    'PARTICIPACAO_CONFIRMADA','RECUSADO','PROPOSTA_EM_RASCUNHO','RESPONDIDO',
    'EXPIRADO','REVOGADO','CANCELADO'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type public.approval_decision as enum
    ('APROVADO','REJEITADO','AJUSTE_SOLICITADO','ENCAMINHADO');
exception when duplicate_object then null; end $$;
