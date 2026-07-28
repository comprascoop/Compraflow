import { createClient } from "@/lib/supabase/client";
import type { Category, CostCenter, Department, Unit } from "@/lib/types";

export async function getDepartments(): Promise<Department[]> {
  const { data, error } = await createClient().from("departments").select("id,name").order("name");
  if (error) throw error; return data as Department[];
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
