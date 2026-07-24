"use client";
import { useParams } from "next/navigation";
import { useQuery } from "@tanstack/react-query";
import { getSupplier } from "@/services/suppliers";
import { cnpjMask } from "@/lib/format";
import { SupplierBadge } from "@/components/status-badge";

export default function FornecedorDetalhe() {
  const { id } = useParams<{ id: string }>();
  const { data: s, isLoading } = useQuery({ queryKey: ["supplier", id], queryFn: () => getSupplier(id) });
  if (isLoading || !s) return <div className="h-40 animate-pulse rounded-lg bg-muted" />;
  return (
    <div className="mx-auto max-w-2xl space-y-6">
      <div>
        <h1 className="text-xl font-semibold">{s.legal_name}</h1>
        {s.trade_name && <p className="text-sm text-slate-500">{s.trade_name}</p>}
        <div className="mt-2"><SupplierBadge status={s.status} /></div>
      </div>
      <dl className="grid gap-4 sm:grid-cols-2">
        <Field label="CNPJ" value={cnpjMask(s.cnpj)} />
        <Field label="Cidade/UF" value={[s.city, s.state].filter(Boolean).join("/") || "—"} />
        <Field label="Prazo médio (dias)" value={s.average_lead_time_days?.toString() ?? "—"} />
        <Field label="Condição de pagamento" value={s.default_payment_terms ?? "—"} />
        <Field label="Avaliação" value={s.rating ? `${s.rating} / 5` : "—"} />
      </dl>
    </div>
  );
}
function Field({ label, value }: { label: string; value: string }) {
  return <div className="card p-3"><dt className="text-xs text-slate-500">{label}</dt><dd className="mt-0.5 text-sm">{value}</dd></div>;
}
