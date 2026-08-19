export async function createRecommendation(input: RecommendationInput): Promise<string> {
  const supabase = createClient();
  // A constraint é unique(request_id, version_no). Cada nova recomendação da mesma
  // demanda é uma versão nova (v1, v2, …), evitando o erro de chave duplicada.
  const { data: prev } = await supabase.from("recommendations")
    .select("version_no").eq("request_id", input.request_id)
    .order("version_no", { ascending: false }).limit(1);
  const version_no = (prev?.[0]?.version_no ?? 0) + 1;
  const { data: rec, error } = await supabase.from("recommendations").insert({
    request_id: input.request_id, version_no,
    justification: input.justification,
    not_lowest_price: input.not_lowest_price, not_lowest_reason: input.not_lowest_reason,
  }).select("id").single();
  if (error) throw error;

  const rows = input.items.map((i) => ({ ...i, recommendation_id: rec.id }));
  const { error: iErr } = await supabase.from("recommendation_items").insert(rows);
  if (iErr) throw iErr;

  const { error: sErr } = await supabase.rpc("fn_start_approval", { p_recommendation_id: rec.id });
  if (sErr) throw sErr;
  return rec.id as string;
}
