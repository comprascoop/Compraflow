"use client";
import { useState } from "react";
import Link from "next/link";
import { useQuery, useQueryClient, useMutation } from "@tanstack/react-query";
import { decide, listPendingApprovals } from "@/services/approvals";
import { brl, dateBR, dateTimeBR } from "@/lib/format";
import { priorityLabel } from "@/components/status-badge";
import { EmptyState } from "@/components/empty-state";
import type { ApprovalDecision } from "@/lib/types";

export default function AprovacoesPage() {
  const qc = useQueryClient();
  const [openId, setOpenId] = useState<string | null>(null);
  const [comment, setComment] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  const { data = [], isLoading } = useQuery({ queryKey: ["approvals"], queryFn: listPendingApprovals });

  const doDecide = useMutation({
    mutationFn: ({ id, d }: { id: string; d: ApprovalDecision }) => decide(id, d, comment || undefined),
    onSuccess: (result) => {
      setInfo(`Decisão registrada: ${result.replace(/_/g, " ").toLowerCase()}.`);
      setComment(""); setOpenId(null); setError(null);
      ["approvals","requests","request"].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));
    },
    onError: (e: Error) => setError(e.message),
  });

  if (isLoading) return <div className="h-40 animate-pulse rounded-lg bg-muted" />;

  return (
    <div className="space-y-5">
      <div>
        <h1 className="text-xl font-semibold">Aprovações</h1>
        <p className="text-sm text-slate-500">Processos aguardando sua decisão.</p>
      </div>
      {info && <p className="text-sm text-emerald-700">{info}</p>}
      {data.length === 0 ? (
        <EmptyState title="Nenhuma aprovação pendente" hint="Quando um comprador enviar uma recomendação, ela aparece aqui." />
      ) : (
        <div className="space-y-3">
          {data.map((a) => (
            <div key={a.id} className="card p-4">
              <div className="flex flex-wrap items-start justify-between gap-3">
                <div className="min-w-0">
                  <p className="text-xs text-slate-500">{a.purchase_requests?.number}</p>
                  <p className="font-medium">{a.purchase_requests?.title}</p>
                  <p className="mt-1 text-sm text-slate-600">
                    Prioridade: {priorityLabel[a.purchase_requests?.priority ?? "NORMAL"]} ·
                    Necessária em {dateBR(a.purchase_requests?.needed_at ?? null)} ·
                    Aguardando desde {dateTimeBR(a.created_at)}
                  </p>
                </div>
                <div className="text-right">
                  <p className="text-xs text-slate-500">Valor em aprovação</p>
                  <p className="text-lg font-semibold">{brl(a.amount)}</p>
                </div>
              </div>

              <div className="mt-3 flex flex-wrap items-center gap-2">
                <Link href={`/demandas/${a.request_id}/comparativo`} className="btn-ghost">Ver comparativo</Link>
                <Link href={`/demandas/${a.request_id}`} className="btn-ghost">Ver demanda</Link>
                <button className="btn-ghost" onClick={() => { setOpenId(openId === a.id ? null : a.id); setError(null); }}>
                  {openId === a.id ? "Fechar" : "Decidir"}
                </button>
              </div>

              {openId === a.id && (
                <div className="mt-4 space-y-3 border-t pt-4">
                  <div>
                    <label className="label">Parecer</label>
                    <textarea className="input h-20 py-2" value={comment} onChange={(e) => setComment(e.target.value)}
                      placeholder="Obrigatório para rejeitar ou solicitar ajustes" />
                  </div>
                  {error && <p className="text-sm text-rose-600">{error}</p>}
                  <div className="flex flex-wrap gap-2">
                    <button className="btn-primary" disabled={doDecide.isPending}
                      onClick={() => doDecide.mutate({ id: a.id, d: "APROVADO" })}>Aprovar</button>
                    <button className="btn-ghost" disabled={doDecide.isPending}
                      onClick={() => doDecide.mutate({ id: a.id, d: "AJUSTE_SOLICITADO" })}>Solicitar ajustes</button>
                    <button className="btn-ghost text-rose-700" disabled={doDecide.isPending}
                      onClick={() => doDecide.mutate({ id: a.id, d: "REJEITADO" })}>Rejeitar</button>
                  </div>
                  <p className="text-xs text-slate-500">A decisão é registrada de forma imutável na trilha de auditoria.</p>
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
