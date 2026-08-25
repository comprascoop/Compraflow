"use client";
import { useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { useQuery, useQueryClient, useMutation } from "@tanstack/react-query";
import { allowedTransitions, assignBuyer, generateOrders, getHistory, getItems, getRequest, transition } from "@/services/requests";
import { brl, dateBR, dateTimeBR } from "@/lib/format";
import { StatusBadge, priorityLabel } from "@/components/status-badge";
import { useRoles } from "@/lib/use-roles";
import { createClient } from "@/lib/supabase/client";
import type { RequestStatus } from "@/lib/types";

const TABS = ["Visão geral", "Itens", "Histórico"] as const;

export default function DemandaDetalhe() {
  const { id } = useParams<{ id: string }>();
  const qc = useQueryClient();
  const [tab, setTab] = useState<(typeof TABS)[number]>("Visão geral");
  const [comment, setComment] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [info, setInfo] = useState<string | null>(null);

  const roles = useRoles();
  const { data: userId } = useQuery({
    queryKey: ["me"],
    queryFn: async () => (await createClient().auth.getUser()).data.user?.id ?? null,
  });

  const { data: req, isLoading } = useQuery({ queryKey: ["request", id], queryFn: () => getRequest(id) });
  const { data: items = [] } = useQuery({ queryKey: ["items", id], queryFn: () => getItems(id) });
  const { data: history = [] } = useQuery({ queryKey: ["history", id], queryFn: () => getHistory(id) });
  const { data: actions = [] } = useQuery({
    queryKey: ["actions", req?.status], enabled: !!req,
    queryFn: () => allowedTransitions(req!.status as RequestStatus),
  });

  const refetchAll = () => ["request","items","history","actions","requests","queue"]
    .forEach((k) => qc.invalidateQueries({ queryKey: [k] }));

  const doTransition = useMutation({
    mutationFn: (to: RequestStatus) => transition(id, to, comment || undefined),
    onSuccess: () => { setComment(""); setError(null); refetchAll(); },
    onError: (e: Error) => setError(e.message),
  });
  const doAssign = useMutation({
    mutationFn: () => assignBuyer(id), onSuccess: refetchAll,
    onError: (e: Error) => setError(e.message),
  });
  const doOrders = useMutation({
    mutationFn: () => generateOrders(id),
    onSuccess: (n) => { setInfo(`${n} pedido(s) de compra gerado(s).`); refetchAll(); },
    onError: (e: Error) => setError(e.message),
  });

  if (isLoading || !req) return <div className="h-40 animate-pulse rounded-lg bg-muted" />;

  // Quem pode o quê (mesma regra do banco), para mostrar só as ações do perfil.
  const isAdmin = roles.includes("ADMINISTRADOR");
  const isPurchasing = roles.includes("COMPRADOR") || roles.includes("COORDENADOR_COMPRAS");
  const isOwner = !!userId && req.created_by === userId;
  const canDo = (a: (typeof actions)[number]) =>
    isAdmin
    || (!!a.required_role && roles.includes(a.required_role as (typeof roles)[number]))
    || (a.allow_owner && isOwner)
    || (a.allow_dept_manager && roles.includes("GESTOR_SETOR"));
  const myActions = actions.filter(canDo);
  const canAssign = (isPurchasing || isAdmin) && !req.assigned_buyer_id;
  const canGenerateOrders = (isPurchasing || isAdmin) && req.status === "APROVADA";
  // Cotação e mapa comparativo são de compras/aprovação — não do solicitante.
  const isApprover = roles.includes("APROVADOR_FINANCEIRO");
  const canSeeSourcing = isPurchasing || isAdmin || isApprover;

  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <p className="text-xs text-slate-500">{req.number}</p>
          <h1 className="text-xl font-semibold">{req.title}</h1>
          <div className="mt-2 flex flex-wrap items-center gap-3 text-sm text-slate-600">
            <StatusBadge status={req.status} />
            <span>Prioridade: {priorityLabel[req.priority]}</span>
            {req.is_emergency && <span className="text-rose-600">Emergencial</span>}
          </div>
        </div>
        <div className="card px-4 py-3 text-right">
          <p className="text-xs text-slate-500">Total estimado</p>
          <p className="text-lg font-semibold">{brl(req.estimated_total)}</p>
        </div>
      </div>

      {canSeeSourcing && (
        <div className="flex flex-wrap gap-2">
          <Link href={`/demandas/${id}/cotacao`} className="btn-ghost">Workspace de cotação</Link>
          <Link href={`/demandas/${id}/comparativo`} className="btn-ghost">Mapa comparativo</Link>
        </div>
      )}

      <div className="card p-4">
        <p className="mb-2 text-sm font-medium">Ações</p>
        {error && <p className="mb-2 text-sm text-rose-600">{error}</p>}
        {info && <p className="mb-2 text-sm text-emerald-700">{info}</p>}
        <div className="flex flex-wrap items-center gap-2">
          {canAssign && (
            <button className="btn-ghost" onClick={() => doAssign.mutate()} disabled={doAssign.isPending}>Assumir demanda</button>
          )}
          {canGenerateOrders && (
            <button className="btn-primary" onClick={() => doOrders.mutate()} disabled={doOrders.isPending}>Gerar pedido de compra</button>
          )}
          {myActions.map((a) => (
            <button key={a.to_status} className="btn-primary" disabled={doTransition.isPending}
              onClick={() => {
                if (a.requires_comment && !comment.trim()) { setError("Esta ação exige justificativa."); return; }
                doTransition.mutate(a.to_status);
              }}>{a.description}</button>
          ))}
          {myActions.length === 0 && !canAssign && !canGenerateOrders && (
            <span className="text-sm text-slate-500">Nenhuma ação disponível para o seu perfil neste momento.</span>
          )}
        </div>
        <input className="input mt-3" placeholder="Justificativa (obrigatória em algumas ações)"
          value={comment} onChange={(e) => setComment(e.target.value)} />
      </div>

      <div>
        <div className="flex gap-1 border-b">
          {TABS.map((t) => (
            <button key={t} onClick={() => setTab(t)}
              className={`px-4 py-2 text-sm ${tab === t ? "border-b-2 border-primary font-medium text-primary" : "text-slate-500"}`}>{t}</button>
          ))}
        </div>
        <div className="pt-4">
          {tab === "Visão geral" && (
            <dl className="grid gap-4 sm:grid-cols-2">
              <Field label="Data necessária" value={dateBR(req.needed_at)} />
              <Field label="Tipo" value={req.purchase_type} />
              <Field label="Criada em" value={dateTimeBR(req.created_at)} />
              <Field label="Comprador atribuído" value={req.assigned_buyer_id ? "Sim" : "—"} />
            </dl>
          )}
          {tab === "Itens" && (
            <div className="card overflow-x-auto">
              <table className="w-full text-sm">
                <thead className="bg-slate-50 text-left text-xs uppercase text-slate-500">
                  <tr><th className="px-4 py-2">#</th><th className="px-4 py-2">Descrição</th>
                  <th className="px-4 py-2 text-right">Qtd</th><th className="px-4 py-2 text-right">Vlr unit.</th>
                  <th className="px-4 py-2 text-right">Total</th></tr>
                </thead>
                <tbody className="divide-y">
                  {items.map((it) => (
                    <tr key={it.id}>
                      <td className="px-4 py-2">{it.line_no}</td>
                      <td className="px-4 py-2">{it.description}</td>
                      <td className="px-4 py-2 text-right">{it.quantity}</td>
                      <td className="px-4 py-2 text-right">{brl(it.unit_price)}</td>
                      <td className="px-4 py-2 text-right">{brl(it.total_estimated)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
          {tab === "Histórico" && (
            <ol className="space-y-3">
              {history.map((h) => (
                <li key={h.id} className="flex gap-3 text-sm">
                  <div className="mt-1 h-2 w-2 shrink-0 rounded-full bg-primary" />
                  <div>
                    <p><span className="text-slate-500">{h.from_status ?? "início"}</span> → <span className="font-medium">{h.to_status}</span></p>
                    {h.comment && <p className="text-slate-600">{h.comment}</p>}
                    <p className="text-xs text-slate-400">{dateTimeBR(h.created_at)}</p>
                  </div>
                </li>
              ))}
              {history.length === 0 && <p className="text-sm text-slate-500">Sem movimentações registradas.</p>}
            </ol>
          )}
        </div>
      </div>
    </div>
  );
}

function Field({ label, value }: { label: string; value: string }) {
  return <div className="card p-3"><dt className="text-xs text-slate-500">{label}</dt><dd className="mt-0.5 text-sm">{value}</dd></div>;
}
