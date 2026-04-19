"use client";
import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { RefreshButton } from "@/components/refresh-button";
import type { Coupon } from "@/lib/types";

export default function CouponsPage() {
  const [coupons, setCoupons] = useState<Coupon[]>([]);

  const load = useCallback(async () => {
    const data = await api<Coupon[]>("/admin/coupons");
    setCoupons(data);
  }, []);

  useEffect(() => { load(); }, [load]);

  async function toggleCoupon(id: number, isActive: boolean) {
    await api(`/admin/coupons/${id}`, { method: "PUT", body: JSON.stringify({ is_active: !isActive }) });
    setCoupons(coupons.map((c) => c.id === id ? { ...c, is_active: !isActive } : c));
  }

  async function deleteCoupon(id: number) {
    if (!confirm("هل أنت متأكد من حذف هذا الكوبون؟")) return;
    await api(`/admin/coupons/${id}`, { method: "DELETE" });
    setCoupons(coupons.map((c) => c.id === id ? { ...c, is_active: false } : c));
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">الكوبونات</h1>
        <div className="flex gap-2">
          <RefreshButton onRefresh={load} />
          <Link href="/coupons/new"><Button>إنشاء كوبون جديد</Button></Link>
        </div>
      </div>
      <Card className="p-6">
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-gray-500">
                <th className="text-right pb-3">الكود</th>
                <th className="text-right pb-3">الباقة</th>
                <th className="text-right pb-3">المدة (يوم)</th>
                <th className="text-right pb-3">الاستخدام</th>
                <th className="text-right pb-3">الحالة</th>
                <th className="text-right pb-3">تاريخ الإنشاء</th>
                <th className="text-right pb-3">ينتهي في</th>
                <th className="text-right pb-3">إجراءات</th>
              </tr>
            </thead>
            <tbody>
              {coupons.map((c) => (
                <tr key={c.id} className="border-b last:border-0">
                  <td className="py-3 font-mono font-bold">{c.code}</td>
                  <td className="py-3"><Badge variant="secondary">Plan #{c.plan_id}</Badge></td>
                  <td className="py-3">{c.duration_days}</td>
                  <td className="py-3">{c.times_used}/{c.max_uses === -1 ? "∞" : c.max_uses}</td>
                  <td className="py-3"><Badge variant={c.is_active ? "default" : "destructive"}>{c.is_active ? "نشط" : "معطل"}</Badge></td>
                  <td className="py-3 text-gray-500 text-xs">{new Date(c.created_at).toLocaleDateString("ar")}</td>
                  <td className="py-3 text-gray-500 text-xs">{c.expires_at ? new Date(c.expires_at).toLocaleDateString("ar") : "—"}</td>
                  <td className="py-3 flex gap-2">
                    <Button variant="outline" size="sm" onClick={() => toggleCoupon(c.id, c.is_active)}>
                      {c.is_active ? "تعطيل" : "تفعيل"}
                    </Button>
                    <Button variant="destructive" size="sm" onClick={() => deleteCoupon(c.id)}>حذف</Button>
                  </td>
                </tr>
              ))}
              {coupons.length === 0 && (
                <tr><td colSpan={8} className="py-8 text-center text-gray-400">لا توجد كوبونات</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </Card>
    </div>
  );
}
