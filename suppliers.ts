"use client";
import { useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { getBusinessUnits } from "@/services/units";
import { cnpjMask } from "@/lib/format";
import type { SupplierInput } from "@/services/suppliers";

export function SupplierForm({ initial, onSubmit, saving, submitLabel }: {
  initial?: Partial<SupplierInput>; onSubmit: (v: SupplierInput) => void;
  saving: boolean; submitLabel: string;
}) {
  const { data: units = [] } = useQuery({ queryKey: ["businessUnits"], queryFn: getBusinessUnits });
  const [form, setForm] = useState<SupplierInput>({
    legal_name: initial?.legal_name ?? "", trade_name: initial?.trade_name ?? "",
    cnpj: initial?.cnpj ?? "", city: initial?.city ?? "", state: initial?.state ?? "",
    default_payment_terms: initial?.default_payment_terms ?? "",
    average_lead_time_days: initial?.average_lead_time_days ?? null,
    business_unit_ids: initial?.business_unit_ids ?? [],
  });
  const [error, setError] = useState<string | null>(null);
  const set = <K extends keyof SupplierInput>(k: K, v: SupplierInput[K]) => setForm((f) => ({ ...f, [k]: v }));

  function submit() {
    setError(null);
    if (!form.legal_name.trim()) { setError("Informe a razão social."); return; }
    if (form.cnpj.replace(/\D/g, "").length !== 14) { setError("CNPJ deve ter 14 dígitos."); return; }
    if (form.business_unit_ids.length === 0) { setError("Marque ao menos uma unidade que o fornecedor atende."); return; }
    onSubmit(form);
  }

  return (
    <div className="space-y-5">
      <section className="card space-y-4 p-5">
        <h2 className="font-medium">Dados do fornecedor</h2>
        <div className="grid gap-4 sm:grid-cols-2">
          <div className="sm:col-span-2"><label className="label">Razão social</label>
            <input className="input" value={form.legal_name} onChange={(e) => set("legal_name", e.target.value)} /></div>
          <div><label className="label">Nome fantasia</label>
            <input className="input" value={form.trade_name ?? ""} onChange={(e) => set("trade_name", e.target.value)} /></div>
          <div><label className="label">CNPJ</label>
            <input className="input" value={cnpjMask(form.cnpj)} onChange={(e) => set("cnpj", e.target.value.replace(/\D/g, ""))} placeholder="00.000.000/0000-00" /></div>
          <div><label className="label">Cidade</label>
            <input className="input" value={form.city ?? ""} onChange={(e) => set("city", e.target.value)} /></div>
          <div><label className="label">UF</label>
            <input className="input" maxLength={2} value={form.state ?? ""} onChange={(e) => set("state", e.target.value.toUpperCase())} /></div>
          <div><label className="label">Condição de pagamento</label>
            <input className="input" value={form.default_payment_terms ?? ""} onChange={(e) => set("default_payment_terms", e.target.value)} /></div>
          <div><label className="label">Prazo médio (dias)</label>
            <input className="input" type="number" value={form.average_lead_time_days ?? ""} onChange={(e) => set("average_lead_time_days", e.target.value ? Number(e.target.value) : null)} /></div>
        </div>
      </section>

      <section className="card space-y-3 p-5">
        <h2 className="font-medium">Unidades que este fornecedor atende</h2>
        <p className="text-sm text-slate-500">
          Só quem pertence a estas unidades enxergará este fornecedor. Marque todas que se aplicam.
        </p>
        <div className="grid gap-2 sm:grid-cols-2">
          {units.map((u) => (
            <label key={u.id} className="flex items-center gap-2 rounded-md border p-2.5 text-sm hover:bg-muted">
              <input type="checkbox" checked={form.business_unit_ids.includes(u.id)}
                onChange={(e) => set("business_unit_ids", e.target.checked
                  ? [...form.business_unit_ids, u.id]
                  : form.business_unit_ids.filter((x) => x !== u.id))} />
              {u.name}
            </label>
          ))}
          {units.length === 0 && <p className="text-sm text-slate-500">Nenhuma unidade cadastrada. Crie em Administração.</p>}
        </div>
      </section>

      {error && <p className="text-sm text-rose-600">{error}</p>}
      <div className="flex justify-end">
        <button className="btn-primary" onClick={submit} disabled={saving}>{saving ? "Salvando…" : submitLabel}</button>
      </div>
    </div>
  );
}
