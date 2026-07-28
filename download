"use client";
import Link from "next/link";
import { useQuery } from "@tanstack/react-query";
import { listQueue } from "@/services/requests";
import { brl, dateBR } from "@/lib/format";
import { StatusBadge, priorityLabel } from "@/components/status-badge";
import { EmptyState } from "@/components/empty-state";

export default function FilaPage() {
  const { data = [], isLoading } = useQuery({ queryKey: ["queue"], queryFn: listQueue });
  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-xl font-semibold">Fila de compras</h1>
        <p className="text-sm text-slate-500">Demandas sob responsabilidade do setor de compras.</p>
      </div>
      {isLoading ? <div className="h-40 animate-pulse rounded-lg bg-muted" />
        : data.length === 0 ? <EmptyState title="Fila vazia" hint="Nenhuma demanda em análise ou cotação no momento." />
        : (
        <div className="card overflow-x-auto">
          <table className="w-full text-sm">
            <thead className="bg-slate-50 text-left text-xs uppercase text-slate-500">
              <tr><th className="px-4 py-3">Número</th><th className="px-4 py-3">Título</th>
              <th className="px-4 py-3">Prioridade</th><th className="px-4 py-3">Necessária</th>
              <th className="px-4 py-3 text-right">Estimado</th><th className="px-4 py-3">Status</th><th className="px-4 py-3"></th></tr>
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
                  <td className="px-4 py-3 text-right">
                    <Link href={`/demandas/${r.id}/cotacao`} className="text-sm text-primary hover:underline">Cotação</Link>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
