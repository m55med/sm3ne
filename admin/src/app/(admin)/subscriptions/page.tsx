"use client";
import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { RefreshButton } from "@/components/refresh-button";
import { ErrorBoundary } from "@/components/error-boundary";
import { SkeletonTable } from "@/components/skeleton-table";
import { EmptyState } from "@/components/empty-state";
import { formatNumber, formatDateTime } from "@/lib/format";
import type {
  SubscriptionLogItem,
  SubscriptionLogResponse,
} from "@/lib/types";

const PER_PAGE = 20;

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
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      const params = new URLSearchParams({
        page: String(page),
        per_page: String(PER_PAGE),
        include_inactive: String(includeInactive),
      });
      const r = await api<SubscriptionLogResponse>(
        `/admin/subscriptions?${params}`
      );
      setItems(r.subscriptions);
      setTotal(r.total);
    } catch (e) {
      setError(e instanceof Error ? e.message : "تعذّر تحميل الاشتراكات");
    } finally {
      setLoading(false);
    }
  }, [page, includeInactive]);

  useEffect(() => {
    load();
  }, [load]);

  const totalPages = Math.max(1, Math.ceil(total / PER_PAGE));
  const showPagination = totalPages > 1;

  return (
    <ErrorBoundary>
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
                onChange={(e) => {
                  setIncludeInactive(e.target.checked);
                  setPage(1);
                }}
              />
              يتضمن الاشتراكات المنتهية/الملغاة
            </label>
            <span className="text-sm text-gray-500 ms-auto">
              <span dir="ltr">{formatNumber(total)}</span> اشتراك
            </span>
          </div>

          {error && (
            <div className="mb-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              {error}
            </div>
          )}

          <div className="overflow-x-auto">
            {loading && items.length === 0 ? (
              <SkeletonTable rows={8} cols={6} />
            ) : items.length === 0 ? (
              <EmptyState
                title="لا توجد اشتراكات"
                description="ستظهر هنا جميع الاشتراكات الحالية والسابقة."
              />
            ) : (
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
                      <td className="py-3 text-gray-400" dir="ltr">
                        {s.id}
                      </td>
                      <td className="py-3 font-medium">
                        <Link
                          href={`/users/${s.user_public_id || s.user_id}`}
                          className="hover:underline text-blue-700"
                        >
                          {s.username}
                        </Link>
                      </td>
                      <td className="py-3">
                        <Badge
                          variant={s.plan_name === "free" ? "secondary" : "default"}
                        >
                          {PLAN_LABEL[s.plan_name] || s.plan_name}
                        </Badge>
                      </td>
                      <td className="py-3">
                        <Badge variant="outline">
                          {SOURCE_LABEL[s.plan_source]}
                        </Badge>
                      </td>
                      <td className="py-3 font-mono text-xs" dir="ltr">
                        {s.coupon_code || "—"}
                      </td>
                      <td className="py-3 text-gray-600 text-xs">
                        {s.starts_at ? formatDateTime(s.starts_at) : "—"}
                      </td>
                      <td className="py-3 text-gray-600 text-xs">
                        {s.expires_at ? formatDateTime(s.expires_at) : "—"}
                      </td>
                      <td className="py-3">
                        <Badge variant={s.is_active ? "default" : "secondary"}>
                          {s.is_active ? "نشط" : "منتهي"}
                        </Badge>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>

          {showPagination && (
            <div className="flex items-center justify-between mt-4">
              <Button
                variant="outline"
                size="sm"
                disabled={page === 1}
                onClick={() => setPage(page - 1)}
              >
                السابق
              </Button>
              <span className="text-sm text-gray-500">
                صفحة <span dir="ltr">{page}</span> من{" "}
                <span dir="ltr">{totalPages}</span>
              </span>
              <Button
                variant="outline"
                size="sm"
                disabled={page * PER_PAGE >= total}
                onClick={() => setPage(page + 1)}
              >
                التالي
              </Button>
            </div>
          )}
        </Card>
      </div>
    </ErrorBoundary>
  );
}
