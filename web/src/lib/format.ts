export const brl = (v: number | null | undefined) =>
  new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(Number(v ?? 0));
export const dateBR = (v: string | null | undefined) =>
  v ? new Intl.DateTimeFormat("pt-BR", { timeZone: "America/Sao_Paulo" }).format(new Date(v)) : "—";
export const dateTimeBR = (v: string | null | undefined) =>
  v ? new Intl.DateTimeFormat("pt-BR", { timeZone: "America/Sao_Paulo", dateStyle: "short", timeStyle: "short" }).format(new Date(v)) : "—";
export const cnpjMask = (v: string) =>
  (v || "").replace(/\D/g, "").slice(0, 14).replace(/^(\d{2})(\d{3})(\d{3})(\d{4})(\d{2}).*/, "$1.$2.$3/$4-$5");
