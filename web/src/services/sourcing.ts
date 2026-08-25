import { createClient } from "@/lib/supabase/client";
import type { ComparisonItem, ComparisonQuote, SourcingRound } from "@/lib/types";

export async function getRounds(requestId: string): Promise<SourcingRound[]> {
  const { data, error } = await createClient().from("sourcing_rounds")
    .select("*").eq("request_id", requestId).order("round_no");
  if (error) throw error; return data as SourcingRound[];
}

export async function createRound(requestId: string, deadline: string | null, mode: string) {
  const supabase = createClient();
  const { data: existing } = await supabase.from("sourcing_rounds")
    .select("round_no").eq("request_id", requestId).order("round_no", { ascending: false }).limit(1);
  const next = (existing?.[0]?.round_no ?? 0) + 1;
  const { data, error } = await supabase.from("sourcing_rounds")
    .insert({ request_id: requestId, round_no: next, deadline_at: deadline, mode })
    .select("id").single();
  if (error) throw error; return data.id as string;
}

export async function inviteSuppliers(roundId: string, supplierIds: string[]) {
  const rows = supplierIds.map((id) => ({ round_id: roundId, supplier_id: id }));
  const { error } = await createClient().from("sourcing_suppliers").insert(rows);
  if (error) throw error;
}

export async function getInvited(roundId: string) {
  const { data, error } = await createClient().from("sourcing_suppliers")
    .select("id, status, supplier_id, decline_reason, suppliers(legal_name)").eq("round_id", roundId);
  if (error) throw error;
  return (data ?? []) as unknown as {
    id: string; status: string; supplier_id: string; decline_reason: string | null;
    suppliers: { legal_name: string } | null;
  }[];
}

// Registra proposta com itens; totais são calculados pelo banco.
export interface QuoteInput {
  round_id: string; supplier_id: string; reference: string | null;
  payment_terms: string | null; delivery_days: number | null;
  freight_amount: number; taxes_amount: number; discount_amount: number;
  items: { request_item_id: string; quantity_offered: number; unit_price: number;
           delivery_days: number | null; technical_fit: string }[];
}
export async function createQuote(input: QuoteInput): Promise<string> {
  const supabase = createClient();
  const { data: q, error } = await supabase.from("supplier_quotes").insert({
    round_id: input.round_id, supplier_id: input.supplier_id, reference: input.reference,
    payment_terms: input.payment_terms, delivery_days: input.delivery_days,
    freight_amount: input.freight_amount, taxes_amount: input.taxes_amount,
    discount_amount: input.discount_amount, status: "VALIDA", quote_date: new Date().toISOString().slice(0,10),
  }).select("id").single();
  if (error) throw error;

  const rows = input.items.map((it) => ({ ...it, quote_id: q.id }));
  const { error: iErr } = await supabase.from("supplier_quote_items").insert(rows);
  if (iErr) throw iErr;

  await supabase.from("sourcing_suppliers").update({ status: "RESPONDIDO" })
    .eq("round_id", input.round_id).eq("supplier_id", input.supplier_id);
  return q.id as string;
}

export async function getComparisonQuotes(requestId: string): Promise<ComparisonQuote[]> {
  const { data, error } = await createClient().from("v_comparison_quotes")
    .select("*").eq("request_id", requestId).order("total_cost");
  if (error) throw error; return data as ComparisonQuote[];
}
export async function getComparisonItems(requestId: string): Promise<ComparisonItem[]> {
  const { data, error } = await createClient().from("v_comparison_items")
    .select("*").eq("request_id", requestId).order("line_no");
  if (error) throw error; return data as ComparisonItem[];
}
