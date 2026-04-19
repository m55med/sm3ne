"use client";
import { useEffect, useState, useCallback } from "react";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { RefreshButton } from "@/components/refresh-button";
import type { AdminStats, RequestItem, PaginatedResponse } from "@/lib/types";

export default function DashboardPage() {
  const [stats, setStats] = useState<AdminStats | null>(null);
  const [requests, setRequests] = useState<RequestItem[]>([]);

  const load = useCallback(async () => {
    const [s, r] = await Promise.all([
      api<AdminStats>("/admin/stats"),
      api<PaginatedResponse<RequestItem>>("/admin/requests?per_page=10"),
    ]);
    setStats(s);
    setRequests(r.requests || []);
  }, []);

  useEffect(() => { load(); }, [load]);

  if (!stats) {
    return <div className="flex items-center justify-center h-64"><div className="animate-spin w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full" /></div>;
  }

  const statCards = [
    { label: "إجمالي المستخدمين", value: stats.total_users, icon: "👥" },
    { label: "المشتركين", value: stats.active_subscribers, icon: "⭐" },
    { label: "طلبات اليوم", value: stats.requests_today, icon: "📋" },
    { label: "إجمالي الطلبات", value: stats.total_requests, icon: "📊" },
  ];

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">الإحصائيات</h1>
        <RefreshButton onRefresh={load} />
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4 mb-8">
        {statCards.map((s, i) => (
          <Card key={i} className="p-6">
            <div className="flex items-center justify-between">
              <div>
                <p className="text-sm text-gray-500">{s.label}</p>
                <p className="text-3xl font-bold text-gray-900 mt-1">{s.value}</p>
              </div>
              <span className="text-3xl">{s.icon}</span>
            </div>
          </Card>
        ))}
      </div>

      <Card className="p-6">
        <h2 className="text-lg font-bold text-gray-900 mb-4">آخر الطلبات</h2>
        <div className="overflow-x-auto">
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
                  <td className="py-3 font-medium">{r.username}</td>
                  <td className="py-3 text-gray-500 max-w-[150px] truncate">{r.filename || "-"}</td>
                  <td className="py-3"><span className="bg-blue-50 text-blue-600 px-2 py-0.5 rounded-full text-xs">{r.language || "-"}</span></td>
                  <td className="py-3">{r.duration_seconds.toFixed(1)}ث</td>
                  <td className="py-3">{r.word_count}</td>
                  <td className="py-3 text-gray-500 text-xs">{new Date(r.created_at).toLocaleDateString("ar")}</td>
                </tr>
              ))}
              {requests.length === 0 && (
                <tr><td colSpan={6} className="py-8 text-center text-gray-400">لا توجد طلبات بعد</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
