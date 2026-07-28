"use client";
import { useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { useQuery, useMutation } from "@tanstack/react-query";
import { getComparisonItems, getComparisonQuotes } from "@/services/sourcing";
import { createRecommendation } from "@/services/approvals";
import { getRequest } from "@/services/requests";
import { brl, dateBR } from "@/lib/format";
import { EmptyState } from "@/components/empty-state";

export default function ComparativoPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [awards, setAwards] = useState<Record<string, string>>({}); // request_item_id -> quote_id
  const [justification, setJustification] = useState("");
  const [notLowestReason, setNotLowestReason] = useState("");
  const [error, setError] = useState<string | null>(null);

  const { data: req } = useQuery({ queryKey: ["request", id], queryFn: () => getRequest(id) });
  const { data: quotes = [], isLoading } = useQuery({ queryKey: ["cmpQuotes", id], queryFn: () => getComparisonQuotes(id) });
  const { data: cmpItems = [] } = useQuery({ queryKey: ["cmpItems", id], queryFn: () => getComparisonItems(id) });

  // agrupa por item
  const byItem = useMemo(() => {
    const m = new Map<string, typeof cmpItems>();
    cmpItems.forEach((r) => { const a = m.get(r.request_item_id) ?? []; a.push(r); m.set(r.request_item_id, a); });
    return m;
  }, [cmpItems]);

  const lowestQuoteId = quotes.length ? quotes[0].quote_id : null; // view já ordena por total_cost
  const awarded = Object.entries(awards);
  const awardedTotal = awarded.reduce((sum, [itemId, quoteId]) => {
    const row = (byItem.get(itemId) ?? []).find((r) => r.quote_id === quoteId);
    return sum + (row ? Number(row.line_total) : 0);
  }, 0);
  const suppliersInAward = new Set(awarded.map(([itemId, quoteId]) =>
    (byItem.get(itemId) ?? []).find((r) => r.quote_id === quoteId)?.supplier_id).filter(Boolean));
  const notLowest = awarded.some(([, quoteId]) => quoteId !== lowestQuoteId);

  const doRecommend = useMutation({
    mutationFn: () => {
      const items = awarded.map(([itemId, quoteId]) => {
        const row = (byItem.get(itemId) ?? []).find((r) => r.quote_id === quoteId)!;
        return { request_item_id: itemId, quote_id: quoteId, supplier_id: row.supplier_id,
                 quantity: Number(row.quantity_offered), unit_price: Number(row.unit_price) };
      });
      return createRecommendation({
        request_id: id, justification, not_lowest_price: notLowest,
        not_lowest_reason: notLowest ? notLowestReason : null, items,
      });
    },
    onSuccess: () => router.push("/aprovacoes"),
    onError: (e: Error) => setError(e.message),
  });

  if (isLoading) return <div className="h-40 animate-pulse rounded-lg bg-muted" />;
  if (quotes.length === 0) {
    return (
      <div className="space-y-5">
        <h1 className="text-xl font-semibold">Mapa comparativo</h1>
        <EmptyState title="Nenhuma proposta registrada"
          hint="Registre propostas no workspace de cotação para gerar a comparação." />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <p className="text-xs text-slate-500">{req?.number}</p>
        <h1 className="text-xl font-semibold">Mapa comparativo</h1>
        <p className="text-sm text-slate-500">
          Destaques são cálculos, não decisão. A escolha do fornecedor é sua.
        </p>
      </div>

      {/* Comparação por proposta */}
      <div className="card overflow-x-auto">
        <table className="w-full text-sm">
          <thead className="bg-slate-50 text-left text-xs uppercase text-slate-500">
            <tr>
              <th className="px-4 py-3">Fornecedor</th><th className="px-4 py-3 text-right">Subtotal</th>
              <th className="px-4 py-3 text-right">Frete</th><th className="px-4 py-3 text-right">Impostos</th>
              <th className="px-4 py-3 text-right">Desconto</th><th className="px-4 py-3 text-right">Custo total</th>
              <th className="px-4 py-3 text-right">Dif. p/ menor</th><th className="px-4 py-3">Pagamento</th>
              <th className="px-4 py-3 text-right">Prazo</th><th className="px-4 py-3">Validade</th>
              <th className="px-4 py-3 text-right">Cobertura</th>
            </tr>
          </thead>
          <tbody className="divide-y">
            {quotes.map((q) => (
              <tr key={q.quote_id} className={q.quote_id === lowestQuoteId ? "bg-emerald-50/50" : ""}>
                <td className="px-4 py-3">
                  {q.supplier_name}
                  {q.quote_id === lowestQuoteId && <span className="ml-2 rounded-full bg-emerald-100 px-2 py-0.5 text-xs text-emerald-700">menor custo</span>}
                  <span className="block text-xs text-slate-400">{q.supplier_status}</span>
                </td>
                <td className="px-4 py-3 text-right">{brl(q.items_subtotal)}</td>
                <td className="px-4 py-3 text-right">{brl(q.freight_amount)}</td>
                <td className="px-4 py-3 text-right">{brl(q.taxes_amount)}</td>
                <td className="px-4 py-3 text-right">{brl(q.discount_amount)}</td>
                <td className="px-4 py-3 text-right font-semibold">{brl(q.total_cost)}</td>
                <td className="px-4 py-3 text-right">{Number(q.diff_to_lowest) === 0 ? "—" : brl(q.diff_to_lowest)}</td>
                <td className="px-4 py-3">{q.payment_terms ?? "—"}</td>
                <td className="px-4 py-3 text-right">{q.delivery_days ?? "—"}</td>
                <td className="px-4 py-3">{dateBR(q.valid_until)}</td>
                <td className="px-4 py-3 text-right">{q.items_quoted}/{q.items_requested}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Adjudicação por item */}
      <div className="card">
        <div className="border-b p-4">
          <h2 className="font-medium">Adjudicação por item</h2>
          <p className="text-sm text-slate-500">Você pode escolher fornecedores diferentes para itens diferentes.</p>
        </div>
        <div className="divide-y">
          {Array.from(byItem.entries()).map(([itemId, rows]) => (
            <div key={itemId} className="p-4">
              <p className="mb-2 text-sm font-medium">{rows[0].item_description}
                <span className="ml-2 text-xs text-slate-400">qtd {rows[0].quantity_requested}</span></p>
              <div className="grid gap-2 sm:grid-cols-2 lg:grid-cols-3">
                {rows.map((r) => {
                  const isBest = Number(r.unit_price) === Number(r.best_unit_price);
                  const selected = awards[itemId] === r.quote_id;
                  return (
                    <button key={r.quote_id} onClick={() => setAwards({ ...awards, [itemId]: r.quote_id })}
                      className={`rounded-md border p-3 text-left text-sm ${selected ? "border-primary ring-2 ring-primary/25" : "hover:bg-muted"}`}>
                      <p className="font-medium">{r.supplier_name}</p>
                      <p>{brl(r.unit_price)} /un · total {brl(r.line_total)}</p>
                      <p className="text-xs text-slate-500">
                        prazo {r.delivery_days ?? "—"}d · {r.technical_fit.replace(/_/g, " ").toLowerCase()}
                      </p>
                      {isBest && <span className="mt-1 inline-block rounded-full bg-emerald-100 px-2 py-0.5 text-xs text-emerald-700">menor preço unitário</span>}
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Recomendação */}
      <div className="card space-y-3 p-5">
        <h2 className="font-medium">Recomendação de compra</h2>
        <div className="flex flex-wrap gap-6 text-sm">
          <span>Itens adjudicados: <b>{awarded.length}</b> de {byItem.size}</span>
          <span>Fornecedores: <b>{suppliersInAward.size}</b></span>
          <span>Total recomendado: <b>{brl(awardedTotal)}</b></span>
        </div>
        {suppliersInAward.size > 1 && (
          <p className="rounded-md bg-amber-50 p-3 text-sm text-amber-800">
            Dividir os itens entre {suppliersInAward.size} fornecedores gera um pedido para cada um e pode alterar frete e condições comerciais.
          </p>
        )}
        <div><label className="label">Justificativa da escolha</label>
          <textarea className="input h-20 py-2" value={justification} onChange={(e) => setJustification(e.target.value)} /></div>
        {notLowest && (
          <div>
            <label className="label">A escolha não é a de menor custo — justifique</label>
            <textarea className="input h-20 py-2" value={notLowestReason} onChange={(e) => setNotLowestReason(e.target.value)} />
          </div>
        )}
        {error && <p className="text-sm text-rose-600">{error}</p>}
        <button className="btn-primary" disabled={doRecommend.isPending}
          onClick={() => {
            setError(null);
            if (awarded.length === 0) { setError("Selecione ao menos um item adjudicado."); return; }
            if (!justification.trim()) { setError("A justificativa é obrigatória."); return; }
            if (notLowest && !notLowestReason.trim()) { setError("Justifique a escolha fora do menor custo."); return; }
            doRecommend.mutate();
          }}>
          Recomendar e enviar para aprovação
        </button>
      </div>
    </div>
  );
}
