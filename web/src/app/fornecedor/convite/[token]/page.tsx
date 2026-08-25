"use client";
import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { ShoppingCart, Clock, CheckCircle2 } from "lucide-react";
import { brl, dateTimeBR } from "@/lib/format";

interface Ctx {
  invitation_id: string; supplier_name: string; request_number: string;
  request_title: string; deadline_at: string | null; mode: string; status: string;
}
interface Item { id: string; line_no: number; description: string; specification: string | null; quantity: number }

// Traduz erros técnicos do servidor em mensagens claras para o fornecedor.
function friendlyError(msg: string): string {
  if (/invalid input syntax for type date/i.test(msg))
    return "A validade da proposta está em formato inválido. Preencha uma data ou deixe o campo em branco.";
  if (/invalid input syntax for type (numeric|integer|double)/i.test(msg))
    return "Confira os campos de valores (frete, impostos, desconto, preços) — use apenas números.";
  if (/expir/i.test(msg))
    return "Este link de cotação expirou. Solicite um novo link ao comprador responsável.";
  if (/já respond|already/i.test(msg))
    return "Esta proposta já foi enviada.";
  return msg || "Não foi possível enviar a proposta. Tente novamente em instantes.";
}

export default function ConvitePage() {
  const { token } = useParams<{ token: string }>();
  const [ctx, setCtx] = useState<Ctx | null>(null);
  const [items, setItems] = useState<Item[]>([]);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [step, setStep] = useState<"aceite" | "proposta" | "enviado">("aceite");
  const [declining, setDeclining] = useState(false);
  const [declineReason, setDeclineReason] = useState("Sem disponibilidade");
  const [header, setHeader] = useState({ reference: "", payment_terms: "", delivery_days: "",
    freight_amount: "0", taxes_amount: "0", discount_amount: "0", valid_until: "", contact_name: "" });
  const [prices, setPrices] = useState<Record<string, string>>({});
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [receipt, setReceipt] = useState<{ protocol: string; total_cost: number } | null>(null);

  useEffect(() => {
    fetch("/api/portal/acessar", { method: "POST", headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token }) })
      .then(async (r) => { const j = await r.json(); if (!r.ok) throw new Error(j.error); return j; })
      .then((j) => { setCtx(j.context); setItems(j.items); })
      .catch((e: Error) => setLoadError(e.message));
  }, [token]);

  // Total é só uma prévia — o valor oficial é o que o servidor recalcular.
  const preview = items.reduce((s, it) => s + Number(prices[it.id] || 0) * Number(it.quantity), 0)
    + Number(header.freight_amount || 0) + Number(header.taxes_amount || 0) - Number(header.discount_amount || 0);

  async function enviar() {
    setError(null);
    // Validação amigável antes de enviar.
    if (items.every((it) => !prices[it.id] || Number(prices[it.id]) <= 0)) {
      setError("Informe o valor unitário de pelo menos um item antes de enviar.");
      return;
    }
    setBusy(true);
    try {
      // Campos vazios de data/número viram nulo (evita erro de tipo no banco).
      const cleanHeader = {
        ...header,
        valid_until: header.valid_until || null,
        delivery_days: header.delivery_days || null,
      };
      const r = await fetch("/api/portal/enviar", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, header: cleanHeader, items: items.map((it) => ({
          request_item_id: it.id, quantity_offered: it.quantity,
          unit_price: Number(prices[it.id] || 0), technical_fit: "ATENDE", will_quote: true })) }) });
      const j = await r.json();
      if (!r.ok) throw new Error(j.error);
      setReceipt(j); setStep("enviado");
    } catch (e) { setError(friendlyError(e instanceof Error ? e.message : "")); }
    finally { setBusy(false); }
  }

  async function recusar() {
    setBusy(true);
    try {
      await fetch("/api/portal/recusar", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ token, reason: declineReason }) });
      setStep("enviado"); setReceipt(null);
    } finally { setBusy(false); }
  }

  if (loadError) return (
    <Shell><div className="card p-8 text-center">
      <p className="font-medium text-rose-700">{loadError}</p>
      <p className="mt-2 text-sm text-slate-500">Solicite um novo link ao comprador responsável.</p>
    </div></Shell>
  );
  if (!ctx) return <Shell><div className="h-40 animate-pulse rounded-lg bg-slate-100" /></Shell>;

  return (
    <Shell>
      <div className="card mb-5 p-5">
        <p className="text-xs text-slate-500">Cotação {ctx.request_number}</p>
        <h1 className="text-lg font-semibold">{ctx.request_title}</h1>
        <p className="mt-1 text-sm text-slate-600">Fornecedor: <b>{ctx.supplier_name}</b></p>
        {ctx.deadline_at && (
          <p className="mt-2 inline-flex items-center gap-1.5 rounded-full bg-amber-50 px-2.5 py-1 text-xs text-amber-800">
            <Clock className="h-3.5 w-3.5" /> Prazo: {dateTimeBR(ctx.deadline_at)}
          </p>
        )}
      </div>

      {step === "enviado" ? (
        <div className="card p-8 text-center">
          <CheckCircle2 className="mx-auto mb-3 h-10 w-10 text-emerald-600" />
          <p className="font-medium">{receipt ? "Proposta enviada com sucesso" : "Resposta registrada"}</p>
          {receipt && (
            <>
              <p className="mt-2 text-sm text-slate-600">Protocolo: <b>{receipt.protocol}</b></p>
              <p className="text-sm text-slate-600">Valor total registrado: <b>{brl(receipt.total_cost)}</b></p>
              <p className="mt-3 text-xs text-slate-500">
                O valor acima foi calculado e conferido pelo sistema do comprador.
              </p>
            </>
          )}
        </div>
      ) : step === "aceite" ? (
        <div className="card space-y-4 p-5">
          <h2 className="font-medium">Confirmação de participação</h2>
          <p className="text-sm text-slate-600">
            Ao participar, você declara que as informações apresentadas são verdadeiras e que está
            ciente do prazo de resposta. Este link é individual e não deve ser compartilhado.
          </p>
          {!declining ? (
            <div className="flex flex-wrap gap-2">
              <button className="btn-primary" onClick={() => setStep("proposta")}>Vou participar</button>
              <button className="btn-ghost" onClick={() => setDeclining(true)}>Não vou participar</button>
            </div>
          ) : (
            <div className="space-y-3">
              <div>
                <label className="label">Motivo da recusa</label>
                <select className="input" value={declineReason} onChange={(e) => setDeclineReason(e.target.value)}>
                  <option>Sem disponibilidade</option><option>Prazo insuficiente</option>
                  <option>Item fora do portfólio</option><option>Condição comercial inviável</option>
                  <option>Problema técnico</option><option>Outro</option>
                </select>
              </div>
              <div className="flex gap-2">
                <button className="btn-ghost" onClick={() => setDeclining(false)}>Voltar</button>
                <button className="btn-primary" onClick={recusar} disabled={busy}>Confirmar recusa</button>
              </div>
            </div>
          )}
        </div>
      ) : (
        <div className="space-y-5">
          <div className="card space-y-4 p-5">
            <h2 className="font-medium">Dados da proposta</h2>
            <div className="grid gap-3 sm:grid-cols-2">
              <div><label className="label">Referência da proposta</label>
                <input className="input" value={header.reference} onChange={(e) => setHeader({ ...header, reference: e.target.value })} /></div>
              <div><label className="label">Responsável comercial</label>
                <input className="input" value={header.contact_name} onChange={(e) => setHeader({ ...header, contact_name: e.target.value })} /></div>
              <div><label className="label">Condição de pagamento</label>
                <input className="input" value={header.payment_terms} onChange={(e) => setHeader({ ...header, payment_terms: e.target.value })} /></div>
              <div><label className="label">Prazo de entrega (dias)</label>
                <input className="input" type="number" value={header.delivery_days} onChange={(e) => setHeader({ ...header, delivery_days: e.target.value })} /></div>
              <div><label className="label">Validade da proposta</label>
                <input className="input" type="date" value={header.valid_until} onChange={(e) => setHeader({ ...header, valid_until: e.target.value })} /></div>
              <div><label className="label">Frete (R$)</label>
                <input className="input" type="number" step="0.01" value={header.freight_amount} onChange={(e) => setHeader({ ...header, freight_amount: e.target.value })} /></div>
              <div><label className="label">Impostos (R$)</label>
                <input className="input" type="number" step="0.01" value={header.taxes_amount} onChange={(e) => setHeader({ ...header, taxes_amount: e.target.value })} /></div>
              <div><label className="label">Desconto (R$)</label>
                <input className="input" type="number" step="0.01" value={header.discount_amount} onChange={(e) => setHeader({ ...header, discount_amount: e.target.value })} /></div>
            </div>
          </div>

          <div className="card p-5">
            <h2 className="mb-3 font-medium">Itens</h2>
            <div className="space-y-3">
              {items.map((it) => (
                <div key={it.id} className="flex flex-wrap items-end gap-3 border-b pb-3 last:border-0">
                  <div className="min-w-[200px] flex-1">
                    <p className="text-sm font-medium">{it.line_no}. {it.description}</p>
                    {it.specification && <p className="text-xs text-slate-500">{it.specification}</p>}
                    <p className="text-xs text-slate-500">Quantidade solicitada: {it.quantity}</p>
                  </div>
                  <div className="w-40">
                    <label className="label">Valor unitário (R$)</label>
                    <input className="input" type="number" step="0.01" value={prices[it.id] ?? ""}
                      onChange={(e) => setPrices({ ...prices, [it.id]: e.target.value })} />
                  </div>
                  <div className="w-32 text-right text-sm">
                    <p className="text-xs text-slate-500">Total do item</p>
                    <p className="font-medium">{brl(Number(prices[it.id] || 0) * Number(it.quantity))}</p>
                  </div>
                </div>
              ))}
            </div>
            <div className="mt-4 flex justify-end border-t pt-3 text-sm">
              <span className="text-slate-500">Prévia do total:&nbsp;</span>
              <span className="font-semibold">{brl(preview)}</span>
            </div>
            <p className="mt-1 text-right text-xs text-slate-400">
              O valor definitivo é recalculado pelo sistema no momento do envio.
            </p>
          </div>

          {error && (
            <div className="flex items-start gap-2 rounded-lg border border-rose-200 bg-rose-50 p-3 text-sm text-rose-700">
              <span className="mt-0.5">⚠️</span><span>{error}</span>
            </div>
          )}
          <div className="flex justify-end gap-2">
            <button className="btn-ghost" onClick={() => setStep("aceite")}>Voltar</button>
            <button className="btn-primary" onClick={enviar} disabled={busy}>
              {busy ? "Enviando…" : "Enviar proposta definitivamente"}
            </button>
          </div>
        </div>
      )}
    </Shell>
  );
}

// Casca própria do portal — não reutiliza a sidebar interna.
function Shell({ children }: { children: React.ReactNode }) {
  return (
    <div className="min-h-screen bg-slate-50">
      <header className="border-b bg-white">
        <div className="mx-auto flex max-w-3xl items-center gap-2 px-5 py-4">
          <ShoppingCart className="h-5 w-5 text-primary" />
          <span className="font-semibold">Portal do Fornecedor</span>
        </div>
      </header>
      <main className="mx-auto max-w-3xl px-5 py-6">{children}</main>
    </div>
  );
}
