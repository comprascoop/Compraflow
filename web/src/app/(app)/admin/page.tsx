"use client";
import { useState } from "react";
import { useQuery, useQueryClient, useMutation } from "@tanstack/react-query";
import { listSuppliers, setSupplierStatus } from "@/services/suppliers";
import { getCategories, getCostCenters, getDepartments } from "@/services/meta";
import { SupplierBadge } from "@/components/status-badge";
import type { SupplierStatus } from "@/lib/types";

export default function AdminPage() {
  const qc = useQueryClient();
  const [reason, setReason] = useState("");
  const [error, setError] = useState<string | null>(null);
  const { data: suppliers = [] } = useQuery({ queryKey: ["suppliers"], queryFn: () => listSuppliers() });
  const { data: departments = [] } = useQuery({ queryKey: ["departments"], queryFn: getDepartments });
  const { data: costCenters = [] } = useQuery({ queryKey: ["costCenters"], queryFn: getCostCenters });
  const { data: categories = [] } = useQuery({ queryKey: ["categories"], queryFn: getCategories });

  const doStatus = useMutation({
    mutationFn: ({ id, status }: { id: string; status: SupplierStatus }) =>
      setSupplierStatus(id, status, reason),
    onSuccess: () => { setReason(""); setError(null); qc.invalidateQueries({ queryKey: ["suppliers"] }); },
    onError: (e: Error) => setError(e.message),
  });

  const pending = suppliers.filter((s) => s.status === "PENDENTE_DE_HOMOLOGACAO" || s.status === "EM_CADASTRO");

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Administração</h1>
        <p className="text-sm text-slate-500">Homologação de fornecedores e estrutura organizacional.</p>
      </div>

      <div className="grid gap-4 sm:grid-cols-3">
        <Stat label="Setores" value={departments.length} />
        <Stat label="Centros de custo" value={costCenters.length} />
        <Stat label="Categorias" value={categories.length} />
      </div>

      <div className="card">
        <div className="border-b p-4">
          <h2 className="font-medium">Fornecedores aguardando homologação ({pending.length})</h2>
          <p className="text-sm text-slate-500">Requer papel Administrador ou Coordenador de compras.</p>
        </div>
        {pending.length === 0 ? (
          <p className="p-6 text-sm text-slate-500">Nenhum fornecedor pendente.</p>
        ) : (
          <div className="divide-y">
            {pending.map((s) => (
              <div key={s.id} className="flex flex-wrap items-center justify-between gap-3 p-4">
                <div>
                  <p className="font-medium">{s.legal_name}</p>
                  <div className="mt-1"><SupplierBadge status={s.status} /></div>
                </div>
                <div className="flex gap-2">
                  <button className="btn-primary" disabled={doStatus.isPending}
                    onClick={() => doStatus.mutate({ id: s.id, status: "HOMOLOGADO" })}>Homologar</button>
                  <button className="btn-ghost text-rose-700" disabled={doStatus.isPending}
                    onClick={() => doStatus.mutate({ id: s.id, status: "BLOQUEADO" })}>Bloquear</button>
                </div>
              </div>
            ))}
          </div>
        )}
        <div className="border-t p-4">
          <label className="label">Justificativa (obrigatória)</label>
          <input className="input" value={reason} onChange={(e) => setReason(e.target.value)}
            placeholder="Ex.: documentação completa e certidões válidas" />
          {error && <p className="mt-2 text-sm text-rose-600">{error}</p>}
        </div>
      </div>

      <p className="text-sm text-slate-500">
        Configurações avançadas (matriz de aprovação, numerações, SLAs) são editáveis pelo
        Supabase Studio nesta versão.
      </p>
    </div>
  );
}
function Stat({ label, value }: { label: string; value: number }) {
  return <div className="card p-4"><p className="text-sm text-slate-500">{label}</p><p className="mt-1 text-2xl font-semibold">{value}</p></div>;
}
