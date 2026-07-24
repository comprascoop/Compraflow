import { NextResponse } from "next/server";
import { createAdminClient, sha256 } from "@/lib/supabase/admin";

export async function POST(request: Request) {
  const { token } = await request.json();
  if (!token) return NextResponse.json({ error: "Token ausente" }, { status: 400 });

  const admin = createAdminClient();
  const hash = await sha256(token);

  const { data, error } = await admin.schema("app").rpc("fn_validate_invitation_token", {
    p_token_hash: hash,
  });
  if (error) {
    await admin.schema("app").rpc("fn_register_token_failure", { p_token_hash: hash });
    return NextResponse.json({ error: error.message }, { status: 403 });
  }

  const ctx = Array.isArray(data) ? data[0] : data;
  if (!ctx) return NextResponse.json({ error: "Convite não encontrado" }, { status: 403 });

  // Itens que o fornecedor pode cotar — nada além disso é exposto.
  const { data: items } = await admin.from("purchase_request_items")
    .select("id, line_no, description, specification, quantity")
    .eq("request_id", ctx.request_id).order("line_no");

  return NextResponse.json({ context: ctx, items: items ?? [] });
}
