import Link from "next/link";
export default function NotFound() {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center gap-3 text-center">
      <p className="text-3xl font-semibold">404</p>
      <p className="text-slate-500">Página não encontrada.</p>
      <Link href="/dashboard" className="btn-primary">Voltar ao painel</Link>
    </div>
  );
}
