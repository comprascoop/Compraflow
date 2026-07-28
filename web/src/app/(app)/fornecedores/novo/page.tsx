"use client";
import { useRouter } from "next/navigation";
import { useMutation } from "@tanstack/react-query";
import { SupplierForm } from "@/components/supplier-form";
import { createSupplier, type SupplierInput } from "@/services/suppliers";

export default function NovoFornecedor() {
  const router = useRouter();
  const m = useMutation({
    mutationFn: (v: SupplierInput) => createSupplier(v),
    onSuccess: (id) => router.push(`/fornecedores/${id}`),
  });
  return (
    <div className="mx-auto max-w-3xl space-y-6">
      <div>
        <h1 className="text-xl font-semibold">Novo fornecedor</h1>
        <p className="text-sm text-slate-500">CNPJ é validado automaticamente pelo sistema.</p>
      </div>
      {m.error && <p className="text-sm text-rose-600">{(m.error as Error).message}</p>}
      <SupplierForm onSubmit={(v) => m.mutate(v)} saving={m.isPending} submitLabel="Cadastrar fornecedor" />
    </div>
  );
}
