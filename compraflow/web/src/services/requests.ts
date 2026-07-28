import { createClient } from "@/lib/supabase/client";
import type { PurchaseRequest, PurchaseRequestItem, RequestStatus, StatusHistory } from "@/lib/types";

export async function listRequests(search?: string): Promise<PurchaseRequest[]> {
  let q = createClient().from("purchase_requests").select("*").order("created_at", { ascending: false });
  if (search) q = q.or(`title.ilike.%${search}%,number.ilike.%${search}%`);
  const { data, error } = await q;
  if (error) throw error; return data as PurchaseRequest[];
}

export async function listQueue(): Promise<PurchaseRequest[]> {
  const { data, error } = await createClient().from("purchase_requests").select("*")
    .in("status", ["EM_ANALISE_POR_COMPRAS","AGUARDANDO_INFORMACOES","EM_COTACAO","COTACOES_RECEBIDAS","EM_ANALISE_DE_COTACOES"])
    .order("created_at", { ascending: false });
  if (error) throw error; return data as PurchaseRequest[];
}

export async function getRequest(id: string): Promise<PurchaseRequest> {
  const { data, error } = await createClient().from("purchase_requests").select("*").eq("id", id).single();
  if (error) throw error; return data as PurchaseRequest;
}
export async function getItems(requestId: string): Promise<PurchaseRequestItem[]> {
  const { data, error } = await createClient().from("purchase_request_items")
    .select("*").eq("request_id", requestId).order("line_no");
  if (error) throw error; return data as PurchaseRequestItem[];
}
export async function getHistory(requestId: string): Promise<StatusHistory[]> {
  const { data, error } = await createClient().from("status_history")
    .select("*").eq("request_id", requestId).order("created_at", { ascending: false });
  if (error) throw error; return data as StatusHistory[];
}

export interface NewRequestInput {
  title: string; business_unit_id: string | null; department_id: string; cost_center_id: string; category_id: string | null;
  purchase_type: string; priority: string; needed_at: string | null; justification: string | null;
  is_emergency: boolean; emergency_reason: string | null;
  items: { description: string; quantity: number; unit_price: number; unit_id: string | null }[];
}

export async function createRequest(input: NewRequestInput): Promise<string> {
  const supabase = createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) throw new Error("Sessão expirada.");
  const { data: req, error } = await supabase.from("purchase_requests").insert({
    title: input.title, business_unit_id: input.business_unit_id || null,
    department_id: input.department_id, cost_center_id: input.cost_center_id,
    category_id: input.category_id, purchase_type: input.purchase_type, priority: input.priority,
    needed_at: input.needed_at, justification: input.justification,
    is_emergency: input.is_emergency, emergency_reason: input.emergency_reason, created_by: user.id,
  }).select("id").single();
  if (error) throw error;

  const items = input.items.map((it, i) => ({
    request_id: req.id, line_no: i + 1, description: it.description,
    quantity: it.quantity, unit_price: it.unit_price, unit_id: it.unit_id,
  }));
  const { error: itErr } = await supabase.from("purchase_request_items").insert(items);
  if (itErr) throw itErr;
  return req.id as string;
}

// Transições SEMPRE via RPC no schema app — o front nunca faz update de status.
export async function transition(requestId: string, to: RequestStatus, comment?: string) {
  const { error } = await createClient().rpc("fn_transition_request", {
    p_request_id: requestId, p_to_status: to, p_comment: comment ?? null,
  });
  if (error) throw error;
}
export async function assignBuyer(requestId: string) {
  const { error } = await createClient().rpc("fn_assign_buyer", { p_request_id: requestId });
  if (error) throw error;
}
export async function allowedTransitions(from: RequestStatus) {
  const { data, error } = await createClient().from("request_status_transitions")
    .select("to_status, description, requires_comment").eq("from_status", from);
  if (error) throw error;
  return data as { to_status: RequestStatus; description: string; requires_comment: boolean }[];
}
export async function generateOrders(requestId: string): Promise<number> {
  const { data, error } = await createClient().rpc("fn_generate_orders", { p_request_id: requestId });
  if (error) throw error; return data as number;
}
