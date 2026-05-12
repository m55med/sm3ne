"use client";
import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import { toast } from "@/components/toast";
import { PLAN_LABEL } from "@/lib/labels";
import type { Plan } from "@/lib/types";

export default function NewCouponPage() {
  const router = useRouter();
  const [plans, setPlans] = useState<Plan[]>([]);
  const [code, setCode] = useState("");
  // نبدأ بـ 0 ثم نُحدِّث لأول باقة غير مجانية بعد جلب القائمة
  const [planId, setPlanId] = useState(0);
  const [durationDays, setDurationDays] = useState(30);
  const [maxUses, setMaxUses] = useState(-1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    api<Plan[]>("/plans").then((data) => {
      setPlans(data);
      // اختيار أول باقة غير مجانية
      const firstPaid = data.find((p) => p.name !== "free");
      if (firstPaid) setPlanId(firstPaid.id);
    });
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");

    // التحقق من الحقول الرقمية قبل الإرسال
    if (!planId || !Number.isFinite(planId)) {
      setError("اختر باقة صحيحة");
      return;
    }
    if (!Number.isFinite(durationDays) || durationDays < 1) {
      setError("مدة الاشتراك يجب أن تكون رقماً صحيحاً ≥ 1");
      return;
    }
    if (!Number.isFinite(maxUses) || (maxUses !== -1 && maxUses < 1)) {
      setError("حد الاستخدام يجب أن يكون -1 أو رقماً ≥ 1");
      return;
    }

    setLoading(true);
    try {
      await api("/admin/coupons", {
        method: "POST",
        body: JSON.stringify({ code, plan_id: planId, duration_days: durationDays, max_uses: maxUses }),
      });
      toast.success("تم إنشاء الكوبون");
      router.push("/coupons");
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "فشل إنشاء الكوبون");
    } finally {
      setLoading(false);
    }
  }

  return (
    <div>
      <h1 className="text-2xl font-bold text-gray-900 mb-6">إنشاء كوبون جديد</h1>
      <Card className="p-6 max-w-lg">
        <form onSubmit={handleSubmit} className="space-y-4">
          <div>
            <Label htmlFor="coupon-code">رمز الكوبون</Label>
            <Input
              id="coupon-code"
              name="code"
              value={code}
              onChange={(e) => setCode(e.target.value.toUpperCase())}
              placeholder="HEARING2026"
              required
              className="font-mono"
            />
          </div>
          <div>
            <Label htmlFor="coupon-plan">الباقة</Label>
            <select
              id="coupon-plan"
              name="plan_id"
              value={planId}
              onChange={(e) => setPlanId(Number(e.target.value))}
              className="w-full border rounded-lg px-3 py-2 text-sm"
            >
              {plans.filter(p => p.name !== "free").map((p) => (
                <option key={p.id} value={p.id}>
                  {PLAN_LABEL[p.name] || p.name} — {p.price}
                </option>
              ))}
            </select>
          </div>
          <div>
            <Label htmlFor="coupon-duration">مدة الاشتراك (أيام)</Label>
            <Input
              id="coupon-duration"
              name="duration_days"
              type="number"
              value={durationDays}
              onChange={(e) => {
                const v = e.target.value === "" ? NaN : Number(e.target.value);
                setDurationDays(v);
              }}
              min={1}
            />
          </div>
          <div>
            <Label htmlFor="coupon-max-uses">حد الاستخدام (-1 = بلا حد)</Label>
            <Input
              id="coupon-max-uses"
              name="max_uses"
              type="number"
              value={maxUses}
              onChange={(e) => {
                const v = e.target.value === "" ? NaN : Number(e.target.value);
                setMaxUses(v);
              }}
              min={-1}
            />
          </div>
          {error && <p className="text-red-500 text-sm">{error}</p>}
          <div className="flex gap-3">
            <Button type="submit" disabled={loading}>{loading ? "جاري الإنشاء..." : "إنشاء الكوبون"}</Button>
            <Button type="button" variant="outline" onClick={() => router.back()}>إلغاء</Button>
          </div>
        </form>
      </Card>
    </div>
  );
}
