import { createClient } from "@/lib/supabase/client";

export interface Notification {
  id: string; type: string; title: string; body: string | null;
  link: string | null; priority: string; read_at: string | null; created_at: string;
}

export async function listNotifications(): Promise<Notification[]> {
  const { data, error } = await createClient().from("notifications")
    .select("*").order("created_at", { ascending: false }).limit(50);
  if (error) throw error; return data as Notification[];
}
export async function markAllRead(): Promise<number> {
  const { data, error } = await createClient().rpc("fn_mark_notifications_read", { p_ids: null });
  if (error) throw error; return data as number;
}
