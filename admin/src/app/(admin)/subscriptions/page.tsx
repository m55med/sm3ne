"use client";
import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { RefreshButton } from "@/components/refresh-button";
import type { SubscriptionLogItem, SubscriptionLogResponse } from "@/lib/types";

const PLAN_LABEL: Record<string, string> = {
  free: "مجاني",
  monthly: "شهري",
  annual: "سنوي",
};

const SOURCE_LABEL: Record<SubscriptionLogItem["plan_source"], string> = {
  free: "مجاني",
  coupon: "كوبون",
  purchase: "مدفوع",
};

export default function SubscriptionsPage() {
  const [items, setItems] = useState<SubscriptionLogItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [includeInactive, setIncludeInactive] = useState(true);

  const load = useCallback(async () => {
    const params = new URLSearchParams({
      page: String(page),
      per_page: "20",
      include_inactive: String(includeInactive),
    });
    const r = await api<SubscriptionLogResponse>(`/admin/subscriptions?${params}`);
    setItems(r.subscriptions);
    setTotal(r.total);
  }, [page, includeInactive]);

  useEffect(() => { load(); }, [load]);

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">سجل الاشتراكات</h1>
        <RefreshButton onRefresh={load} />
      </div>
      <Card className="p-6">
        <div className="flex items-center gap-4 mb-6">
          <label className="flex items-center gap-2 text-sm">
            <input
              type="checkbox"
              checked={includeInactive}
              onChange={(e) => { setIncludeInactive(e.target.checked); setPage(1); }}
            />
            يتضمن الاشتراكات المنتهية/الملغاة
          </label>
          <span className="text-sm text-gray-500 mr-auto">{total} اشتراك</span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-gray-500">
                <th className="text-right pb-3">#</th>
                <th className="text-right pb-3">المستخدم</th>
                <th className="text-right pb-3">الباقة</th>
                <th className="text-right pb-3">المصدر</th>
                <th className="text-right pb-3">الكوبون</th>
                <th className="text-right pb-3">البداية</th>
                <th className="text-right pb-3">النهاية</th>
                <th className="text-right pb-3">الحالة</th>
              </tr>
            </thead>
            <tbody>
              {items.map((s) => (
                <tr key={s.id} className="border-b last:border-0">
                  <td className="py-3 text-gray-400">{s.id}</td>
                  <td className="py-3 font-medium">
                    <Link href={`/users/${s.user_public_id || s.user_id}`} className="hover:underline text-blue-700">
                      {s.username}
                    </Link>
                  </td>
                  <td className="py-3">
                    <Badge variant={s.plan_name === "free" ? "secondary" : "default"}>
                      {PLAN_LABEL[s.plan_name] || s.plan_name}
                    </Badge>
                  </td>
                  <td className="py-3">
                    <Badge variant="outline">{SOURCE_LABEL[s.plan_source]}</Badge>
                  </td>
                  <td className="py-3 font-mono text-xs">{s.coupon_code || "—"}</td>
                  <td className="py-3 text-gray-600 text-xs">{s.starts_at ? new Date(s.starts_at).toLocaleString("ar") : "—"}</td>
                  <td className="py-3 text-gray-600 text-xs">{s.expires_at ? new Date(s.expires_at).toLocaleString("ar") : "—"}</td>
                  <td className="py-3">
                    <Badge variant={s.is_active ? "default" : "secondary"}>{s.is_active ? "نشط" : "منتهي"}</Badge>
                  </td>
                </tr>
              ))}
              {items.length === 0 && (
                <tr><td colSpan={8} className="py-8 text-center text-gray-400">لا توجد اشتراكات</td></tr>
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
