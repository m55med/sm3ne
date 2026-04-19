"use client";
import { useState, useEffect } from "react";
import { useRouter } from "next/navigation";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Label } from "@/components/ui/label";
import type { Plan } from "@/lib/types";

export default function NewCouponPage() {
  const router = useRouter();
  const [plans, setPlans] = useState<Plan[]>([]);
  const [code, setCode] = useState("");
  const [planId, setPlanId] = useState(2);
  const [durationDays, setDurationDays] = useState(30);
  const [maxUses, setMaxUses] = useState(-1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    api<Plan[]>("/plans").then(setPlans);
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setLoading(true);
    setError("");
    try {
      await api("/admin/coupons", {
        method: "POST",
        body: JSON.stringify({ code, plan_id: planId, duration_days: durationDays, max_uses: maxUses }),
      });
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
            <Label>رمز الكوبون</Label>
            <Input value={code} onChange={(e) => setCode(e.target.value.toUpperCase())} placeholder="HEARING2026" required className="font-mono" />
          </div>
          <div>
            <Label>الباقة</Label>
            <select value={planId} onChange={(e) => setPlanId(Number(e.target.value))} className="w-full border rounded-lg px-3 py-2 text-sm">
              {plans.filter(p => p.name !== "free").map((p) => (
                <option key={p.id} value={p.id}>{p.name} — {p.price}</option>
              ))}
            </select>
          </div>
          <div>
            <Label>مدة الاشتراك (أيام)</Label>
            <Input type="number" value={durationDays} onChange={(e) => setDurationDays(Number(e.target.value))} min={1} />
          </div>
          <div>
            <Label>حد الاستخدام (-1 = بلا حد)</Label>
            <Input type="number" value={maxUses} onChange={(e) => setMaxUses(Number(e.target.value))} min={-1} />
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
