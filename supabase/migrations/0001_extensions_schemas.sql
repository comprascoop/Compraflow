-- 0001 — Extensões e schemas
-- Idempotente. Aplicar em ordem numérica.

create extension if not exists pgcrypto;   -- gen_random_uuid(), digest() p/ hash de token
create extension if not exists citext;     -- e-mails case-insensitive

-- schema de funções auxiliares (helpers de RLS/domínio). Nunca exposto via API.
create schema if not exists app;

-- schema analytics (estrela) — populado em etapa posterior via views/materialized views.
create schema if not exists analytics;

comment on schema app is 'Funções de domínio e helpers de segurança (SECURITY DEFINER). Não expor no PostgREST.';
comment on schema analytics is 'Modelo estrela (dims/facts) para dashboards. Somente leitura.';
