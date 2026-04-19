"use client";
import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { RefreshButton } from "@/components/refresh-button";
import type { AdminTicketListResponse, TicketSummary, TicketStatus, TicketType } from "@/lib/types";

const STATUS_META: Record<TicketStatus, { label: string; variant: "default" | "secondary" | "destructive" | "outline" }> = {
  open: { label: "جديدة", variant: "default" },
  in_progress: { label: "جاري العمل", variant: "secondary" },
  resolved: { label: "تم الحل", variant: "outline" },
  closed: { label: "مغلقة", variant: "destructive" },
};

const TYPE_META: Record<TicketType, string> = {
  contact: "استفسار",
  suggestion: "اقتراح",
  bug: "بلاغ خطأ",
  other: "أخرى",
};

export default function TicketsPage() {
  const [tickets, setTickets] = useState<TicketSummary[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState<string>("");
  const [typeFilter, setTypeFilter] = useState<string>("");

  const load = useCallback(async () => {
    const params = new URLSearchParams({ page: String(page), per_page: "20" });
    if (statusFilter) params.set("status", statusFilter);
    if (typeFilter) params.set("ticket_type", typeFilter);
    const r = await api<AdminTicketListResponse>(`/admin/tickets?${params}`);
    setTickets(r.tickets);
    setTotal(r.total);
  }, [page, statusFilter, typeFilter]);

  useEffect(() => { load(); }, [load]);

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">الرسائل / التكتات</h1>
        <RefreshButton onRefresh={load} />
      </div>
      <Card className="p-6">
        <div className="flex items-center gap-3 mb-6 flex-wrap">
          <select
            className="h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm"
            value={statusFilter}
            onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
          >
            <option value="">كل الحالات</option>
            <option value="open">جديدة</option>
            <option value="in_progress">جاري العمل</option>
            <option value="resolved">تم الحل</option>
            <option value="closed">مغلقة</option>
          </select>
          <select
            className="h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm"
            value={typeFilter}
            onChange={(e) => { setTypeFilter(e.target.value); setPage(1); }}
          >
            <option value="">كل الأنواع</option>
            <option value="contact">استفسار</option>
            <option value="suggestion">اقتراح</option>
            <option value="bug">بلاغ خطأ</option>
            <option value="other">أخرى</option>
          </select>
          <span className="text-sm text-gray-500 mr-auto">{total} رسالة</span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-gray-500">
                <th className="text-right pb-3">العنوان</th>
                <th className="text-right pb-3">المستخدم</th>
                <th className="text-right pb-3">النوع</th>
                <th className="text-right pb-3">الحالة</th>
                <th className="text-right pb-3">الردود</th>
                <th className="text-right pb-3">آخر رد</th>
                <th className="text-right pb-3">التاريخ</th>
              </tr>
            </thead>
            <tbody>
              {tickets.map((t) => {
                const meta = STATUS_META[t.status] || STATUS_META.open;
                return (
                  <tr key={t.public_id} className="border-b last:border-0 hover:bg-gray-50">
                    <td className="py-3 font-medium">
                      <Link href={`/tickets/${t.public_id}`} className="hover:underline text-blue-700 block max-w-[260px] truncate">
                        {t.subject}
                      </Link>
                    </td>
                    <td className="py-3">
                      {t.username ? (
                        <Link href={`/users/${t.user_public_id || ""}`} className="hover:underline">
                          {t.username}
                        </Link>
                      ) : (
                        <span className="text-gray-400">—</span>
                      )}
                    </td>
                    <td className="py-3"><Badge variant="outline">{TYPE_META[t.ticket_type]}</Badge></td>
                    <td className="py-3"><Badge variant={meta.variant}>{meta.label}</Badge></td>
                    <td className="py-3 text-center">{t.reply_count}</td>
                    <td className="py-3 text-gray-500 text-xs">{t.last_reply_at ? new Date(t.last_reply_at).toLocaleString("ar") : "—"}</td>
                    <td className="py-3 text-gray-500 text-xs">{t.created_at ? new Date(t.created_at).toLocaleDateString("ar") : "—"}</td>
                  </tr>
                );
              })}
              {tickets.length === 0 && (
                <tr><td colSpan={7} className="py-8 text-center text-gray-400">لا توجد رسائل</td></tr>
              )}
            </tbody>
          </table>
        </div>
        <div className="flex items-center justify-between mt-4">
          <Button variant="outline" size="sm" disabled={page === 1} onClick={() => setPage(page - 1)}>السابق</Button>
          <span className="text-sm text-gray-500">صفحة {page} من {Math.ceil(total / 20) || 1}</span>
          <Button variant="outline" size="sm" disabled={page * 20 >= total} onClick={() => setPage(page + 1)}>التالي</Button>
        </div>
      </Card>
    </div>
  );
}
