import { createClient } from "@/lib/supabase/client";
import type { Category, CostCenter, Department, Unit } from "@/lib/types";

export async function getDepartments(): Promise<Department[]> {
  const { data, error } = await createClient().from("departments").select("id,name").order("name");
  if (error) throw error; return data as Department[];
}
// Setores aos quais o usuário logado pertence (para o formulário de demanda).
// Só é permitido criar demanda num setor do qual você é membro — então listamos
// apenas esses. Se o usuário não tiver setor vinculado (ex.: admin), cai em todos.
export async function myDepartments(): Promise<Department[]> {
  const supabase = createClient();
  const { data: links, error } = await supabase.from("user_departments").select("department_id");
  if (error) throw error;
  const ids = (links ?? []).map((r: { department_id: string }) => r.department_id);
  if (ids.length === 0) return getDepartments();
  const { data, error: e2 } = await supabase
    .from("departments").select("id,name").in("id", ids).order("name");
  if (e2) throw e2; return data as Department[];
}
export async function getCostCenters(): Promise<CostCenter[]> {
  const { data, error } = await createClient().from("cost_centers").select("id,name,code,department_id").order("code");
  if (error) throw error; return data as CostCenter[];
}
export async function getCategories(): Promise<Category[]> {
  const { data, error } = await createClient().from("categories").select("id,name").order("name");
  if (error) throw error; return data as Category[];
}
export async function getUnits(): Promise<Unit[]> {
  const { data, error } = await createClient().from("units_of_measure").select("id,code,name").order("code");
  if (error) throw error; return data as Unit[];
}
