"use client";
import { createContext, useContext, type ReactNode } from "react";

export type Role = "ADMINISTRADOR" | "REQUISITANTE" | "GESTOR_SETOR" | "COMPRADOR"
  | "COORDENADOR_COMPRAS" | "APROVADOR_FINANCEIRO" | "AUDITOR";

const RolesContext = createContext<Role[]>([]);

export function RolesProvider({ roles, children }: { roles: Role[]; children: ReactNode }) {
  return <RolesContext.Provider value={roles}>{children}</RolesContext.Provider>;
}
export const useRoles = () => useContext(RolesContext);
export function useHasRole(...any: Role[]) {
  const roles = useRoles();
  return any.some((r) => roles.includes(r));
}
