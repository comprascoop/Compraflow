import { NextResponse } from "next/server";
import { createAdminClient, sha256 } from "@/lib/supabase/admin";

export async function POST(request: Request) {
  const { token, reason } = await request.json();
  const admin = createAdminClient();
  const hash = await sha256(token);

  const { data: ctxData, error: vErr } = await admin.rpc("fn_validate_invitation_token", { p_token_hash: hash });
  if (vErr) return NextResponse.json({ error: vErr.message }, { status: 403 });
  const ctx = Array.isArray(ctxData) ? ctxData[0] : ctxData;

  const { error } = await admin.rpc("fn_decline_invitation", {
    p_invitation_id: ctx.invitation_id, p_reason: reason,
  });
  if (error) return NextResponse.json({ error: error.message }, { status: 400 });
  return NextResponse.json({ ok: true });
}
