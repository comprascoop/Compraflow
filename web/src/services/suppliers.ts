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
  const { error } = await createClient().schema("app").rpc("fn_set_supplier_status", {
    p_supplier_id: id, p_status: status, p_reason: reason, p_valid_until: null,
  });
  if (error) throw error;
}
