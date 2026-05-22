"use client";
import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { RefreshButton } from "@/components/refresh-button";
import { TICKET_STATUS_LABEL, TICKET_TYPE_LABEL } from "@/lib/labels";
import { formatDateTime, formatNumber } from "@/lib/format";
import type { AdminTicketListResponse, TicketSummary, TicketStatus } from "@/lib/types";

const STATUS_VARIANT: Record<TicketStatus, "default" | "secondary" | "destructive" | "outline"> = {
  open: "default",
  in_progress: "secondary",
  resolved: "outline",
  closed: "destructive",
};

const PER_PAGE = 20;

export default function TicketsPage() {
  const [tickets, setTickets] = useState<TicketSummary[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [statusFilter, setStatusFilter] = useState<string>("");
  const [typeFilter, setTypeFilter] = useState<string>("");

  const load = useCallback(async () => {
    const params = new URLSearchParams({ page: String(page), per_page: String(PER_PAGE) });
    if (statusFilter) params.set("status", statusFilter);
    if (typeFilter) params.set("ticket_type", typeFilter);
    const r = await api<AdminTicketListResponse>(`/admin/tickets?${params}`);
    setTickets(r.tickets);
    setTotal(r.total);
  }, [page, statusFilter, typeFilter]);

  useEffect(() => { load(); }, [load]);

  const totalPages = Math.ceil(total / PER_PAGE) || 1;
  const showPagination = total > PER_PAGE;
  const hasFilter = !!statusFilter || !!typeFilter;
  const isEmpty = !hasFilter && total === 0;

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
            aria-label="فلترة بالحالة"
          >
            <option value="">كل الحالات</option>
            {Object.entries(TICKET_STATUS_LABEL).map(([k, v]) => (
              <option key={k} value={k}>{v}</option>
            ))}
          </select>
          <select
            className="h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm"
            value={typeFilter}
            onChange={(e) => { setTypeFilter(e.target.value); setPage(1); }}
            aria-label="فلترة بالنوع"
          >
            <option value="">كل الأنواع</option>
            {Object.entries(TICKET_TYPE_LABEL).map(([k, v]) => (
              <option key={k} value={k}>{v}</option>
            ))}
          </select>
          <span className="text-sm text-gray-500 mr-auto">{formatNumber(total)} رسالة</span>
        </div>

        {isEmpty ? (
          <div className="py-16 text-center">
            <div className="text-5xl mb-3">📭</div>
            <p className="text-gray-500">لا توجد رسائل بعد</p>
            <p className="text-xs text-gray-400 mt-1">ستظهر هنا كل التكتات والاستفسارات الواردة</p>
          </div>
        ) : (
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
                {tickets.map((t) => (
                  <tr key={t.public_id} className="border-b last:border-0 hover:bg-gray-50">
                    <td className="py-3 font-medium">
                      <Link href={`/tickets/${t.public_id}`} className="hover:underline text-blue-700 block max-w-[260px] truncate">
                        {t.subject}
                      </Link>
                    </td>
                    <td className="py-3">
                      {(t.user_full_name || t.user_email) ? (
                        <Link href={`/users/${t.user_public_id || ""}`} className="hover:underline">
                          {t.user_full_name || t.user_email}
                        </Link>
                      ) : (
                        <span className="text-gray-400">—</span>
                      )}
                    </td>
                    <td className="py-3"><Badge variant="outline">{TICKET_TYPE_LABEL[t.ticket_type] || t.ticket_type}</Badge></td>
                    <td className="py-3"><Badge variant={STATUS_VARIANT[t.status] || "default"}>{TICKET_STATUS_LABEL[t.status] || t.status}</Badge></td>
                    <td className="py-3 text-center">{formatNumber(t.reply_count)}</td>
                    <td className="py-3 text-gray-500 text-xs">{formatDateTime(t.last_reply_at)}</td>
                    <td className="py-3 text-gray-500 text-xs">{formatDateTime(t.created_at)}</td>
                  </tr>
                ))}
                {tickets.length === 0 && (
                  <tr><td colSpan={7} className="py-8 text-center text-gray-400">لا توجد رسائل بهذه الفلترة</td></tr>
                )}
              </tbody>
            </table>
          </div>
        )}

        {showPagination && (
          <div className="flex items-center justify-between mt-4">
            <Button variant="outline" size="sm" disabled={page === 1} onClick={() => setPage(page - 1)}>السابق</Button>
            <span className="text-sm text-gray-500">صفحة {formatNumber(page)} من {formatNumber(totalPages)}</span>
            <Button variant="outline" size="sm" disabled={page * PER_PAGE >= total} onClick={() => setPage(page + 1)}>التالي</Button>
          </div>
        )}
      </Card>
    </div>
  );
}
