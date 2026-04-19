"use client";
import { useEffect, useState, useCallback } from "react";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { RefreshButton } from "@/components/refresh-button";
import Link from "next/link";
import type { PlanAdminItem, PlanCreateBody, PlanUpdateBody, PlanSubscriberItem } from "@/lib/types";

const PLAN_LABEL: Record<string, string> = {
  free: "مجانية",
  monthly: "شهرية",
  annual: "سنوية",
};

type FormState = {
  name: string;
  price: string;
  original_price: string;
  max_audio_seconds: string;
  daily_request_limit: string;
  monthly_request_limit: string;
  api_daily_request_limit: string;
  rpm_default: string;
  api_keys_allowed: string;
  description: string;
  is_active: boolean;
};

const EMPTY_FORM: FormState = {
  name: "",
  price: "0",
  original_price: "0",
  max_audio_seconds: "30",
  daily_request_limit: "100",
  monthly_request_limit: "",
  api_daily_request_limit: "-1",
  rpm_default: "10",
  api_keys_allowed: "1",
  description: "",
  is_active: true,
};

function fmtLimit(n: number, unlimitedValue = -1) {
  if (n === unlimitedValue) return "∞";
  return String(n);
}

function fmtMonthly(n: number | null) {
  if (n === null) return "—";
  if (n === -1) return "∞";
  return String(n);
}

function fmtApi(n: number) {
  if (n === -1) return "مثل اليومي";
  if (n === 0) return "معطّل";
  return String(n);
}

export default function PlansPage() {
  const [plans, setPlans] = useState<PlanAdminItem[]>([]);
  const [loading, setLoading] = useState(true);
  const [dialogOpen, setDialogOpen] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [form, setForm] = useState<FormState>(EMPTY_FORM);
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const [subsOpen, setSubsOpen] = useState(false);
  const [subsPlan, setSubsPlan] = useState<PlanAdminItem | null>(null);
  const [subs, setSubs] = useState<PlanSubscriberItem[]>([]);
  const [subsLoading, setSubsLoading] = useState(false);

  const load = useCallback(async () => {
    try {
      const data = await api<PlanAdminItem[]>("/admin/plans");
      setPlans(data);
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  function openCreate() {
    setEditingId(null);
    setForm(EMPTY_FORM);
    setError(null);
    setDialogOpen(true);
  }

  function openEdit(p: PlanAdminItem) {
    setEditingId(p.id);
    setForm({
      name: p.name,
      price: String(p.price),
      original_price: String(p.original_price),
      max_audio_seconds: String(p.max_audio_seconds),
      daily_request_limit: String(p.daily_request_limit),
      monthly_request_limit: p.monthly_request_limit === null ? "" : String(p.monthly_request_limit),
      api_daily_request_limit: String(p.api_daily_request_limit),
      rpm_default: String(p.rpm_default),
      api_keys_allowed: String(p.api_keys_allowed),
      description: p.description || "",
      is_active: p.is_active,
    });
    setError(null);
    setDialogOpen(true);
  }

  function buildPayload(): PlanCreateBody | PlanUpdateBody {
    const base = {
      price: Number(form.price),
      original_price: Number(form.original_price),
      max_audio_seconds: Math.trunc(Number(form.max_audio_seconds)),
      daily_request_limit: Math.trunc(Number(form.daily_request_limit)),
      monthly_request_limit: form.monthly_request_limit.trim() === "" ? null : Math.trunc(Number(form.monthly_request_limit)),
      api_daily_request_limit: Math.trunc(Number(form.api_daily_request_limit)),
      rpm_default: Math.trunc(Number(form.rpm_default)),
      api_keys_allowed: Math.trunc(Number(form.api_keys_allowed)),
      description: form.description.trim() || null,
      is_active: form.is_active,
    };
    if (editingId === null) {
      return { ...base, name: form.name.trim() } as PlanCreateBody;
    }
    return base as PlanUpdateBody;
  }

  async function submit() {
    setSaving(true);
    setError(null);
    try {
      if (editingId === null) {
        if (!form.name.trim()) {
          setError("الاسم مطلوب");
          setSaving(false);
          return;
        }
        await api("/admin/plans", { method: "POST", body: JSON.stringify(buildPayload()) });
      } else {
        await api(`/admin/plans/${editingId}`, { method: "PUT", body: JSON.stringify(buildPayload()) });
      }
      setDialogOpen(false);
      await load();
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : "حدث خطأ");
    } finally {
      setSaving(false);
    }
  }

  async function openSubscribers(p: PlanAdminItem) {
    setSubsPlan(p);
    setSubsOpen(true);
    setSubsLoading(true);
    try {
      const list = await api<PlanSubscriberItem[]>(`/admin/plans/${p.id}/subscribers`);
      setSubs(list);
    } finally {
      setSubsLoading(false);
    }
  }

  async function confirmDelete(p: PlanAdminItem) {
    if (p.name === "free") return;
    const ok = window.confirm(`تعطيل الباقة "${p.name}"؟ المشتركون الحاليون (${p.subscriber_count}) سيظلون عليها حتى انتهاء المدة.`);
    if (!ok) return;
    await api(`/admin/plans/${p.id}`, { method: "DELETE" });
    await load();
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">الباقات</h1>
        <div className="flex gap-2">
          <RefreshButton onRefresh={load} />
          <Button onClick={openCreate}>+ باقة جديدة</Button>
        </div>
      </div>

      {loading ? (
        <div className="text-gray-400 text-center py-8">جاري التحميل...</div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {plans.map((plan) => (
            <Card key={plan.id} className={`p-6 ${plan.is_active ? "" : "opacity-60"}`}>
              <div className="flex items-center justify-between mb-4">
                <h2 className="text-xl font-bold">{PLAN_LABEL[plan.name] || plan.name}</h2>
                <div className="flex gap-1">
                  <Badge>{plan.name}</Badge>
                  {!plan.is_active && <Badge variant="destructive">معطّلة</Badge>}
                </div>
              </div>

              <div className="space-y-2 text-sm mb-4">
                <Row label="السعر" value={plan.price === 0 ? "مجاني" : `${plan.price}`} strong />
                {plan.original_price > plan.price && (
                  <Row label="السعر الأصلي" value={<span className="line-through text-gray-400">{plan.original_price}</span>} />
                )}
                <Row label="مشتركين" value={
                  plan.subscriber_count > 0 ? (
                    <button onClick={() => openSubscribers(plan)} className="hover:underline">
                      <Badge variant="secondary" className="cursor-pointer">{plan.subscriber_count}</Badge>
                    </button>
                  ) : (
                    <Badge variant="secondary">0</Badge>
                  )
                } />
                <Row label="الوصف" value={plan.description || "—"} />
                <hr className="my-2" />
                <Row label="حد الصوت الواحد" value={plan.max_audio_seconds === -1 ? "بلا حدود" : `${plan.max_audio_seconds} ث`} />
                <Row label="الحد اليومي" value={fmtLimit(plan.daily_request_limit)} />
                <Row label="الحد الشهري" value={fmtMonthly(plan.monthly_request_limit)} />
                <Row label="طلبات/دقيقة" value={fmtLimit(plan.rpm_default)} />
                <hr className="my-2" />
                <Row label="API — طلبات يومية" value={fmtApi(plan.api_daily_request_limit)} />
                <Row label="API — مفاتيح مسموحة" value={fmtLimit(plan.api_keys_allowed)} />
              </div>

              <div className="flex gap-2">
                <Button variant="outline" size="sm" className="flex-1" onClick={() => openEdit(plan)}>تعديل</Button>
                {plan.name !== "free" && (
                  <Button variant="outline" size="sm" className="text-red-600 hover:bg-red-50" onClick={() => confirmDelete(plan)}>حذف</Button>
                )}
              </div>
            </Card>
          ))}
        </div>
      )}

      <Dialog open={subsOpen} onOpenChange={setSubsOpen}>
        <DialogContent className="sm:max-w-2xl max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>
              مشتركو باقة {subsPlan ? (PLAN_LABEL[subsPlan.name] || subsPlan.name) : ""}
              {subs.length > 0 && <span className="text-sm text-gray-500 mr-2">({subs.length})</span>}
            </DialogTitle>
          </DialogHeader>
          {subsLoading ? (
            <div className="text-center py-8 text-gray-400">جاري التحميل...</div>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-gray-500">
                    <th className="text-right pb-2">المستخدم</th>
                    <th className="text-right pb-2">المصدر</th>
                    <th className="text-right pb-2">الكوبون</th>
                    <th className="text-right pb-2">البداية</th>
                    <th className="text-right pb-2">المتبقي</th>
                  </tr>
                </thead>
                <tbody>
                  {subs.map((s) => (
                    <tr key={s.user_id} className="border-b last:border-0">
                      <td className="py-2">
                        <Link href={`/users/${s.user_public_id || s.user_id}`} className="hover:underline text-blue-700">
                          {s.full_name || s.username}
                        </Link>
                        {s.email && <div className="text-xs text-gray-400">{s.email}</div>}
                      </td>
                      <td className="py-2"><Badge variant="outline">{s.plan_source === "coupon" ? "كوبون" : s.plan_source === "purchase" ? "مدفوع" : "مجاني"}</Badge></td>
                      <td className="py-2 font-mono text-xs">{s.coupon_code || "—"}</td>
                      <td className="py-2 text-xs text-gray-600">{s.starts_at ? new Date(s.starts_at).toLocaleDateString("ar") : "—"}</td>
                      <td className="py-2">
                        {s.days_remaining === null ? <span className="text-gray-400">—</span> : (
                          <Badge variant={s.days_remaining <= 3 ? "destructive" : s.days_remaining <= 7 ? "secondary" : "default"}>
                            {s.days_remaining} يوم
                          </Badge>
                        )}
                      </td>
                    </tr>
                  ))}
                  {subs.length === 0 && (
                    <tr><td colSpan={5} className="py-8 text-center text-gray-400">لا يوجد مشتركون</td></tr>
                  )}
                </tbody>
              </table>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="sm:max-w-lg max-h-[90vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{editingId === null ? "باقة جديدة" : "تعديل الباقة"}</DialogTitle>
            <DialogDescription>
              -1 = بلا حدود. 0 في حقل API = تعطيل الـ API على الباقة.
            </DialogDescription>
          </DialogHeader>

          <div className="grid gap-4 py-2">
            {editingId === null && (
              <Field label="الاسم (معرّف فريد)" value={form.name} onChange={(v) => setForm({ ...form, name: v })} placeholder="مثال: pro" />
            )}
            <div className="grid grid-cols-2 gap-3">
              <Field label="السعر" value={form.price} onChange={(v) => setForm({ ...form, price: v })} type="number" />
              <Field label="السعر الأصلي" value={form.original_price} onChange={(v) => setForm({ ...form, original_price: v })} type="number" />
            </div>
            <Field label="حد الصوت الواحد (ثانية، -1 = بلا حدود)" value={form.max_audio_seconds} onChange={(v) => setForm({ ...form, max_audio_seconds: v })} type="number" />
            <div className="grid grid-cols-2 gap-3">
              <Field label="الحد اليومي" value={form.daily_request_limit} onChange={(v) => setForm({ ...form, daily_request_limit: v })} type="number" />
              <Field label="الحد الشهري (فارغ = بدون)" value={form.monthly_request_limit} onChange={(v) => setForm({ ...form, monthly_request_limit: v })} type="number" placeholder="اختياري" />
            </div>
            <Field label="طلبات في الدقيقة (RPM)" value={form.rpm_default} onChange={(v) => setForm({ ...form, rpm_default: v })} type="number" />
            <div className="grid grid-cols-2 gap-3">
              <Field label="API — حد يومي" value={form.api_daily_request_limit} onChange={(v) => setForm({ ...form, api_daily_request_limit: v })} type="number" />
              <Field label="API — مفاتيح مسموحة" value={form.api_keys_allowed} onChange={(v) => setForm({ ...form, api_keys_allowed: v })} type="number" />
            </div>
            <div>
              <Label className="text-xs">الوصف</Label>
              <Textarea value={form.description} onChange={(e) => setForm({ ...form, description: e.target.value })} rows={2} className="mt-1" />
            </div>
            <label className="flex items-center gap-2 text-sm">
              <input type="checkbox" checked={form.is_active} onChange={(e) => setForm({ ...form, is_active: e.target.checked })} />
              نشطة
            </label>
            {error && <div className="text-red-600 text-sm">{error}</div>}
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setDialogOpen(false)} disabled={saving}>إلغاء</Button>
            <Button onClick={submit} disabled={saving}>{saving ? "جاري الحفظ..." : "حفظ"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function Row({ label, value, strong }: { label: string; value: React.ReactNode; strong?: boolean }) {
  return (
    <div className="flex justify-between items-center">
      <span className="text-gray-500">{label}</span>
      <span className={strong ? "font-bold text-lg" : ""}>{value}</span>
    </div>
  );
}

function Field({ label, value, onChange, type = "text", placeholder }: {
  label: string;
  value: string;
  onChange: (v: string) => void;
  type?: string;
  placeholder?: string;
}) {
  return (
    <div>
      <Label className="text-xs">{label}</Label>
      <Input type={type} value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} className="mt-1" />
    </div>
  );
}
