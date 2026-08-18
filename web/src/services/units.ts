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
export async function myUnits(): Promise<string[]> {
  const { data, error } = await createClient().from("user_business_units").select("business_unit_id");
  if (error) throw error;
  return (data ?? []).map((r: { business_unit_id: string }) => r.business_unit_id);
}

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
  const [{ data: profiles, error: pErr }, { data: ubu, error: uErr }, { data: ur, error: rErr }] =
    await Promise.all([
      supabase.from("profiles").select("id, full_name, email, is_active").order("full_name"),
      supabase.from("user_business_units").select("user_id, business_unit_id"),
      supabase.from("user_roles").select("user_id, role_id, is_active"),
    ]);
  if (pErr) throw pErr;
  if (uErr) throw uErr;
  if (rErr) throw rErr;
  return (profiles ?? []).map((p) => ({
    id: p.id, full_name: p.full_name, email: p.email, is_active: p.is_active,
    user_business_units: (ubu ?? []).filter((x) => x.user_id === p.id)
      .map((x) => ({ business_unit_id: x.business_unit_id })),
    user_roles: (ur ?? []).filter((x) => x.user_id === p.id)
      .map((x) => ({ role_id: x.role_id, is_active: x.is_active })),
  })) as {
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
export async function setUserRoles(userId: string, roleIds: string[]) {
  const supabase = createClient();
  await supabase.from("user_roles").delete().eq("user_id", userId);
  if (roleIds.length > 0) {
    const rows = roleIds.map((role_id) => ({ user_id: userId, role_id, is_active: true }));
    const { error } = await supabase.from("user_roles").insert(rows);
    if (error) throw error;
  }
}

export async function createUserAccount(input: {
  full_name: string; email: string; password: string;
  role_codes: string[]; business_unit_ids: string[];
}): Promise<void> {
  let res: Response;
  try {
    res = await fetch("/api/admin/usuarios", {
      method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(input),
    });
  } catch {
    throw new Error("Não foi possível contatar o servidor.");
  }
  if (!res.ok) {
    let msg = `Falha ao criar usuário (HTTP ${res.status}).`;
    try { const body = await res.json(); if (body?.error) msg = body.error; } catch { /* resposta não-JSON */ }
    throw new Error(msg);
  }
}
