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

// Unidades do usuário logado, com nome (para o "Setor solicitante" da demanda).
// Só se cria demanda numa unidade da qual você faz parte — então listamos só essas.
// Sem unidade vinculada (ex.: admin), cai em todas as ativas.
export async function myBusinessUnits(): Promise<BusinessUnit[]> {
  const supabase = createClient();
  const { data: links, error } = await supabase.from("user_business_units").select("business_unit_id");
  if (error) throw error;
  const ids = (links ?? []).map((r: { business_unit_id: string }) => r.business_unit_id);
  if (ids.length === 0) return getBusinessUnits();
  const { data, error: e2 } = await supabase.from("business_units")
    .select("id,name,code,company_id").in("id", ids).eq("is_active", true).order("name");
  if (e2) throw e2; return data as BusinessUnit[];
}

export interface Role { id: string; code: string; name: string }
export async function getRoles(): Promise<Role[]> {
  const { data, error } = await createClient().from("roles").select("id,code,name").order("name");
  if (error) throw error; return data as Role[];
}

export async function listUsersWithUnits() {
  const supabase = createClient();
  const { data, error } = await supabase.from("profiles")
    .select("id, full_name, email, is_active, user_business_units(business_unit_id), user_roles(role_id, is_active)");
  if (error) throw error;
  return (data ?? []) as unknown as {
    id: string; full_name: string; email: string | null; is_active: boolean;
    user_business_units: { business_unit_id: string }[];
    user_roles: { role_id: string; is_active: boolean }[];
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
// Papéis de um usuário (admin pode editar via RLS). Substitui o conjunto atual.
export async function setUserRoles(userId: string, roleIds: string[]) {
  const supabase = createClient();
  await supabase.from("user_roles").delete().eq("user_id", userId);
  if (roleIds.length > 0) {
    const rows = roleIds.map((role_id) => ({ user_id: userId, role_id, is_active: true }));
    const { error } = await supabase.from("user_roles").insert(rows);
    if (error) throw error;
  }
}

// Cria um novo usuário (auth + profile + papéis + unidades) via rota no servidor
// (usa a service role — a criação do login não pode ser feita no navegador).
export async function createUserAccount(input: {
  full_name: string; email: string; password: string;
  role_codes: string[]; business_unit_ids: string[];
}): Promise<void> {
  const res = await fetch("/api/admin/usuarios", {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(input),
  });
  if (!res.ok) {
    const body = await res.json().catch(() => ({}));
    throw new Error(body.error ?? "Falha ao criar usuário.");
  }
}
