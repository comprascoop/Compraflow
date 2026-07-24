"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { Plus, Trash2 } from "lucide-react";
import { createRequest } from "@/services/requests";
import { getCategories, getCostCenters, getDepartments, getUnits } from "@/services/meta";
import { brl } from "@/lib/format";

interface ItemRow { description: string; quantity: number; unit_price: number; unit_id: string | null }

export default function NovaDemandaPage() {
  const router = useRouter();
  const { data: departments = [] } = useQuery({ queryKey: ["departments"], queryFn: getDepartments });
  const { data: costCenters = [] } = useQuery({ queryKey: ["costCenters"], queryFn: getCostCenters });
  const { data: categories = [] } = useQuery({ queryKey: ["categories"], queryFn: getCategories });
  const { data: units = [] } = useQuery({ queryKey: ["units"], queryFn: getUnits });

  const [form, setForm] = useState({
    title: "", department_id: "", cost_center_id: "", category_id: "",
    purchase_type: "PRODUTO", priority: "NORMAL", needed_at: "", justification: "",
    is_emergency: false, emergency_reason: "",
  });
  const [items, setItems] = useState<ItemRow[]>([{ description: "", quantity: 1, unit_price: 0, unit_id: null }]);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const set = (k: string, v: string | boolean) => setForm((f) => ({ ...f, [k]: v }));
  const total = items.reduce((s, it) => s + it.quantity * it.unit_price, 0);
  const filteredCC = costCenters.filter((c) => !form.department_id || c.department_id === form.department_id);
  const updateItem = (i: number, patch: Partial<ItemRow>) =>
    setItems((rows) => rows.map((r, idx) => (idx === i ? { ...r, ...patch } : r)));

  async function save() {
    setError(null);
    if (!form.title || !form.department_id || !form.cost_center_id) { setError("Preencha título, setor e centro de custo."); return; }
    if (items.some((it) => !it.description || it.quantity <= 0)) { setError("Todo item precisa de descrição e quantidade maior que zero."); return; }
    setSaving(true);
    try {
      const id = await createRequest({
        ...form, category_id: form.category_id || null, needed_at: form.needed_at || null,
        justification: form.justification || null,
        emergency_reason: form.is_emergency ? form.emergency_reason || null : null, items,
      });
      router.push(`/demandas/${id}`);
    } catch (e) { setError(e instanceof Error ? e.message : "Erro ao salvar a demanda."); }
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
        <div><label className="label">Título</label>
          <input className="input" value={form.title} onChange={(e) => set("title", e.target.value)} /></div>
        <div className="grid gap-4 sm:grid-cols-2">
          <div><label className="label">Setor solicitante</label>
            <select className="input" value={form.department_id}
              onChange={(e) => { set("department_id", e.target.value); set("cost_center_id", ""); }}>
              <option value="">Selecione…</option>
              {departments.map((d) => <option key={d.id} value={d.id}>{d.name}</option>)}
            </select></div>
          <div><label className="label">Centro de custo</label>
            <select className="input" value={form.cost_center_id} onChange={(e) => set("cost_center_id", e.target.value)}>
              <option value="">Selecione…</option>
              {filteredCC.map((c) => <option key={c.id} value={c.id}>{c.code} — {c.name}</option>)}
            </select></div>
          <div><label className="label">Categoria</label>
            <select className="input" value={form.category_id} onChange={(e) => set("category_id", e.target.value)}>
              <option value="">Selecione…</option>
              {categories.map((c) => <option key={c.id} value={c.id}>{c.name}</option>)}
            </select></div>
          <div><label className="label">Tipo</label>
            <select className="input" value={form.purchase_type} onChange={(e) => set("purchase_type", e.target.value)}>
              <option value="PRODUTO">Produto</option><option value="SERVICO">Serviço</option>
              <option value="CONTRATO">Contrato</option><option value="RENOVACAO">Renovação</option>
              <option value="COMPRA_EMERGENCIAL">Compra emergencial</option>
            </select></div>
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
          <button className="btn-ghost" onClick={() => setItems((r) => [...r, { description: "", quantity: 1, unit_price: 0, unit_id: null }])}>
            <Plus className="h-4 w-4" /> Adicionar item
          </button>
        </div>
        {items.map((it, i) => (
          <div key={i} className="grid grid-cols-12 items-end gap-2">
            <div className="col-span-5"><label className="label">Descrição</label>
              <input className="input" value={it.description} onChange={(e) => updateItem(i, { description: e.target.value })} /></div>
            <div className="col-span-2"><label className="label">Unidade</label>
              <select className="input" value={it.unit_id ?? ""} onChange={(e) => updateItem(i, { unit_id: e.target.value || null })}>
                <option value="">—</option>{units.map((u) => <option key={u.id} value={u.id}>{u.code}</option>)}
              </select></div>
            <div className="col-span-2"><label className="label">Qtd</label>
              <input className="input" type="number" min={0} step="0.0001" value={it.quantity}
                onChange={(e) => updateItem(i, { quantity: Number(e.target.value) })} /></div>
            <div className="col-span-2"><label className="label">Vlr unit.</label>
              <input className="input" type="number" min={0} step="0.01" value={it.unit_price}
                onChange={(e) => updateItem(i, { unit_price: Number(e.target.value) })} /></div>
            <div className="col-span-1">
              <button className="btn-ghost h-9 w-full px-0" onClick={() => setItems((r) => r.filter((_, idx) => idx !== i))} disabled={items.length === 1}>
                <Trash2 className="h-4 w-4" />
              </button>
            </div>
          </div>
        ))}
        <div className="flex justify-end border-t pt-3 text-sm">
          <span className="text-slate-500">Total estimado:&nbsp;</span><span className="font-semibold">{brl(total)}</span>
        </div>
      </section>

      {error && <p className="text-sm text-rose-600">{error}</p>}
      <div className="flex justify-end gap-2">
        <button className="btn-ghost" onClick={() => router.back()}>Cancelar</button>
        <button className="btn-primary" onClick={save} disabled={saving}>{saving ? "Salvando…" : "Salvar rascunho"}</button>
      </div>
    </div>
  );
}
