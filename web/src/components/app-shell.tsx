"use client";
import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { LayoutDashboard, FileText, Inbox, Building2, LogOut, ShoppingCart, CheckSquare, Bell, Settings } from "lucide-react";
import { signOut } from "@/services/auth";
import type { ReactNode } from "react";

const NAV = [
  { href: "/dashboard", label: "Painel", icon: LayoutDashboard },
  { href: "/demandas", label: "Demandas", icon: FileText },
  { href: "/fila", label: "Fila de compras", icon: Inbox },
  { href: "/aprovacoes", label: "Aprovações", icon: CheckSquare },
  { href: "/fornecedores", label: "Fornecedores", icon: Building2 },
  { href: "/notificacoes", label: "Notificações", icon: Bell },
  { href: "/admin", label: "Administração", icon: Settings },
];

export function AppShell({ children, email }: { children: ReactNode; email: string }) {
  const pathname = usePathname();
  const router = useRouter();
  async function handleSignOut() { await signOut(); router.push("/login"); router.refresh(); }
  return (
    <div className="flex min-h-screen">
      <aside className="hidden w-60 shrink-0 flex-col border-r bg-slate-50 md:flex">
        <div className="flex h-14 items-center gap-2 border-b px-4">
          <ShoppingCart className="h-5 w-5 text-primary" />
          <span className="font-semibold">CompraFlow</span>
        </div>
        <nav className="flex-1 space-y-1 p-3">
          {NAV.map(({ href, label, icon: Icon }) => {
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
