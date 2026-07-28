"use client";
import { useParams, useRouter } from "next/navigation";
import { useQuery, useMutation } from "@tanstack/react-query";
import { SupplierForm } from "@/components/supplier-form";
import { getSupplier, getSupplierUnits, updateSupplier, type SupplierInput } from "@/services/suppliers";

export default function EditarFornecedor() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const { data: s } = useQuery({ queryKey: ["supplier", id], queryFn: () => getSupplier(id) });
  const { data: unitIds } = useQuery({ queryKey: ["supplierUnits", id], queryFn: () => getSupplierUnits(id) });
  const m = useMutation({
    mutationFn: (v: SupplierInput) => updateSupplier(id, v),
    onSuccess: () => router.push(`/fornecedores/${id}`),
  });
  if (!s || unitIds === undefined) return <div className="h-40 animate-pulse rounded-lg bg-muted" />;
  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <h1 className="text-xl font-semibold">Editar fornecedor</h1>
      {m.error && <p className="text-sm text-rose-600">{(m.error as Error).message}</p>}
      <SupplierForm submitLabel="Salvar alterações" saving={m.isPending} onSubmit={(v) => m.mutate(v)}
        initial={{ legal_name: s.legal_name, trade_name: s.trade_name, cnpj: s.cnpj, city: s.city,
          state: s.state, default_payment_terms: s.default_payment_terms,
          average_lead_time_days: s.average_lead_time_days, business_unit_ids: unitIds }} />
    </div>
  );
}
