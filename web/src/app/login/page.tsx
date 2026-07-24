"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { signIn } from "@/services/auth";
import { ShoppingCart } from "lucide-react";

export default function LoginPage() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function onSubmit() {
    setError(null); setLoading(true);
    try {
      await signIn(email.trim(), password);
      router.push("/dashboard"); router.refresh();
    } catch { setError("E-mail ou senha inválidos."); }
    finally { setLoading(false); }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-slate-50 px-4">
      <div className="card w-full max-w-sm p-7">
        <div className="mb-6 flex items-center gap-2">
          <ShoppingCart className="h-6 w-6 text-primary" /><span className="text-lg font-semibold">CompraFlow</span>
        </div>
        <h1 className="mb-1 text-xl font-semibold">Entrar</h1>
        <p className="mb-6 text-sm text-slate-500">Acesse com seu e-mail corporativo.</p>
        <div className="space-y-3">
          <div>
            <label className="label">E-mail</label>
            <input className="input" type="email" value={email} onChange={(e) => setEmail(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && onSubmit()} />
          </div>
          <div>
            <label className="label">Senha</label>
            <input className="input" type="password" value={password} onChange={(e) => setPassword(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && onSubmit()} />
          </div>
          {error && <p className="text-sm text-rose-600">{error}</p>}
          <button className="btn-primary w-full" onClick={onSubmit} disabled={loading}>
            {loading ? "Entrando…" : "Entrar"}
          </button>
        </div>
        <p className="mt-6 border-t pt-4 text-xs text-slate-500">
          Ambiente local: use <code>comprador@compraflow.local</code> e senha <code>Compra@123</code>.
        </p>
      </div>
    </div>
  );
}
