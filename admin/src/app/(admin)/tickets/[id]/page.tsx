"use client";
import { useEffect, useState, useCallback } from "react";
import { useParams, useRouter } from "next/navigation";
import Link from "next/link";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { RefreshButton } from "@/components/refresh-button";
import type { TicketDetail, TicketStatus } from "@/lib/types";

const STATUS_LABEL: Record<TicketStatus, string> = {
  open: "جديدة",
  in_progress: "جاري العمل",
  resolved: "تم الحل",
  closed: "مغلقة",
};

const TYPE_LABEL: Record<string, string> = {
  contact: "استفسار",
  suggestion: "اقتراح",
  bug: "بلاغ خطأ",
  other: "أخرى",
};

export default function AdminTicketDetail() {
  const { id } = useParams();
  const router = useRouter();
  const [ticket, setTicket] = useState<TicketDetail | null>(null);
  const [reply, setReply] = useState("");
  const [sending, setSending] = useState(false);
  const [savingStatus, setSavingStatus] = useState(false);

  const load = useCallback(async () => {
    const t = await api<TicketDetail>(`/admin/tickets/${id}`);
    setTicket(t);
  }, [id]);

  useEffect(() => { load(); }, [load]);

  async function sendReply() {
    if (!reply.trim()) return;
    setSending(true);
    try {
      await api(`/admin/tickets/${id}/replies`, { method: "POST", body: JSON.stringify({ message: reply }) });
      setReply("");
      await load();
    } catch (e) {
      alert(e instanceof Error ? e.message : "فشل الإرسال");
    } finally {
      setSending(false);
    }
  }

  async function changeStatus(newStatus: TicketStatus) {
    setSavingStatus(true);
    try {
      await api(`/admin/tickets/${id}/status`, { method: "PUT", body: JSON.stringify({ status: newStatus }) });
      await load();
    } finally {
      setSavingStatus(false);
    }
  }

  if (!ticket) return <div className="flex items-center justify-center h-64"><div className="animate-spin w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full" /></div>;

  const isClosed = ticket.status === "closed";

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <Button variant="outline" size="sm" onClick={() => router.back()}>← رجوع</Button>
        <div className="flex gap-2">
          <RefreshButton onRefresh={load} />
          <select
            className="h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm"
            value={ticket.status}
            onChange={(e) => changeStatus(e.target.value as TicketStatus)}
            disabled={savingStatus}
          >
            {(Object.keys(STATUS_LABEL) as TicketStatus[]).map((s) => (
              <option key={s} value={s}>{STATUS_LABEL[s]}</option>
            ))}
          </select>
        </div>
      </div>

      <Card className="p-6">
        <div className="flex items-start justify-between mb-4">
          <div className="flex-1">
            <h1 className="text-xl font-bold mb-2">{ticket.subject}</h1>
            <div className="flex gap-2 items-center text-sm">
              <Badge variant="outline">{TYPE_LABEL[ticket.ticket_type] || ticket.ticket_type}</Badge>
              <Badge>{STATUS_LABEL[ticket.status]}</Badge>
              {ticket.username && (
                <>
                  <span className="text-gray-400">·</span>
                  <Link href={`/users/${ticket.user_public_id || ""}`} className="text-blue-700 hover:underline">
                    {ticket.username}
                  </Link>
                </>
              )}
              {ticket.created_at && (
                <>
                  <span className="text-gray-400">·</span>
                  <span className="text-gray-500 text-xs">{new Date(ticket.created_at).toLocaleString("ar")}</span>
                </>
              )}
            </div>
          </div>
        </div>

        <div className="space-y-3">
          {/* Initial message */}
          <MessageBubble
            authorName={ticket.username || "مستخدم"}
            isAdmin={false}
            message={ticket.message}
            createdAt={ticket.created_at}
          />

          {/* Replies */}
          {ticket.replies.map((r, i) => (
            <MessageBubble
              key={r.public_id || i}
              authorName={r.author_name || (r.is_admin ? "فريق الدعم" : "مستخدم")}
              isAdmin={r.is_admin}
              message={r.message}
              createdAt={r.created_at}
            />
          ))}
        </div>

        <hr className="my-4" />

        {isClosed ? (
          <div className="text-center text-gray-500 py-4 text-sm">الرسالة مغلقة</div>
        ) : (
          <div>
            <Textarea
              value={reply}
              onChange={(e) => setReply(e.target.value)}
              placeholder="اكتب ردك كـ فريق الدعم..."
              rows={3}
            />
            <div className="flex justify-end mt-3">
              <Button onClick={sendReply} disabled={sending || !reply.trim()}>
                {sending ? "جاري الإرسال..." : "إرسال الرد"}
              </Button>
            </div>
          </div>
        )}
      </Card>
    </div>
  );
}

function MessageBubble({ authorName, isAdmin, message, createdAt }: {
  authorName: string;
  isAdmin: boolean;
  message: string;
  createdAt: string | null | undefined;
}) {
  return (
    <div className={`flex ${isAdmin ? "justify-start" : "justify-end"}`}>
      <div className={`max-w-[80%] rounded-xl p-3 ${isAdmin ? "bg-blue-50 border border-blue-100" : "bg-gray-100"}`}>
        <div className="flex items-center gap-1.5 mb-1.5 text-xs">
          <span className={`font-semibold ${isAdmin ? "text-blue-700" : "text-gray-700"}`}>
            {isAdmin ? "🛟 " : "👤 "}{authorName}
          </span>
        </div>
        <p className="text-sm whitespace-pre-wrap leading-relaxed">{message}</p>
        {createdAt && (
          <p className="text-[10px] text-gray-400 mt-1">{new Date(createdAt).toLocaleString("ar")}</p>
        )}
      </div>
    </div>
  );
}
