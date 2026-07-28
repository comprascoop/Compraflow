"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { Plus, Trash2 } from "lucide-react";
import { createRequest } from "@/services/requests";
import { getUnits } from "@/services/meta";
import { myBusinessUnits } from "@/services/units";

interface ItemRow { description: string; quantity: number; unit_id: string | null }

// Extrai uma mensagem legível de erros do Supabase (que não são instanceof Error).
function readableError(e: unknown): string {
  const msg =
    e instanceof Error ? e.message
    : e && typeof e === "object" && "message" in e ? String((e as { message: unknown }).message)
    : "";
  if (/row-level security|violates row-level/i.test(msg))
    return "Você não tem permissão para criar demanda nesta unidade. Confirme com o administrador se você é requisitante e está vinculado a esta unidade.";
  return msg || "Erro ao salvar a demanda.";
}

export default function NovaDemandaPage() {
  const router = useRouter();
  const { data: businessUnits = [] } = useQuery({ queryKey: ["myBusinessUnits"], queryFn: myBusinessUnits });
  const { data: units = [] } = useQuery({ queryKey: ["units"], queryFn: getUnits });

  const [form, setForm] = useState({
    business_unit_id: "", requester_name: "", priority: "NORMAL", needed_at: "",
    justification: "", is_emergency: false, emergency_reason: "",
  });
  const [items, setItems] = useState<ItemRow[]>([{ description: "", quantity: 1, unit_id: null }]);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const set = (k: string, v: string | boolean) => setForm((f) => ({ ...f, [k]: v }));
  const updateItem = (i: number, patch: Partial<ItemRow>) =>
    setItems((rows) => rows.map((r, idx) => (idx === i ? { ...r, ...patch } : r)));

  async function save() {
    setError(null);
    if (!form.business_unit_id) { setError("Selecione o setor solicitante (unidade)."); return; }
    if (!form.requester_name.trim()) { setError("Informe o nome do solicitante."); return; }
    if (items.some((it) => !it.description.trim() || it.quantity <= 0)) {
      setError("Todo item precisa de descrição e quantidade maior que zero."); return;
    }
    setSaving(true);
    try {
      const id = await createRequest({
        business_unit_id: form.business_unit_id,
        requester_name: form.requester_name.trim(),
        priority: form.priority,
        needed_at: form.needed_at || null,
        justification: form.justification || null,
        is_emergency: form.is_emergency,
        emergency_reason: form.is_emergency ? form.emergency_reason || null : null,
        items,
      });
      router.push(`/demandas/${id}`);
    } catch (e) { setError(readableError(e)); }
    finally { setSaving(false); }
  }

  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Nova demanda</h1>
        <p className="text-sm text-slate-500">Salva como rascunho. Você envia para compras depois.</p>
      </div>
      <section className="card space-y-4 p-5">
        <h2 className="font-medium">Informações gerais</h2>
        <div className="grid gap-4 sm:grid-cols-2">
          <div><label className="label">Setor solicitante</label>
            <select className="input" value={form.business_unit_id}
              onChange={(e) => set("business_unit_id", e.target.value)}>
              <option value="">Selecione…</option>
              {businessUnits.map((u) => <option key={u.id} value={u.id}>{u.name}</option>)}
            </select></div>
          <div><label className="label">Nome do solicitante</label>
            <input className="input" value={form.requester_name}
              onChange={(e) => set("requester_name", e.target.value)} placeholder="Quem está pedindo" /></div>
          <div><label className="label">Prioridade</label>
            <select className="input" value={form.priority} onChange={(e) => set("priority", e.target.value)}>
              <option value="BAIXA">Baixa</option><option value="NORMAL">Normal</option>
              <option value="ALTA">Alta</option><option value="CRITICA">Crítica</option>
            </select></div>
          <div><label className="label">Data necessária</label>
            <input className="input" type="date" value={form.needed_at} onChange={(e) => set("needed_at", e.target.value)} /></div>
        </div>
        <div><label className="label">Justificativa</label>
          <textarea className="input h-20 py-2" value={form.justification} onChange={(e) => set("justification", e.target.value)} /></div>
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={form.is_emergency} onChange={(e) => set("is_emergency", e.target.checked)} />
          Compra emergencial
        </label>
        {form.is_emergency && (
          <div><label className="label">Justificativa da emergência</label>
            <textarea className="input h-16 py-2" value={form.emergency_reason} onChange={(e) => set("emergency_reason", e.target.value)} /></div>
        )}
      </section>

      <section className="card space-y-3 p-5">
        <div className="flex items-center justify-between">
          <h2 className="font-medium">Itens</h2>
          <button className="btn-ghost" onClick={() => setItems((r) => [...r, { description: "", quantity: 1, unit_id: null }])}>
            <Plus className="h-4 w-4" /> Adicionar item
          </button>
        </div>
        {items.map((it, i) => (
          <div key={i} className="grid grid-cols-12 items-end gap-2">
            <div className="col-span-6"><label className="label">Descrição</label>
              <input className="input" value={it.description} onChange={(e) => updateItem(i, { description: e.target.value })} /></div>
            <div className="col-span-2"><label className="label">Unidade</label>
              <select className="input" value={it.unit_id ?? ""} onChange={(e) => updateItem(i, { unit_id: e.target.value || null })}>
                <option value="">—</option>{units.map((u) => <option key={u.id} value={u.id}>{u.code}</option>)}
              </select></div>
            <div className="col-span-3"><label className="label">Qtd</label>
              <input className="input" type="number" min={0} step="0.0001" value={it.quantity}
                onChange={(e) => updateItem(i, { quantity: Number(e.target.value) })} /></div>
            <div className="col-span-1">
              <button className="btn-ghost h-9 w-full px-0" onClick={() => setItems((r) => r.filter((_, idx) => idx !== i))} disabled={items.length === 1}>
                <Trash2 className="h-4 w-4" />
              </button>
            </div>
          </div>
        ))}
      </section>

      {error && <p className="text-sm text-rose-600">{error}</p>}
      <div className="flex justify-end gap-2">
        <button className="btn-ghost" onClick={() => router.back()}>Cancelar</button>
        <button className="btn-primary" onClick={save} disabled={saving}>{saving ? "Salvando…" : "Salvar rascunho"}</button>
      </div>
    </div>
  );
}
