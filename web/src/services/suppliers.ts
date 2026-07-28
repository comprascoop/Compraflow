import { createClient } from "@/lib/supabase/client";
import type { Supplier, SupplierStatus } from "@/lib/types";

export async function listSuppliers(search?: string): Promise<Supplier[]> {
  let q = createClient().from("suppliers").select("*").order("legal_name");
  if (search) q = q.or(`legal_name.ilike.%${search}%,trade_name.ilike.%${search}%,cnpj.ilike.%${search}%`);
  const { data, error } = await q;
  if (error) throw error; return data as Supplier[];
}
export async function getSupplier(id: string): Promise<Supplier> {
  const { data, error } = await createClient().from("suppliers").select("*").eq("id", id).single();
  if (error) throw error; return data as Supplier;
}
export async function setSupplierStatus(id: string, status: SupplierStatus, reason: string) {
  const { error } = await createClient().rpc("fn_set_supplier_status", {
    p_supplier_id: id, p_status: status, p_reason: reason, p_valid_until: null,
  });
  if (error) throw error;
}

export interface SupplierInput {
  legal_name: string; trade_name: string | null; cnpj: string;
  city: string | null; state: string | null; default_payment_terms: string | null;
  average_lead_time_days: number | null; business_unit_ids: string[];
}

export async function createSupplier(input: SupplierInput): Promise<string> {
  const supabase = createClient();
  const { data, error } = await supabase.from("suppliers").insert({
    legal_name: input.legal_name, trade_name: input.trade_name, cnpj: input.cnpj,
    city: input.city, state: input.state, default_payment_terms: input.default_payment_terms,
    average_lead_time_days: input.average_lead_time_days,
  }).select("id").single();
  if (error) throw error;
  if (input.business_unit_ids.length > 0) {
    const rows = input.business_unit_ids.map((bu) => ({ supplier_id: data.id, business_unit_id: bu }));
    const { error: e2 } = await supabase.from("supplier_business_units").insert(rows);
    if (e2) throw e2;
  }
  return data.id as string;
}

export async function updateSupplier(id: string, input: SupplierInput): Promise<void> {
  const supabase = createClient();
  const { error } = await supabase.from("suppliers").update({
    legal_name: input.legal_name, trade_name: input.trade_name, cnpj: input.cnpj,
    city: input.city, state: input.state, default_payment_terms: input.default_payment_terms,
    average_lead_time_days: input.average_lead_time_days,
  }).eq("id", id);
  if (error) throw error;
  // regrava vínculos de unidade
  await supabase.from("supplier_business_units").delete().eq("supplier_id", id);
  if (input.business_unit_ids.length > 0) {
    const rows = input.business_unit_ids.map((bu) => ({ supplier_id: id, business_unit_id: bu }));
    const { error: e2 } = await supabase.from("supplier_business_units").insert(rows);
    if (e2) throw e2;
  }
}

export async function getSupplierUnits(supplierId: string): Promise<string[]> {
  const { data, error } = await createClient().from("supplier_business_units")
    .select("business_unit_id").eq("supplier_id", supplierId);
  if (error) throw error;
  return (data ?? []).map((r: { business_unit_id: string }) => r.business_unit_id);
}
