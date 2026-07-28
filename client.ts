"use client";
import { useState } from "react";
import { useQuery, useQueryClient, useMutation } from "@tanstack/react-query";
import { listSuppliers, setSupplierStatus } from "@/services/suppliers";
import { getBusinessUnits, getCompanies, createBusinessUnit, listUsersWithUnits, setUserUnits } from "@/services/units";
import { SupplierBadge } from "@/components/status-badge";
import type { SupplierStatus } from "@/lib/types";

const TABS = ["Unidades de negócio", "Usuários e acessos", "Homologação"] as const;

export default function AdminPage() {
  const [tab, setTab] = useState<(typeof TABS)[number]>("Unidades de negócio");
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Administração</h1>
        <p className="text-sm text-slate-500">Unidades de negócio, acessos por unidade e homologação de fornecedores.</p>
      </div>
      <div className="flex gap-1 border-b">
        {TABS.map((t) => (
          <button key={t} onClick={() => setTab(t)}
            className={`px-4 py-2 text-sm ${tab === t ? "border-b-2 border-primary font-medium text-primary" : "text-slate-500"}`}>{t}</button>
        ))}
      </div>
      {tab === "Unidades de negócio" && <UnitsTab />}
      {tab === "Usuários e acessos" && <UsersTab />}
      {tab === "Homologação" && <HomologTab />}
    </div>
  );
}

function UnitsTab() {
  const qc = useQueryClient();
  const { data: units = [] } = useQuery({ queryKey: ["businessUnits"], queryFn: getBusinessUnits });
  const { data: companies = [] } = useQuery({ queryKey: ["companies"], queryFn: getCompanies });
  const [name, setName] = useState(""); const [code, setCode] = useState(""); const [company, setCompany] = useState("");
  const [error, setError] = useState<string | null>(null);
  const m = useMutation({
    mutationFn: () => createBusinessUnit(company || companies[0]?.id, name, code),
    onSuccess: () => { setName(""); setCode(""); setError(null); qc.invalidateQueries({ queryKey: ["businessUnits"] }); },
    onError: (e: Error) => setError(e.message),
  });
  return (
    <div className="space-y-5">
      <div className="card">
        <div className="border-b p-4"><h2 className="font-medium">Unidades cadastradas</h2></div>
        <div className="divide-y">
          {units.map((u) => (
            <div key={u.id} className="flex items-center justify-between p-4 text-sm">
              <span className="font-medium">{u.name}</span>
              <span className="text-slate-400">{u.code}</span>
            </div>
          ))}
          {units.length === 0 && <p className="p-6 text-sm text-slate-500">Nenhuma unidade ainda.</p>}
        </div>
      </div>
      <div className="card space-y-3 p-5">
        <h2 className="font-medium">Nova unidade de negócio</h2>
        <p className="text-sm text-slate-500">Ex.: Posto de Combustível, Loja Agropecuária, Supermercado.</p>
        <div className="grid gap-3 sm:grid-cols-3">
          {companies.length > 1 && (
            <div><label className="label">Empresa</label>
              <select className="input" value={company} onChange={(e) => setCompany(e.target.value)}>
                {companies.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
              </select></div>
          )}
          <div><label className="label">Nome</label>
            <input className="input" value={name} onChange={(e) => setName(e.target.value)} /></div>
          <div><label className="label">Código</label>
            <input className="input" value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} placeholder="POSTO" /></div>
        </div>
        {error && <p className="text-sm text-rose-600">{error}</p>}
        <button className="btn-primary" disabled={!name || m.isPending} onClick={() => m.mutate()}>Criar unidade</button>
      </div>
    </div>
  );
}

function UsersTab() {
  const qc = useQueryClient();
  const { data: users = [] } = useQuery({ queryKey: ["usersUnits"], queryFn: listUsersWithUnits });
  const { data: units = [] } = useQuery({ queryKey: ["businessUnits"], queryFn: getBusinessUnits });
  const m = useMutation({
    mutationFn: ({ userId, unitIds }: { userId: string; unitIds: string[] }) => setUserUnits(userId, unitIds),
    onSuccess: () => qc.invalidateQueries({ queryKey: ["usersUnits"] }),
  });
  return (
    <div className="card">
      <div className="border-b p-4">
        <h2 className="font-medium">Acesso por unidade</h2>
        <p className="text-sm text-slate-500">Marque quais unidades cada usuário pode enxergar.</p>
      </div>
      <div className="divide-y">
        {users.map((u) => {
          const current = u.user_business_units.map((x) => x.business_unit_id);
          return (
            <div key={u.id} className="p-4">
              <p className="text-sm font-medium">{u.full_name || u.email}</p>
              <p className="mb-2 text-xs text-slate-500">{u.email}</p>
              <div className="flex flex-wrap gap-2">
                {units.map((un) => {
                  const on = current.includes(un.id);
                  return (
                    <button key={un.id}
                      className={`rounded-full border px-3 py-1 text-xs ${on ? "border-primary bg-primary/10 text-primary" : "text-slate-600 hover:bg-muted"}`}
                      onClick={() => m.mutate({ userId: u.id,
                        unitIds: on ? current.filter((x) => x !== un.id) : [...current, un.id] })}>
                      {un.name}
                    </button>
                  );
                })}
              </div>
            </div>
          );
        })}
        {users.length === 0 && <p className="p-6 text-sm text-slate-500">Nenhum usuário.</p>}
      </div>
    </div>
  );
}

function HomologTab() {
  const qc = useQueryClient();
  const [reason, setReason] = useState(""); const [error, setError] = useState<string | null>(null);
  const { data: suppliers = [] } = useQuery({ queryKey: ["suppliers"], queryFn: () => listSuppliers() });
  const doStatus = useMutation({
    mutationFn: ({ id, status }: { id: string; status: SupplierStatus }) => setSupplierStatus(id, status, reason),
    onSuccess: () => { setReason(""); setError(null); qc.invalidateQueries({ queryKey: ["suppliers"] }); },
    onError: (e: Error) => setError(e.message),
  });
  const pending = suppliers.filter((s) => s.status === "PENDENTE_DE_HOMOLOGACAO" || s.status === "EM_CADASTRO");
  return (
    <div className="card">
      <div className="border-b p-4">
        <h2 className="font-medium">Fornecedores aguardando homologação ({pending.length})</h2>
        <p className="text-sm text-slate-500">Requer Administrador ou Coordenador de compras.</p>
      </div>
      {pending.length === 0 ? <p className="p-6 text-sm text-slate-500">Nenhum pendente.</p> : (
        <div className="divide-y">
          {pending.map((s) => (
            <div key={s.id} className="flex flex-wrap items-center justify-between gap-3 p-4">
              <div><p className="font-medium">{s.legal_name}</p><div className="mt-1"><SupplierBadge status={s.status} /></div></div>
              <div className="flex gap-2">
                <button className="btn-primary" disabled={doStatus.isPending} onClick={() => doStatus.mutate({ id: s.id, status: "HOMOLOGADO" })}>Homologar</button>
                <button className="btn-ghost text-rose-700" disabled={doStatus.isPending} onClick={() => doStatus.mutate({ id: s.id, status: "BLOQUEADO" })}>Bloquear</button>
              </div>
            </div>
          ))}
        </div>
      )}
      <div className="border-t p-4">
        <label className="label">Justificativa (obrigatória)</label>
        <input className="input" value={reason} onChange={(e) => setReason(e.target.value)} placeholder="Ex.: documentação completa" />
        {error && <p className="mt-2 text-sm text-rose-600">{error}</p>}
      </div>
    </div>
  );
}
