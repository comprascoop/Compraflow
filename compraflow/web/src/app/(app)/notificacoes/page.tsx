"use client";
import Link from "next/link";
import { useQuery, useQueryClient, useMutation } from "@tanstack/react-query";
import { listNotifications, markAllRead } from "@/services/notifications";
import { dateTimeBR } from "@/lib/format";
import { EmptyState } from "@/components/empty-state";

export default function NotificacoesPage() {
  const qc = useQueryClient();
  const { data = [], isLoading } = useQuery({ queryKey: ["notifications"], queryFn: listNotifications });
  const doRead = useMutation({
    mutationFn: markAllRead,
    onSuccess: () => qc.invalidateQueries({ queryKey: ["notifications"] }),
  });
  const unread = data.filter((n) => !n.read_at).length;

  if (isLoading) return <div className="h-40 animate-pulse rounded-lg bg-muted" />;
  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-semibold">Notificações</h1>
          <p className="text-sm text-slate-500">{unread} não lida(s)</p>
        </div>
        {unread > 0 && <button className="btn-ghost" onClick={() => doRead.mutate()}>Marcar todas como lidas</button>}
      </div>
      {data.length === 0 ? <EmptyState title="Nenhuma notificação" /> : (
        <div className="card divide-y">
          {data.map((n) => (
            <div key={n.id} className={`p-4 ${n.read_at ? "" : "bg-blue-50/40"}`}>
              <div className="flex items-start justify-between gap-3">
                <div>
                  <p className="font-medium">{n.title}</p>
                  {n.body && <p className="text-sm text-slate-600">{n.body}</p>}
                  <p className="mt-1 text-xs text-slate-400">{dateTimeBR(n.created_at)}</p>
                </div>
                {n.link && <Link href={n.link} className="text-sm text-primary hover:underline">Abrir</Link>}
              </div>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
