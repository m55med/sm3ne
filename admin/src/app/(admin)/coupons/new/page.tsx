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

// Coupons exist for ONE purpose: giving deaf users free access to the paid
// plans. "Permanent" coupons (duration_days = -1) grant a subscription that
// never expires — the intended default for that audience.
function randomCode(prefix = "HEARING"): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no ambiguous 0/O/1/I
  let s = "";
  for (let i = 0; i < 5; i++) s += chars[Math.floor(Math.random() * chars.length)];
  return `${prefix}-${s}`;
}

type DurationMode = "permanent" | "fixed";

export default function NewCouponPage() {
  const router = useRouter();
  const [plans, setPlans] = useState<Plan[]>([]);
  const [code, setCode] = useState("");
  const [planId, setPlanId] = useState(0);
  const [durationMode, setDurationMode] = useState<DurationMode>("permanent");
  const [durationDays, setDurationDays] = useState(365);
  const [maxUses, setMaxUses] = useState(1);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    api<Plan[]>("/plans").then((data) => {
      setPlans(data);
      const firstPaid = data.find((p) => p.name !== "free");
      if (firstPaid) setPlanId(firstPaid.id);
    });
  }, []);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError("");

    if (!code.trim() || code.trim().length < 4) {
      setError("رمز الكوبون يجب أن يكون 4 أحرف على الأقل");
      return;
    }
    if (!planId || !Number.isFinite(planId)) {
      setError("اختر باقة صحيحة");
      return;
    }
    const resolvedDuration =
      durationMode === "permanent" ? -1 : Math.trunc(durationDays);
    if (durationMode === "fixed" && (!Number.isFinite(durationDays) || durationDays < 1)) {
      setError("مدة الاشتراك يجب أن تكون رقماً صحيحاً ≥ 1");
      return;
    }
    if (!Number.isFinite(maxUses) || (maxUses !== -1 && maxUses < 1)) {
      setError("حد الاستخدام يجب أن يكون -1 (بلا حد) أو رقماً ≥ 1");
      return;
    }

    setLoading(true);
    try {
      await api("/admin/coupons", {
        method: "POST",
        body: JSON.stringify({
          code: code.trim(),
          plan_id: planId,
          duration_days: resolvedDuration,
          max_uses: maxUses,
        }),
      });
      toast.success("تم إنشاء الكوبون");
      router.push("/coupons");
    } catch (err: unknown) {
      setError(err instanceof Error ? err.message : "فشل إنشاء الكوبون");
    } finally {
      setLoading(false);
    }
  }

  const selectedPlan = plans.find((p) => p.id === planId);

  return (
    <div className="max-w-2xl">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">إنشاء كوبون جديد</h1>
        <p className="text-sm text-gray-500 mt-1">
          الكوبونات تُمنح لذوي الإعاقة السمعية لتفعيل الباقات المدفوعة مجاناً.
        </p>
      </div>

      <Card className="p-6">
        <form onSubmit={handleSubmit} className="space-y-6">
          {/* رمز الكوبون */}
          <div>
            <Label htmlFor="coupon-code">رمز الكوبون</Label>
            <div className="flex gap-2 mt-1">
              <Input
                id="coupon-code"
                name="code"
                value={code}
                onChange={(e) =>
                  setCode(e.target.value.toUpperCase().replace(/[^A-Z0-9_-]/g, ""))
                }
                placeholder="HEARING-AB3K9"
                required
                className="font-mono"
                dir="ltr"
              />
              <Button
                type="button"
                variant="outline"
                onClick={() => setCode(randomCode())}
              >
                توليد
              </Button>
            </div>
            <p className="text-xs text-gray-400 mt-1">
              أحرف إنجليزية كبيرة وأرقام و <span dir="ltr">- _</span> فقط، 4 أحرف على الأقل.
            </p>
          </div>

          {/* الباقة */}
          <div>
            <Label htmlFor="coupon-plan">الباقة</Label>
            <select
              id="coupon-plan"
              name="plan_id"
              value={planId}
              onChange={(e) => setPlanId(Number(e.target.value))}
              className="mt-1 w-full border rounded-lg px-3 py-2 text-sm bg-transparent"
            >
              {plans
                .filter((p) => p.name !== "free")
                .map((p) => (
                  <option key={p.id} value={p.id}>
                    {PLAN_LABEL[p.name] || p.name}
                  </option>
                ))}
            </select>
            <p className="text-xs text-gray-400 mt-1">
              المزايا التي سيحصل عليها المستخدم عند تفعيل الكوبون.
            </p>
          </div>

          {/* نوع الاشتراك */}
          <div>
            <Label>نوع الاشتراك</Label>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-1">
              <button
                type="button"
                onClick={() => setDurationMode("permanent")}
                className={`text-right rounded-xl border-2 p-3 transition ${
                  durationMode === "permanent"
                    ? "border-blue-600 bg-blue-50"
                    : "border-gray-200 hover:border-blue-300"
                }`}
              >
                <div className="font-bold text-gray-900 text-sm">دائم — لا ينتهي ♾️</div>
                <div className="text-xs text-gray-500 mt-1">
                  الباقة تفضل مفعّلة للأبد. الخيار المناسب لذوي الإعاقة السمعية.
                </div>
              </button>
              <button
                type="button"
                onClick={() => setDurationMode("fixed")}
                className={`text-right rounded-xl border-2 p-3 transition ${
                  durationMode === "fixed"
                    ? "border-blue-600 bg-blue-50"
                    : "border-gray-200 hover:border-blue-300"
                }`}
              >
                <div className="font-bold text-gray-900 text-sm">مدة محددة 📅</div>
                <div className="text-xs text-gray-500 mt-1">
                  الباقة تفضل مفعّلة لعدد أيام محدد ثم تنتهي.
                </div>
              </button>
            </div>
          </div>

          {/* مدة الاشتراك — تظهر فقط للمدة المحددة */}
          {durationMode === "fixed" && (
            <div>
              <Label htmlFor="coupon-duration">مدة الاشتراك (أيام)</Label>
              <Input
                id="coupon-duration"
                name="duration_days"
                type="number"
                value={Number.isFinite(durationDays) ? durationDays : ""}
                onChange={(e) =>
                  setDurationDays(e.target.value === "" ? NaN : Number(e.target.value))
                }
                min={1}
                className="mt-1"
              />
              <p className="text-xs text-gray-400 mt-1">
                عدد الأيام التي تظل فيها الباقة مفعّلة بعد التفعيل.
              </p>
            </div>
          )}

          {/* حد الاستخدام */}
          <div>
            <Label htmlFor="coupon-max-uses">حد الاستخدام</Label>
            <Input
              id="coupon-max-uses"
              name="max_uses"
              type="number"
              value={Number.isFinite(maxUses) ? maxUses : ""}
              onChange={(e) =>
                setMaxUses(e.target.value === "" ? NaN : Number(e.target.value))
              }
              min={-1}
              className="mt-1"
            />
            <p className="text-xs text-gray-400 mt-1">
              كم شخص يقدر يستخدم الكوبون. <span dir="ltr">1</span> = شخص واحد فقط،
              <span dir="ltr"> -1</span> = بلا حد.
            </p>
          </div>

          {/* ملخّص */}
          <div className="rounded-lg bg-gray-50 border border-gray-200 px-4 py-3 text-sm text-gray-600">
            <span className="font-semibold text-gray-800">ملخّص: </span>
            الكوبون{" "}
            <span className="font-mono font-bold" dir="ltr">
              {code || "—"}
            </span>{" "}
            يفعّل باقة{" "}
            <b>{selectedPlan ? PLAN_LABEL[selectedPlan.name] || selectedPlan.name : "—"}</b>{" "}
            {durationMode === "permanent" ? (
              <b className="text-blue-700">بشكل دائم</b>
            ) : (
              <>لمدة <b>{Number.isFinite(durationDays) ? durationDays : "—"} يوم</b></>
            )}
            ، ويُستخدَم{" "}
            <b>{maxUses === -1 ? "بلا حد" : `${maxUses} مرة`}</b>.
          </div>

          {error && <p className="text-red-500 text-sm">{error}</p>}

          <div className="flex gap-3">
            <Button type="submit" disabled={loading}>
              {loading ? "جاري الإنشاء..." : "إنشاء الكوبون"}
            </Button>
            <Button type="button" variant="outline" onClick={() => router.back()}>
              إلغاء
            </Button>
          </div>
        </form>
      </Card>
    </div>
  );
}
