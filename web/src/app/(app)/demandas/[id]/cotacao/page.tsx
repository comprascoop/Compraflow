"use client";
import { useState } from "react";
import { useParams } from "next/navigation";
import Link from "next/link";
import { useQuery, useQueryClient, useMutation } from "@tanstack/react-query";
import { createQuote, createRound, getInvited, getRounds, inviteSuppliers } from "@/services/sourcing";
import { getItems, getRequest } from "@/services/requests";
import { listSuppliers } from "@/services/suppliers";
import { brl, dateTimeBR } from "@/lib/format";
import { EmptyState } from "@/components/empty-state";

export default function CotacaoPage() {
  const { id } = useParams<{ id: string }>();
  const qc = useQueryClient();
  const [error, setError] = useState<string | null>(null);
  const [deadline, setDeadline] = useState("");
  const [mode, setMode] = useState("PADRAO");
  const [picked, setPicked] = useState<string[]>([]);
  const [quoteFor, setQuoteFor] = useState<string | null>(null);
  const [links, setLinks] = useState<{ supplier_id: string; url: string }[]>([]);
  const [genError, setGenError] = useState<string | null>(null);
  const [generating, setGenerating] = useState(false);
  const [header, setHeader] = useState({ reference: "", payment_terms: "", delivery_days: "", freight_amount: "0", taxes_amount: "0", discount_amount: "0" });
  const [prices, setPrices] = useState<Record<string, string>>({});

  const { data: req } = useQuery({ queryKey: ["request", id], queryFn: () => getRequest(id) });
  const { data: items = [] } = useQuery({ queryKey: ["items", id], queryFn: () => getItems(id) });
  const { data: rounds = [] } = useQuery({ queryKey: ["rounds", id], queryFn: () => getRounds(id) });
  const { data: suppliers = [] } = useQuery({ queryKey: ["suppliers"], queryFn: () => listSuppliers() });
  const round = rounds[rounds.length - 1];
  const { data: invited = [] } = useQuery({
    queryKey: ["invited", round?.id], enabled: !!round, queryFn: () => getInvited(round!.id),
  });

  const refresh = () => ["rounds","invited","request"].forEach((k) => qc.invalidateQueries({ queryKey: [k] }));

  const doRound = useMutation({
    mutationFn: () => createRound(id, deadline || null, mode),
    onSuccess: () => { setError(null); refresh(); },
    onError: (e: Error) => setError(e.message),
  });
  const doInvite = useMutation({
    mutationFn: () => inviteSuppliers(round!.id, picked),
    onSuccess: () => { setPicked([]); setError(null); refresh(); },
    onError: (e: Error) => setError(e.message),
  });
  const doQuote = useMutation({
    mutationFn: () => createQuote({
      round_id: round!.id, supplier_id: quoteFor!,
      reference: header.reference || null, payment_terms: header.payment_terms || null,
      delivery_days: header.delivery_days ? Number(header.delivery_days) : null,
      freight_amount: Number(header.freight_amount || 0),
      taxes_amount: Number(header.taxes_amount || 0),
      discount_amount: Number(header.discount_amount || 0),
      items: items.map((it) => ({
        request_item_id: it.id, quantity_offered: it.quantity,
        unit_price: Number(prices[it.id] || 0), delivery_days: null, technical_fit: "ATENDE",
      })),
    }),
    onSuccess: () => { setQuoteFor(null); setPrices({}); setError(null); refresh(); },
    onError: (e: Error) => setError(e.message),
  });

  async function generateLinks() {
    if (!round) return;
    setGenError(null); setGenerating(true);
    try {
      const payload = invited.map((i) => ({
        supplier_id: i.supplier_id,
        email: `contato@${(i.suppliers?.legal_name ?? "fornecedor").toLowerCase().replace(/[^a-z0-9]+/g, "")}.com`,
      }));
      const r = await fetch("/api/convites/gerar", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ round_id: round.id, suppliers: payload }),
      });
      const j = await r.json();
      if (!r.ok) throw new Error(j.error);
      setLinks(j.links);
    } catch (e) { setGenError(e instanceof Error ? e.message : "Erro ao gerar links"); }
    finally { setGenerating(false); }
  }

  const notInvited = suppliers.filter((s) => !invited.some((i) => i.supplier_id === s.id));

  return (
    <div className="space-y-6">
      <div>
        <p className="text-xs text-slate-500">{req?.number}</p>
        <h1 className="text-xl font-semibold">Workspace de cotação</h1>
        <p className="text-sm text-slate-500">{req?.title}</p>
      </div>
      {error && <p className="text-sm text-rose-600">{error}</p>}

      {!round ? (
        <div className="card space-y-3 p-5">
          <h2 className="font-medium">Abrir rodada de cotação</h2>
          <div className="grid gap-3 sm:grid-cols-2">
            <div><label className="label">Prazo para resposta</label>
              <input className="input" type="datetime-local" value={deadline} onChange={(e) => setDeadline(e.target.value)} /></div>
            <div><label className="label">Modo</label>
              <select className="input" value={mode} onChange={(e) => setMode(e.target.value)}>
                <option value="PADRAO">Padrão</option><option value="ENVELOPE_FECHADO">Envelope fechado</option>
              </select></div>
          </div>
          <button className="btn-primary" onClick={() => doRound.mutate()} disabled={doRound.isPending}>Criar rodada</button>
        </div>
      ) : (
        <>
          <div className="card p-4">
            <div className="flex flex-wrap items-center justify-between gap-2">
              <div>
                <p className="font-medium">Rodada {round.round_no} · {round.mode === "ENVELOPE_FECHADO" ? "Envelope fechado" : "Padrão"}</p>
                <p className="text-sm text-slate-500">Prazo: {dateTimeBR(round.deadline_at)}</p>
              </div>
              <Link href={`/demandas/${id}/comparativo`} className="btn-ghost">Ver mapa comparativo</Link>
            </div>
          </div>

          <div className="card space-y-3 p-5">
            <h2 className="font-medium">Convidar fornecedores</h2>
            <p className="text-sm text-slate-500">Política padrão: no mínimo 3 fornecedores convidados.</p>
            <div className="max-h-52 space-y-1 overflow-y-auto">
              {notInvited.map((s) => (
                <label key={s.id} className="flex items-center gap-2 rounded px-2 py-1 text-sm hover:bg-muted">
                  <input type="checkbox" checked={picked.includes(s.id)}
                    onChange={(e) => setPicked((p) => e.target.checked ? [...p, s.id] : p.filter((x) => x !== s.id))} />
                  {s.legal_name} <span className="text-xs text-slate-400">({s.status})</span>
                </label>
              ))}
              {notInvited.length === 0 && <p className="text-sm text-slate-500">Todos os fornecedores já foram convidados.</p>}
            </div>
            <button className="btn-primary" disabled={picked.length === 0 || doInvite.isPending} onClick={() => doInvite.mutate()}>
              Convidar {picked.length > 0 ? `(${picked.length})` : ""}
            </button>
          </div>

          <div className="card">
            <div className="border-b p-4"><h2 className="font-medium">Fornecedores convidados ({invited.length})</h2></div>
            {invited.length === 0 ? <div className="p-6"><EmptyState title="Nenhum fornecedor convidado ainda" /></div> : (
              <div className="divide-y">
                {invited.map((i) => {
                  const recusou = i.status === "RECUSADO";
                  const respondeu = i.status === "RESPONDIDO";
                  return (
                    <div key={i.id} className="flex flex-wrap items-center justify-between gap-2 p-4">
                      <div>
                        <p className="font-medium">{i.suppliers?.legal_name}</p>
                        <p className={`text-xs ${recusou ? "text-rose-600" : "text-slate-500"}`}>
                          {recusou ? "Recusou participação" : respondeu ? "Proposta recebida" : i.status}
                        </p>
                        {recusou && i.decline_reason && (
                          <p className="mt-1 text-xs text-slate-600">Motivo: {i.decline_reason}</p>
                        )}
                      </div>
                      {!respondeu && !recusou && (
                        <button className="btn-ghost" onClick={() => setQuoteFor(i.supplier_id)}>Registrar proposta</button>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          {invited.length > 0 && (
            <div className="card space-y-3 p-5">
              <div className="flex items-center justify-between">
                <div>
                  <h2 className="font-medium">Links de convite dos fornecedores</h2>
                  <p className="text-sm text-slate-500">
                    Cada fornecedor recebe um link individual e seguro para preencher a própria proposta.
                  </p>
                </div>
                <button className="btn-primary" onClick={generateLinks} disabled={generating}>
                  {generating ? "Gerando…" : "Gerar links"}
                </button>
              </div>
              {genError && <p className="text-sm text-rose-600">{genError}</p>}
              {links.length > 0 && (
                <div className="space-y-2">
                  <p className="rounded-md bg-amber-50 p-2 text-xs text-amber-800">
                    Copie e envie cada link ao respectivo fornecedor. Eles aparecem apenas uma vez.
                  </p>
                  {links.map((l) => {
                    const nome = invited.find((i) => i.supplier_id === l.supplier_id)?.suppliers?.legal_name;
                    return (
                      <div key={l.supplier_id} className="flex items-center gap-2 rounded-md border p-2 text-sm">
                        <span className="w-40 shrink-0 truncate font-medium">{nome}</span>
                        <input readOnly className="input flex-1 text-xs" value={l.url}
                          onFocus={(e) => e.currentTarget.select()} />
                        <button className="btn-ghost shrink-0"
                          onClick={() => navigator.clipboard.writeText(l.url)}>Copiar</button>
                      </div>
                    );
                  })}
                </div>
              )}
            </div>
          )}

          {quoteFor && (
            <div className="card space-y-4 p-5">
              <h2 className="font-medium">Registrar proposta</h2>
              <div className="grid gap-3 sm:grid-cols-3">
                <div><label className="label">Referência</label>
                  <input className="input" value={header.reference} onChange={(e) => setHeader({ ...header, reference: e.target.value })} /></div>
                <div><label className="label">Condição de pagamento</label>
                  <input className="input" value={header.payment_terms} onChange={(e) => setHeader({ ...header, payment_terms: e.target.value })} /></div>
                <div><label className="label">Prazo de entrega (dias)</label>
                  <input className="input" type="number" value={header.delivery_days} onChange={(e) => setHeader({ ...header, delivery_days: e.target.value })} /></div>
                <div><label className="label">Frete (R$)</label>
                  <input className="input" type="number" step="0.01" value={header.freight_amount} onChange={(e) => setHeader({ ...header, freight_amount: e.target.value })} /></div>
                <div><label className="label">Impostos (R$)</label>
                  <input className="input" type="number" step="0.01" value={header.taxes_amount} onChange={(e) => setHeader({ ...header, taxes_amount: e.target.value })} /></div>
                <div><label className="label">Desconto (R$)</label>
                  <input className="input" type="number" step="0.01" value={header.discount_amount} onChange={(e) => setHeader({ ...header, discount_amount: e.target.value })} /></div>
              </div>
              <div className="space-y-2">
                <p className="text-sm font-medium">Preços por item</p>
                {items.map((it) => (
                  <div key={it.id} className="flex items-center gap-3">
                    <span className="flex-1 text-sm">{it.description} <span className="text-slate-400">(qtd {it.quantity})</span></span>
                    <input className="input w-36" type="number" step="0.01" placeholder="Vlr unit."
                      value={prices[it.id] ?? ""} onChange={(e) => setPrices({ ...prices, [it.id]: e.target.value })} />
                  </div>
                ))}
              </div>
              <p className="text-xs text-slate-500">O custo total é recalculado no banco de dados após o envio.</p>
              <div className="flex gap-2">
                <button className="btn-ghost" onClick={() => setQuoteFor(null)}>Cancelar</button>
                <button className="btn-primary" onClick={() => doQuote.mutate()} disabled={doQuote.isPending}>Salvar proposta</button>
              </div>
            </div>
          )}
        </>
      )}
    </div>
  );
}
