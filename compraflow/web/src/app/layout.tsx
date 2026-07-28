import "./globals.css";
import type { Metadata } from "next";
import { QueryProvider } from "@/lib/query-provider";
export const metadata: Metadata = { title: "CompraFlow", description: "Gestão de compras corporativas" };
export default function RootLayout({ children }: { children: React.ReactNode }) {
  return <html lang="pt-BR"><body><QueryProvider>{children}</QueryProvider></body></html>;
}
