import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { AppShell } from "@/components/app-shell";
import { RolesProvider, type Role } from "@/lib/use-roles";

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data } = await supabase.from("user_roles")
    .select("roles(code)").eq("is_active", true);
  // o join volta como array na tipagem do supabase-js; normalizamos.
  const roles = (data ?? []).flatMap((r: { roles: { code: string }[] | { code: string } | null }) => {
    const rel = r.roles;
    if (!rel) return [];
    return Array.isArray(rel) ? rel.map((x) => x.code) : [rel.code];
  }).filter(Boolean) as Role[];

  return (
    <RolesProvider roles={roles}>
      <AppShell email={user.email ?? ""} roles={roles}>{children}</AppShell>
    </RolesProvider>
  );
}
