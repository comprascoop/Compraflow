import type { RequestStatus, SupplierStatus } from "@/lib/types";

const REQUEST_LABEL: Record<RequestStatus, string> = {
  RASCUNHO: "Rascunho", ENVIADA: "Enviada",
  AGUARDANDO_APROVACAO_DO_SETOR: "Aprovação do setor", EM_ANALISE_POR_COMPRAS: "Em análise (compras)",
  AGUARDANDO_INFORMACOES: "Aguardando informações", EM_COTACAO: "Em cotação",
  COTACOES_RECEBIDAS: "Cotações recebidas", EM_ANALISE_DE_COTACOES: "Análise de cotações",
  AGUARDANDO_APROVACAO_TECNICA: "Aprovação técnica", AGUARDANDO_APROVACAO_FINANCEIRA: "Aprovação financeira",
  APROVADA: "Aprovada", REJEITADA: "Rejeitada", PEDIDO_EMITIDO: "Pedido emitido",
  EM_ENTREGA: "Em entrega", RECEBIDA: "Recebida", ENCERRADA: "Encerrada", CANCELADA: "Cancelada",
};
const TONE = {
  neutral: "bg-slate-100 text-slate-700", blue: "bg-blue-50 text-blue-700",
  amber: "bg-amber-50 text-amber-700", green: "bg-emerald-50 text-emerald-700", red: "bg-rose-50 text-rose-700",
};
function requestTone(s: RequestStatus) {
  if (s === "RASCUNHO") return TONE.neutral;
  if (["REJEITADA","CANCELADA"].includes(s)) return TONE.red;
  if (["APROVADA","RECEBIDA","ENCERRADA"].includes(s)) return TONE.green;
  if (s.startsWith("AGUARDANDO")) return TONE.amber;
  return TONE.blue;
}
export function StatusBadge({ status }: { status: RequestStatus }) {
  return <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${requestTone(status)}`}>{REQUEST_LABEL[status]}</span>;
}
const SUPPLIER_LABEL: Record<SupplierStatus, string> = {
  EM_CADASTRO: "Em cadastro", PENDENTE_DE_HOMOLOGACAO: "Pendente homologação", HOMOLOGADO: "Homologado",
  HOMOLOGADO_COM_RESTRICAO: "Homologado c/ restrição", BLOQUEADO: "Bloqueado", INATIVO: "Inativo",
};
export function SupplierBadge({ status }: { status: SupplierStatus }) {
  const tone = status === "HOMOLOGADO" ? TONE.green
    : ["BLOQUEADO","INATIVO"].includes(status) ? TONE.red
    : status === "HOMOLOGADO_COM_RESTRICAO" ? TONE.amber : TONE.neutral;
  return <span className={`inline-flex rounded-full px-2 py-0.5 text-xs font-medium ${tone}`}>{SUPPLIER_LABEL[status]}</span>;
}
export const priorityLabel: Record<string, string> = { BAIXA: "Baixa", NORMAL: "Normal", ALTA: "Alta", CRITICA: "Crítica" };
