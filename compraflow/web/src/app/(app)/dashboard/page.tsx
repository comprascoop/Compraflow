"use client";
import { useQuery } from "@tanstack/react-query";
import Link from "next/link";
import { listRequests } from "@/services/requests";
import { brl } from "@/lib/format";
import { StatusBadge } from "@/components/status-badge";

export default function DashboardPage() {
  const { data: reqs = [], isLoading } = useQuery({ queryKey: ["requests"], queryFn: () => listRequests() });
  const open = reqs.filter((r) => !["ENCERRADA","CANCELADA","REJEITADA"].includes(r.status));
  const total = open.reduce((s, r) => s + Number(r.estimated_total), 0);
  const cards = [
    { label: "Demandas abertas", value: open.length },
    { label: "Em cotação", value: reqs.filter((r) => r.status === "EM_COTACAO").length },
    { label: "Aguardando aprovação", value: reqs.filter((r) => r.status.startsWith("AGUARDANDO_APROVACAO")).length },
    { label: "Valor estimado aberto", value: brl(total) },
  ];
  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Painel</h1>
        <p className="text-sm text-slate-500">Visão geral das demandas que você acompanha.</p>
      </div>
      <div className="grid grid-cols-2 gap-4 lg:grid-cols-4">
        {cards.map((c) => (
          <div key={c.label} className="card p-4">
            <p className="text-sm text-slate-500">{c.label}</p>
            <p className="mt-1 text-2xl font-semibold">{isLoading ? "…" : c.value}</p>
          </div>
        ))}
      </div>
      <div className="card">
        <div className="flex items-center justify-between border-b p-4">
          <h2 className="font-medium">Últimas demandas</h2>
          <Link href="/demandas" className="text-sm text-primary hover:underline">Ver todas</Link>
        </div>
        <div className="divide-y">
          {reqs.slice(0, 6).map((r) => (
            <Link key={r.id} href={`/demandas/${r.id}`} className="flex items-center justify-between p-4 hover:bg-muted">
              <div className="min-w-0">
                <p className="truncate font-medium">{r.title}</p>
                <p className="text-xs text-slate-500">{r.number}</p>
              </div>
              <div className="flex items-center gap-3">
                <span className="text-sm text-slate-600">{brl(r.estimated_total)}</span>
                <StatusBadge status={r.status} />
              </div>
            </Link>
          ))}
          {!isLoading && reqs.length === 0 && <p className="p-6 text-sm text-slate-500">Nenhuma demanda ainda.</p>}
        </div>
      </div>
    </div>
  );
}
