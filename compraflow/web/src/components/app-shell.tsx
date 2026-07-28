"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { LayoutDashboard, FileText, Inbox, Building2, LogOut, ShoppingCart, CheckSquare, Bell, Settings } from "lucide-react";
import { signOut } from "@/services/auth";
import type { Role } from "@/lib/use-roles";
import type { ReactNode } from "react";

// visible_to = null → todos os papéis veem. Caso contrário, só os listados.
const NAV: { href: string; label: string; icon: typeof LayoutDashboard; visible_to: Role[] | null }[] = [
  { href: "/dashboard",    label: "Painel",           icon: LayoutDashboard, visible_to: null },
  { href: "/demandas",     label: "Demandas",         icon: FileText,        visible_to: null },
  { href: "/fila",         label: "Fila de compras",  icon: Inbox,
    visible_to: ["COMPRADOR", "COORDENADOR_COMPRAS", "ADMINISTRADOR"] },
  { href: "/aprovacoes",   label: "Aprovações",       icon: CheckSquare,
    visible_to: ["APROVADOR_FINANCEIRO", "GESTOR_SETOR", "ADMINISTRADOR"] },
  { href: "/fornecedores", label: "Fornecedores",     icon: Building2,
    visible_to: ["COMPRADOR", "COORDENADOR_COMPRAS", "ADMINISTRADOR", "AUDITOR"] },
  { href: "/notificacoes", label: "Notificações",     icon: Bell,            visible_to: null },
  { href: "/admin",        label: "Administração",    icon: Settings,
    visible_to: ["ADMINISTRADOR"] },
];

export function AppShell({ children, email, roles }: { children: ReactNode; email: string; roles: Role[] }) {
  const pathname = usePathname();
  const router = useRouter();
  async function handleSignOut() { await signOut(); router.push("/login"); router.refresh(); }

  const visible = NAV.filter((n) => n.visible_to === null || n.visible_to.some((r) => roles.includes(r)));

  return (
    <div className="flex min-h-screen">
      <aside className="hidden w-60 shrink-0 flex-col border-r bg-slate-50 md:flex">
        <div className="flex h-14 items-center gap-2 border-b px-4">
          <ShoppingCart className="h-5 w-5 text-primary" />
          <span className="font-semibold">CompraFlow</span>
        </div>
        <nav className="flex-1 space-y-1 p-3">
          {visible.map(({ href, label, icon: Icon }) => {
            const active = pathname.startsWith(href);
            return (
              <Link key={href} href={href}
                className={`flex items-center gap-2.5 rounded-md px-3 py-2 text-sm ${active ? "bg-primary text-primary-fg" : "text-slate-700 hover:bg-slate-200/60"}`}>
                <Icon className="h-4 w-4" /> {label}
              </Link>
            );
          })}
        </nav>
        <div className="border-t p-3">
          <p className="truncate px-2 pb-2 text-xs text-slate-500">{email}</p>
          <button onClick={handleSignOut} className="btn-ghost w-full justify-start"><LogOut className="h-4 w-4" /> Sair</button>
        </div>
      </aside>
      <div className="flex min-w-0 flex-1 flex-col">
        <header className="flex h-14 items-center border-b px-5 md:hidden">
          <ShoppingCart className="mr-2 h-5 w-5 text-primary" /><span className="font-semibold">CompraFlow</span>
        </header>
        <main className="flex-1 bg-white p-5 md:p-8">{children}</main>
      </div>
    </div>
  );
}
