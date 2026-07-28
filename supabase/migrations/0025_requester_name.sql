-- 0025 — Nome do solicitante (pessoa que fez o pedido), texto livre na demanda.
-- Não altera RLS: continua sendo o dono quem edita enquanto RASCUNHO.

alter table public.purchase_requests
  add column if not exists requester_name text;
