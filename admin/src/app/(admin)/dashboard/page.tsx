"use client";
import { useEffect, useState, useCallback } from "react";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { RefreshButton } from "@/components/refresh-button";
import { ErrorBoundary } from "@/components/error-boundary";
import { SkeletonTable } from "@/components/skeleton-table";
import { EmptyState } from "@/components/empty-state";
import { formatNumber, formatDateTime } from "@/lib/format";
import type { AdminStats, RequestItem, PaginatedResponse } from "@/lib/types";

export default function DashboardPage() {
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [requests, setRequests] = useState<RequestItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const [s, r] = await Promise.all([
        api<AdminStats>("/admin/stats"),
        api<PaginatedResponse<RequestItem>>("/admin/requests?per_page=10"),
      ]);
      setStats(s);
      setRequests(r.requests || []);
    } catch (e) {
      setError(e instanceof Error ? e.message : "تعذّر تحميل البيانات");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  if (error && !stats) {
    return (
      <div className="flex flex-col items-center justify-center rounded-xl border border-red-200 bg-red-50 px-6 py-10 text-center">
        <h2 className="text-lg font-bold text-red-900">تعذّر تحميل لوحة التحكم</h2>
        <p className="mt-1 max-w-md text-sm text-red-700">{error}</p>
        <Button onClick={load} size="sm" variant="outline" className="mt-4">
          إعادة المحاولة
        </Button>
      </div>
    );
  }

  const statCards = stats
    ? [
        { label: "إجمالي المستخدمين", value: stats.total_users, icon: "👥" },
        { label: "المشتركين", value: stats.active_subscribers, icon: "⭐" },
        { label: "طلبات اليوم", value: stats.requests_today, icon: "📋" },
        { label: "إجمالي الطلبات", value: stats.total_requests, icon: "📊" },
      ]
    : [];

  return (
    <ErrorBoundary>
      <div>
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-bold text-gray-900">الإحصائيات</h1>
          <RefreshButton onRefresh={load} />
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
          {loading && !stats
            ? Array.from({ length: 4 }).map((_, i) => (
                <Card key={i} className="p-6">
                  <div className="flex items-center justify-between">
                    <div className="flex-1">
                      <div className="h-3 w-24 rounded bg-gray-200 animate-pulse" />
                      <div className="mt-3 h-8 w-20 rounded bg-gray-200 animate-pulse" />
                    </div>
                    <div className="h-8 w-8 rounded-full bg-gray-100 animate-pulse" />
                  </div>
                </Card>
              ))
            : statCards.map((s, i) => (
                <Card key={i} className="p-6">
                  <div className="flex items-center justify-between">
                    <div>
                      <p className="text-sm text-gray-500">{s.label}</p>
                      <p className="text-3xl font-bold text-gray-900 mt-1" dir="ltr">
                        {formatNumber(s.value)}
                      </p>
                    </div>
                    <span className="text-3xl" aria-hidden="true">{s.icon}</span>
                  </div>
                </Card>
              ))}
        </div>

        <Card className="p-6">
          <h2 className="text-lg font-bold text-gray-900 mb-4">آخر الطلبات</h2>
          <div className="overflow-x-auto">
            {loading && requests.length === 0 ? (
              <SkeletonTable rows={5} cols={4} />
            ) : requests.length === 0 ? (
              <EmptyState
                title="لا توجد طلبات بعد"
                description="ستظهر آخر الطلبات هنا فور بدء المستخدمين باستعمال الخدمة."
              />
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-gray-500">
                    <th className="text-right pb-3">المستخدم</th>
                    <th className="text-right pb-3">الملف</th>
                    <th className="text-right pb-3">اللغة</th>
                    <th className="text-right pb-3">المدة</th>
                    <th className="text-right pb-3">الكلمات</th>
                    <th className="text-right pb-3">التاريخ</th>
                  </tr>
                </thead>
                <tbody>
                  {requests.map((r) => (
                    <tr key={r.id} className="border-b last:border-0">
                      <td className="py-3 font-medium">{r.full_name || r.email || "—"}</td>
                      <td className="py-3 text-gray-500 max-w-[150px] truncate">
                        {r.filename || "—"}
                      </td>
                      <td className="py-3">
                        <span
                          className="bg-blue-50 text-blue-600 px-2 py-0.5 rounded-full text-xs"
                          dir="ltr"
                        >
                          {r.language || "—"}
                        </span>
                      </td>
                      <td className="py-3">
                        <span dir="ltr">{r.duration_seconds.toFixed(1)}</span>ث
                      </td>
                      <td className="py-3" dir="ltr">
                        {formatNumber(r.word_count)}
                      </td>
                      <td className="py-3 text-gray-500 text-xs">
                        {formatDateTime(r.created_at)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </Card>
      </div>
    </ErrorBoundary>
  );
}
