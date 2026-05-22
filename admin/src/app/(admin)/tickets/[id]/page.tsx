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
import { toast } from "@/components/toast";
import { TICKET_STATUS_LABEL, TICKET_TYPE_LABEL } from "@/lib/labels";
import { formatDateTime } from "@/lib/format";
import type { TicketAttachmentItem, TicketDetail, TicketStatus } from "@/lib/types";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "/api/v1";

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
    const trimmed = reply.trim();
    if (!trimmed) return;
    setSending(true);
    try {
      await api(`/admin/tickets/${id}/replies`, { method: "POST", body: JSON.stringify({ message: trimmed }) });
      toast.success("تم إرسال الرد");
      setReply("");
      await load();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "فشل الإرسال");
    } finally {
      setSending(false);
    }
  }

  async function changeStatus(newStatus: TicketStatus) {
    setSavingStatus(true);
    try {
      await api(`/admin/tickets/${id}/status`, { method: "PUT", body: JSON.stringify({ status: newStatus }) });
      toast.success("تم تحديث الحالة");
      await load();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "فشل تحديث الحالة");
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
            aria-label="تغيير حالة التكت"
          >
            {(Object.keys(TICKET_STATUS_LABEL) as TicketStatus[]).map((s) => (
              <option key={s} value={s}>{TICKET_STATUS_LABEL[s]}</option>
            ))}
          </select>
        </div>
      </div>

      <Card className="p-6">
        <div className="flex items-start justify-between mb-4">
          <div className="flex-1">
            <h1 className="text-xl font-bold mb-2">{ticket.subject}</h1>
            <div className="flex gap-2 items-center text-sm">
              <Badge variant="outline">{TICKET_TYPE_LABEL[ticket.ticket_type] || ticket.ticket_type}</Badge>
              <Badge>{TICKET_STATUS_LABEL[ticket.status] || ticket.status}</Badge>
              {(ticket.user_full_name || ticket.user_email) && (
                <>
                  <span className="text-gray-400">·</span>
                  <Link href={`/users/${ticket.user_public_id || ""}`} className="text-blue-700 hover:underline">
                    {ticket.user_full_name || ticket.user_email}
                  </Link>
                </>
              )}
              {ticket.created_at && (
                <>
                  <span className="text-gray-400">·</span>
                  <span className="text-gray-500 text-xs">{formatDateTime(ticket.created_at)}</span>
                </>
              )}
            </div>
          </div>
        </div>

        <div className="space-y-3">
          {/* الرسالة الأصلية */}
          <MessageBubble
            authorName={ticket.user_full_name || ticket.user_email || "مستخدم"}
            isAdmin={false}
            message={ticket.message}
            createdAt={ticket.created_at}
            attachments={ticket.attachments}
            ticketPublicId={ticket.public_id}
          />

          {/* الردود */}
          {ticket.replies.map((r, i) => (
            <MessageBubble
              key={r.public_id || i}
              authorName={r.author_name || (r.is_admin ? "فريق الدعم" : "مستخدم")}
              isAdmin={r.is_admin}
              message={r.message}
              createdAt={r.created_at}
              attachments={r.attachments}
              ticketPublicId={ticket.public_id}
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
              aria-label="نص الرد"
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

function MessageBubble({
  authorName,
  isAdmin,
  message,
  createdAt,
  attachments,
  ticketPublicId,
}: {
  authorName: string;
  isAdmin: boolean;
  message: string;
  createdAt: string | null | undefined;
  attachments?: TicketAttachmentItem[];
  ticketPublicId: string;
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
        {attachments && attachments.length > 0 && (
          <div className="mt-2 flex flex-wrap gap-2">
            {attachments.map((a) => (
              <AttachmentThumb
                key={a.public_id}
                attachment={a}
                ticketPublicId={ticketPublicId}
              />
            ))}
          </div>
        )}
        {createdAt && (
          <p className="text-[10px] text-gray-400 mt-1">{formatDateTime(createdAt)}</p>
        )}
      </div>
    </div>
  );
}

/// Authenticated <img>: the attachment endpoint requires Bearer auth, so a
/// plain <img src=...> won't load. We fetch the bytes with the token, turn
/// them into an object URL, and revoke it on unmount.
function AttachmentThumb({
  attachment,
  ticketPublicId,
}: {
  attachment: TicketAttachmentItem;
  ticketPublicId: string;
}) {
  const [src, setSrc] = useState<string | null>(null);
  const [error, setError] = useState(false);

  useEffect(() => {
    let cancelled = false;
    let objectUrl: string | null = null;
    (async () => {
      try {
        const token = localStorage.getItem("admin_token");
        const res = await fetch(
          `${API_BASE}/admin/tickets/${ticketPublicId}/attachments/${attachment.public_id}`,
          { headers: token ? { Authorization: `Bearer ${token}` } : undefined },
        );
        if (!res.ok) throw new Error(`status ${res.status}`);
        const blob = await res.blob();
        if (cancelled) return;
        objectUrl = URL.createObjectURL(blob);
        setSrc(objectUrl);
      } catch {
        if (!cancelled) setError(true);
      }
    })();
    return () => {
      cancelled = true;
      if (objectUrl) URL.revokeObjectURL(objectUrl);
    };
  }, [attachment.public_id, ticketPublicId]);

  if (error) {
    return (
      <div className="w-24 h-24 rounded-lg bg-red-50 border border-red-200 flex items-center justify-center text-xs text-red-600">
        تعذّر التحميل
      </div>
    );
  }
  if (!src) {
    return (
      <div className="w-24 h-24 rounded-lg bg-gray-200 animate-pulse" />
    );
  }
  return (
    <a href={src} target="_blank" rel="noreferrer" className="block">
      {/* eslint-disable-next-line @next/next/no-img-element */}
      <img
        src={src}
        alt={attachment.original_filename || "attachment"}
        className="w-24 h-24 rounded-lg object-cover border border-gray-200 hover:opacity-90 transition"
      />
    </a>
  );
}
