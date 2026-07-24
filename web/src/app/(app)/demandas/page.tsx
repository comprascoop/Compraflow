"use client";
import { useState } from "react";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { Plus, Search } from "lucide-react";
import { listRequests } from "@/services/requests";
import { brl, dateBR } from "@/lib/format";
import { StatusBadge, priorityLabel } from "@/components/status-badge";
import { EmptyState } from "@/components/empty-state";

export default function DemandasPage() {
  const [search, setSearch] = useState("");
  const { data = [], isLoading } = useQuery({ queryKey: ["requests", search], queryFn: () => listRequests(search || undefined) });
  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">Demandas</h1>
          <p className="text-sm text-slate-500">Suas demandas e as do seu setor.</p>
        </div>
        <Link href="/demandas/nova" className="btn-primary"><Plus className="h-4 w-4" /> Nova demanda</Link>
      </div>
      <div className="relative max-w-sm">
        <Search className="absolute left-3 top-2.5 h-4 w-4 text-slate-400" />
        <input className="input pl-9" placeholder="Buscar por título ou número" value={search} onChange={(e) => setSearch(e.target.value)} />
      </div>
      {isLoading ? <div className="h-40 animate-pulse rounded-lg bg-muted" />
        : data.length === 0 ? (
        <EmptyState title="Nenhuma demanda encontrada" hint="Crie sua primeira demanda de compra para começar."
          action={<Link href="/demandas/nova" className="btn-primary"><Plus className="h-4 w-4" /> Nova demanda</Link>} />
      ) : (
        <div className="card overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-slate-50 text-left text-xs uppercase text-slate-500">
              <tr><th className="px-4 py-3">Número</th><th className="px-4 py-3">Título</th>
              <th className="px-4 py-3">Prioridade</th><th className="px-4 py-3">Necessária</th>
              <th className="px-4 py-3 text-right">Estimado</th><th className="px-4 py-3">Status</th></tr>
            </thead>
            <tbody className="divide-y">
              {data.map((r) => (
                <tr key={r.id} className="hover:bg-muted">
                  <td className="px-4 py-3"><Link href={`/demandas/${r.id}`} className="text-primary hover:underline">{r.number}</Link></td>
                  <td className="px-4 py-3">{r.title}</td>
                  <td className="px-4 py-3">{priorityLabel[r.priority]}</td>
                  <td className="px-4 py-3">{dateBR(r.needed_at)}</td>
                  <td className="px-4 py-3 text-right">{brl(r.estimated_total)}</td>
                  <td className="px-4 py-3"><StatusBadge status={r.status} /></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
