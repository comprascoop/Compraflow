"use client";
import { useState } from "react";
import Link from "next/link";
import { useHasRole } from "@/lib/use-roles";
import { useQuery } from "@tanstack/react-query";
import { Search, Plus } from "lucide-react";
import { listSuppliers } from "@/services/suppliers";
import { cnpjMask } from "@/lib/format";
import { SupplierBadge } from "@/components/status-badge";
import { EmptyState } from "@/components/empty-state";

export default function FornecedoresPage() {
  const [search, setSearch] = useState("");
  const canManage = useHasRole("COMPRADOR", "COORDENADOR_COMPRAS", "ADMINISTRADOR");
  const { data = [], isLoading } = useQuery({ queryKey: ["suppliers", search], queryFn: () => listSuppliers(search || undefined) });
  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">Fornecedores</h1>
          <p className="text-sm text-slate-500">Base de fornecedores e status de homologação.</p>
        </div>
        {canManage && (
          <Link href="/fornecedores/novo" className="btn-primary"><Plus className="h-4 w-4" /> Novo fornecedor</Link>
        )}
      </div>
      <div className="relative max-w-sm">
        <Search className="absolute left-3 top-2.5 h-4 w-4 text-slate-400" />
        <input className="input pl-9" placeholder="Buscar por nome ou CNPJ" value={search} onChange={(e) => setSearch(e.target.value)} />
      </div>
      {isLoading ? <div className="h-40 animate-pulse rounded-lg bg-muted" />
        : data.length === 0 ? <EmptyState title="Nenhum fornecedor encontrado" />
        : (
        <div className="card overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-slate-50 text-left text-xs uppercase text-slate-500">
              <tr><th className="px-4 py-3">Razão social</th><th className="px-4 py-3">CNPJ</th>
              <th className="px-4 py-3">Cidade/UF</th><th className="px-4 py-3">Avaliação</th><th className="px-4 py-3">Status</th></tr>
            </thead>
            <tbody className="divide-y">
              {data.map((s) => (
                <tr key={s.id} className="hover:bg-muted">
                  <td className="px-4 py-3">
                    <Link href={`/fornecedores/${s.id}`} className="text-primary hover:underline">{s.legal_name}</Link>
                    {s.trade_name && <span className="block text-xs text-slate-500">{s.trade_name}</span>}
                  </td>
                  <td className="px-4 py-3">{cnpjMask(s.cnpj)}</td>
                  <td className="px-4 py-3">{[s.city, s.state].filter(Boolean).join("/") || "—"}</td>
                  <td className="px-4 py-3">{s.rating ? `${s.rating} / 5` : "—"}</td>
                  <td className="px-4 py-3"><SupplierBadge status={s.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
