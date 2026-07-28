import { createClient } from "@/lib/supabase/client";

export interface BusinessUnit { id: string; name: string; code: string | null; company_id: string }

export async function getBusinessUnits(): Promise<BusinessUnit[]> {
  const { data, error } = await createClient().from("business_units")
    .select("id,name,code,company_id").eq("is_active", true).order("name");
  if (error) throw error; return data as BusinessUnit[];
}
export async function getCompanies() {
  const { data, error } = await createClient().from("companies").select("id,name").order("name");
  if (error) throw error; return data as { id: string; name: string }[];
}
export async function createBusinessUnit(company_id: string, name: string, code: string) {
  const { error } = await createClient().from("business_units").insert({ company_id, name, code });
  if (error) throw error;
}
// unidades vinculadas ao usuário logado (para default de formulários)
export async function myUnits(): Promise<string[]> {
  const { data, error } = await createClient().from("user_business_units").select("business_unit_id");
  if (error) throw error;
  return (data ?? []).map((r: { business_unit_id: string }) => r.business_unit_id);
}

export async function listUsersWithUnits() {
  const supabase = createClient();
  const { data, error } = await supabase.from("profiles")
    .select("id, full_name, email, user_business_units(business_unit_id)");
  if (error) throw error;
  return (data ?? []) as unknown as {
    id: string; full_name: string; email: string | null;
    user_business_units: { business_unit_id: string }[];
  }[];
}
export async function setUserUnits(userId: string, unitIds: string[]) {
  const supabase = createClient();
  await supabase.from("user_business_units").delete().eq("user_id", userId);
  if (unitIds.length > 0) {
    const rows = unitIds.map((bu) => ({ user_id: userId, business_unit_id: bu }));
    const { error } = await supabase.from("user_business_units").insert(rows);
    if (error) throw error;
  }
}
