"use client";
import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { RefreshButton } from "@/components/refresh-button";
import type { RequestItem, PaginatedResponse } from "@/lib/types";

const REFRESH_INTERVAL_MS = 5000;

const STATUS_META: Record<RequestItem["status"], { label: string; variant: "default" | "secondary" | "destructive"; pulse?: boolean }> = {
  processing: { label: "جاري", variant: "secondary", pulse: true },
  completed: { label: "مكتمل", variant: "default" },
  failed: { label: "فشل", variant: "destructive" },
};

const PLAN_LABEL: Record<string, string> = {
  free: "مجاني",
  monthly: "شهري",
  annual: "سنوي",
};

const SOURCE_LABEL: Record<RequestItem["plan_source"], string> = {
  free: "—",
  coupon: "كوبون",
  purchase: "مدفوع",
};

export default function RequestsPage() {
  const [requests, setRequests] = useState<RequestItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [langFilter, setLangFilter] = useState("");
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null);

  const fetchRequests = useCallback(async () => {
    const params = new URLSearchParams({ page: String(page), per_page: "20" });
    if (langFilter) params.set("language", langFilter);
    const r = await api<PaginatedResponse<RequestItem>>(`/admin/requests?${params}`);
    setRequests(r.requests || []);
    setTotal(r.total);
    setLastRefresh(new Date());
  }, [page, langFilter]);

  useEffect(() => {
    fetchRequests().catch(() => {});
    const id = setInterval(() => {
      fetchRequests().catch(() => {});
    }, REFRESH_INTERVAL_MS);
    return () => clearInterval(id);
  }, [fetchRequests]);

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">سجل الطلبات</h1>
        <RefreshButton onRefresh={fetchRequests} />
      </div>
      <Card className="p-6">
        <div className="flex items-center gap-4 mb-6 flex-wrap">
          <Input placeholder="فلتر حسب اللغة (ar, en...)" value={langFilter} onChange={(e) => { setLangFilter(e.target.value); setPage(1); }} className="max-w-xs" />
          <span className="text-sm text-gray-500">{total} طلب</span>
          {lastRefresh && (
            <span className="text-xs text-gray-400 mr-auto inline-flex items-center gap-1">
              <span className="inline-block h-2 w-2 rounded-full bg-green-500 animate-pulse" />
              آخر تحديث: {lastRefresh.toLocaleTimeString("ar")}
            </span>
          )}
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-gray-500">
                <th className="text-right pb-3">#</th>
                <th className="text-right pb-3">الحالة</th>
                <th className="text-right pb-3">المستخدم</th>
                <th className="text-right pb-3">الباقة</th>
                <th className="text-right pb-3">الملف</th>
                <th className="text-right pb-3">المدة</th>
                <th className="text-right pb-3">المعالج</th>
                <th className="text-right pb-3">اللغة</th>
                <th className="text-right pb-3">استخدام اليوم</th>
                <th className="text-right pb-3">الكلمات</th>
                <th className="text-right pb-3">مقصوص</th>
                <th className="text-right pb-3">التاريخ</th>
              </tr>
            </thead>
            <tbody>
              {requests.map((r) => {
                const statusMeta = STATUS_META[r.status] || STATUS_META.completed;
                const planLabel = PLAN_LABEL[r.plan_name] || r.plan_name;
                const isPaid = r.plan_source !== "free";
                const limitText = r.daily_limit === -1 ? "∞" : String(r.daily_limit);
                const overLimit = r.daily_limit !== -1 && r.daily_used >= r.daily_limit;
                return (
                  <tr key={r.id} className="border-b last:border-0">
                    <td className="py-3 text-gray-400">{r.id}</td>
                    <td className="py-3">
                      <Badge variant={statusMeta.variant} className={statusMeta.pulse ? "animate-pulse" : ""} title={r.error_message || undefined}>
                        {statusMeta.label}
                      </Badge>
                    </td>
                    <td className="py-3 font-medium">
                      {r.user_public_id ? (
                        <Link href={`/users/${r.user_public_id}`} className="hover:underline text-blue-700">{r.username}</Link>
                      ) : (
                        r.username
                      )}
                    </td>
                    <td className="py-3">
                      <div className="flex flex-col gap-1 items-start">
                        <Badge variant={isPaid ? "default" : "outline"}>{planLabel}</Badge>
                        {isPaid && (
                          <Badge variant="secondary" className="text-[10px]">
                            {SOURCE_LABEL[r.plan_source]}
                          </Badge>
                        )}
                      </div>
                    </td>
                    <td className="py-3 text-gray-500 max-w-[120px] truncate">{r.filename || "-"}</td>
                    <td className="py-3">{r.duration_seconds.toFixed(1)}ث</td>
                    <td className="py-3">{r.processed_seconds.toFixed(1)}ث</td>
                    <td className="py-3"><Badge variant="secondary">{r.language || "-"}</Badge></td>
                    <td className={`py-3 font-medium ${overLimit ? "text-red-600" : "text-gray-700"}`}>
                      {r.daily_used} / {limitText}
                    </td>
                    <td className="py-3">{r.word_count}</td>
                    <td className="py-3">{r.was_trimmed ? <Badge variant="destructive">نعم</Badge> : "—"}</td>
                    <td className="py-3 text-gray-500 text-xs">{new Date(r.created_at).toLocaleString("ar")}</td>
                  </tr>
                );
              })}
              {requests.length === 0 && (
                <tr><td colSpan={12} className="py-8 text-center text-gray-400">لا توجد طلبات</td></tr>
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
