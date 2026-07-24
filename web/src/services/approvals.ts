import { createClient } from "@/lib/supabase/client";
import type { ApprovalDecision } from "@/lib/types";

// Caixa de aprovações: instâncias em andamento visíveis ao usuário (RLS decide).
export async function listPendingApprovals() {
  const { data, error } = await createClient()
    .from("approval_instances")
    .select("id, request_id, recommendation_id, amount, status, current_step, created_at, purchase_requests(number,title,priority,needed_at)")
    .eq("status", "EM_ANDAMENTO")
    .order("created_at");
  if (error) throw error;
  return (data ?? []) as unknown as {
    id: string; request_id: string; amount: number; current_step: number; created_at: string;
    purchase_requests: { number: string | null; title: string; priority: string; needed_at: string | null } | null;
  }[];
}

export async function getApprovalActions(instanceId: string) {
  const { data, error } = await createClient().from("approval_actions")
    .select("*").eq("instance_id", instanceId).order("created_at");
  if (error) throw error;
  return (data ?? []) as { id: string; step_no: number; decision: string; comment: string | null; created_at: string; amount_at_decision: number }[];
}

// Decisão registrada via RPC — imutável, com trilha de auditoria.
export async function decide(instanceId: string, decision: ApprovalDecision, comment?: string) {
  const { data, error } = await createClient().schema("app").rpc("fn_decide_approval", {
    p_instance_id: instanceId, p_decision: decision, p_comment: comment ?? null,
  });
  if (error) throw error;
  return data as string;
}

// Cria recomendação (adjudicação por item) e abre o fluxo de aprovação.
export interface RecommendationInput {
  request_id: string;
  justification: string;
  not_lowest_price: boolean;
  not_lowest_reason: string | null;
  items: { request_item_id: string; quote_id: string; supplier_id: string; quantity: number; unit_price: number }[];
}
export async function createRecommendation(input: RecommendationInput): Promise<string> {
  const supabase = createClient();
  const { data: rec, error } = await supabase.from("recommendations").insert({
    request_id: input.request_id, justification: input.justification,
    not_lowest_price: input.not_lowest_price, not_lowest_reason: input.not_lowest_reason,
  }).select("id").single();
  if (error) throw error;

  const rows = input.items.map((i) => ({ ...i, recommendation_id: rec.id }));
  const { error: iErr } = await supabase.from("recommendation_items").insert(rows);
  if (iErr) throw iErr;

  const { error: sErr } = await supabase.schema("app").rpc("fn_start_approval", { p_recommendation_id: rec.id });
  if (sErr) throw sErr;
  return rec.id as string;
}
