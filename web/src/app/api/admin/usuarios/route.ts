import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { createAdminClient } from "@/lib/supabase/admin";

type RoleRel = { code: string } | { code: string }[] | null;
const hasAdmin = (rows: { roles: RoleRel }[] | null) =>
  (rows ?? []).some((r) =>
    Array.isArray(r.roles) ? r.roles.some((x) => x.code === "ADMINISTRADOR") : r.roles?.code === "ADMINISTRADOR");

// Cria um usuário de login com senha provisória e já atribui papéis e unidades.
// Só administradores podem chamar. Usa a service role (ignora RLS) no servidor.
export async function POST(request: Request) {
  try {
    const supabase = await createClient();
    const { data: { user } } = await supabase.auth.getUser();
    if (!user) return NextResponse.json({ error: "Não autenticado." }, { status: 401 });

    const { data: myRoles } = await supabase.from("user_roles").select("roles(code)").eq("is_active", true);
    if (!hasAdmin(myRoles as { roles: RoleRel }[] | null))
      return NextResponse.json({ error: "Apenas administradores podem criar usuários." }, { status: 403 });

    const { full_name = "", email, password, role_codes = [], business_unit_ids = [] } = await request.json();
    if (!email || typeof password !== "string" || password.length < 6)
      return NextResponse.json({ error: "Informe e-mail e senha (mínimo 6 caracteres)." }, { status: 400 });

    const admin = createAdminClient();

    // 1) cria o login (e-mail já confirmado, sem precisar de SMTP).
    const { data: created, error: cErr } = await admin.auth.admin.createUser({
      email, password, email_confirm: true, user_metadata: { full_name },
    });
    if (cErr || !created.user)
      return NextResponse.json({ error: cErr?.message ?? "Falha ao criar usuário." }, { status: 400 });
    const newId = created.user.id;

    // o trigger handle_new_user já cria o profile; reforçamos o nome.
    await admin.from("profiles").update({ full_name }).eq("id", newId);

    // 2) papéis (converte códigos em ids).
    if (Array.isArray(role_codes) && role_codes.length > 0) {
      const { data: roles } = await admin.from("roles").select("id,code").in("code", role_codes);
      const rows = (roles ?? []).map((r) => ({ user_id: newId, role_id: r.id, created_by: user.id }));
      if (rows.length > 0) {
        const { error } = await admin.from("user_roles").insert(rows);
        if (error) return NextResponse.json({ error: error.message }, { status: 400 });
      }
    }

    // 3) unidades de negócio que ele enxerga.
    if (Array.isArray(business_unit_ids) && business_unit_ids.length > 0) {
      const rows = business_unit_ids.map((bu: string) => ({ user_id: newId, business_unit_id: bu }));
      const { error } = await admin.from("user_business_units").insert(rows);
      if (error) return NextResponse.json({ error: error.message }, { status: 400 });
    }

    return NextResponse.json({ id: newId });
  } catch (e) {
    // Qualquer erro inesperado (ex.: SUPABASE_SERVICE_ROLE_KEY ausente) vira JSON legível.
    return NextResponse.json(
      { error: e instanceof Error ? e.message : "Erro inesperado no servidor." }, { status: 500 });
  }
}
