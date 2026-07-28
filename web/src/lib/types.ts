export type RequestStatus =
  | "RASCUNHO" | "ENVIADA" | "AGUARDANDO_APROVACAO_DO_SETOR" | "EM_ANALISE_POR_COMPRAS"
  | "AGUARDANDO_INFORMACOES" | "EM_COTACAO" | "COTACOES_RECEBIDAS" | "EM_ANALISE_DE_COTACOES"
  | "AGUARDANDO_APROVACAO_TECNICA" | "AGUARDANDO_APROVACAO_FINANCEIRA" | "APROVADA" | "REJEITADA"
  | "PEDIDO_EMITIDO" | "EM_ENTREGA" | "RECEBIDA" | "ENCERRADA" | "CANCELADA";
export type Priority = "BAIXA" | "NORMAL" | "ALTA" | "CRITICA";
export type SupplierStatus = "EM_CADASTRO" | "PENDENTE_DE_HOMOLOGACAO" | "HOMOLOGADO"
  | "HOMOLOGADO_COM_RESTRICAO" | "BLOQUEADO" | "INATIVO";
export type ApprovalDecision = "APROVADO" | "REJEITADO" | "AJUSTE_SOLICITADO" | "ENCAMINHADO";

export interface PurchaseRequest {
  id: string; number: string | null; title: string; requester_name: string | null;
  status: RequestStatus; priority: Priority;
  purchase_type: string; department_id: string; cost_center_id: string | null;
  category_id: string | null; needed_at: string | null; is_emergency: boolean;
  estimated_total: number; assigned_buyer_id: string | null; created_by: string; created_at: string;
}
export interface PurchaseRequestItem {
  id: string; request_id: string; line_no: number; description: string;
  quantity: number; unit_price: number; total_estimated: number;
}
export interface Supplier {
  id: string; legal_name: string; trade_name: string | null; cnpj: string;
  city: string | null; state: string | null; status: SupplierStatus; rating: number | null;
  average_lead_time_days: number | null; default_payment_terms: string | null;
}
export interface StatusHistory {
  id: number; request_id: string; from_status: RequestStatus | null;
  to_status: RequestStatus; comment: string | null; created_at: string;
}
export interface SourcingRound {
  id: string; request_id: string; round_no: number; mode: string;
  deadline_at: string | null; is_open: boolean; opened_at: string | null;
}
export interface ComparisonQuote {
  request_id: string; quote_id: string; supplier_id: string; supplier_name: string;
  supplier_status: SupplierStatus; supplier_rating: number | null;
  items_subtotal: number; discount_amount: number; taxes_amount: number;
  freight_amount: number; insurance_amount: number; total_cost: number;
  payment_terms: string | null; delivery_days: number | null; valid_until: string | null;
  status: string; items_quoted: number; items_requested: number;
  savings_vs_estimate: number; diff_to_lowest: number;
}
export interface ComparisonItem {
  request_item_id: string; line_no: number; item_description: string;
  quantity_requested: number; quote_id: string; supplier_id: string; supplier_name: string;
  unit_price: number; quantity_offered: number; line_total: number;
  delivery_days: number | null; technical_fit: string; unavailable: boolean;
  best_unit_price: number | null; best_delivery_days: number | null;
}
export interface ApprovalInstance {
  id: string; request_id: string; recommendation_id: string; amount: number;
  status: string; current_step: number; created_at: string;
}
export interface Department { id: string; name: string }
export interface CostCenter { id: string; name: string; code: string; department_id: string }
export interface Category { id: string; name: string }
export interface Unit { id: string; code: string; name: string }
