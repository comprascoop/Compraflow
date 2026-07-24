import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient, sha256 } from "@/lib/supabase/admin";

// Gera convites individuais com token seguro. O token original é devolvido UMA vez
// (para envio por e-mail) e nunca é persistido — o banco guarda só o hash.
export async function POST(request: Request) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) return NextResponse.json({ error: "Não autenticado" }, { status: 401 });

  const { round_id, suppliers, expires_days = 7 } = await request.json();
  if (!round_id || !Array.isArray(suppliers) || suppliers.length === 0) {
    return NextResponse.json({ error: "Informe a rodada e os fornecedores." }, { status: 400 });
  }

  const admin = createAdminClient();
  const expiresAt = new Date(Date.now() + expires_days * 86400_000).toISOString();
  const links: { supplier_id: string; email: string; url: string }[] = [];

  for (const s of suppliers as { supplier_id: string; email: string }[]) {
    const { data: inv, error } = await admin.from("sourcing_invitations")
      .insert({ sourcing_round_id: round_id, supplier_id: s.supplier_id,
                invited_email: s.email, invitation_status: "AGUARDANDO_ENVIO",
                created_by: user.id })
      .select("id").single();
    if (error) return NextResponse.json({ error: error.message }, { status: 400 });

    // token de alta entropia — 32 bytes
    const raw = Buffer.from(crypto.getRandomValues(new Uint8Array(32))).toString("base64url");
    const hash = await sha256(raw);

    const { error: tErr } = await admin.schema("app").rpc("fn_register_invitation_token", {
      p_invitation_id: inv.id, p_token_hash: hash, p_expires_at: expiresAt,
    });
    if (tErr) return NextResponse.json({ error: tErr.message }, { status: 400 });

    links.push({ supplier_id: s.supplier_id, email: s.email,
                 url: `${new URL(request.url).origin}/fornecedor/convite/${raw}` });
  }

  // Cada fornecedor recebe um link diferente e não vê os demais convidados.
  return NextResponse.json({ links });
}
