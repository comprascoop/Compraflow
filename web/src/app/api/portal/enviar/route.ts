import { NextResponse } from "next/server";
import { createAdminClient, sha256 } from "@/lib/supabase/admin";

export async function POST(request: Request) {
  const { token, header, items } = await request.json();
  const admin = createAdminClient();
  const hash = await sha256(token);

  // Revalida o token no envio — não confia no que veio da tela.
  const { data: ctxData, error: vErr } = await admin.schema("app")
    .rpc("fn_validate_invitation_token", { p_token_hash: hash });
  if (vErr) return NextResponse.json({ error: vErr.message }, { status: 403 });
  const ctx = Array.isArray(ctxData) ? ctxData[0] : ctxData;

  // Totais são recalculados dentro do banco; o que a tela mandou é ignorado.
  const { data, error } = await admin.schema("app").rpc("fn_submit_supplier_quote", {
    p_invitation_id: ctx.invitation_id, p_header: header, p_items: items,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });

  const result = Array.isArray(data) ? data[0] : data;
  return NextResponse.json(result);
}
