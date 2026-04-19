"use client";
import { useEffect, useState, useCallback } from "react";
import { useParams, useRouter } from "next/navigation";
import { api } from "@/lib/api";
import { getCurrentAdminId } from "@/lib/auth";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { RefreshButton } from "@/components/refresh-button";
import {
  Dialog,
  DialogContent,
  DialogFooter,
  DialogHeader,
  DialogTitle,
  DialogDescription,
} from "@/components/ui/dialog";
import type { UserDetail, SessionItem, PlanAdminItem } from "@/lib/types";

const PLAN_LABEL: Record<string, string> = {
  free: "مجاني",
  monthly: "شهري",
  annual: "سنوي",
};

const SOURCE_LABEL: Record<string, string> = {
  free: "مجاني",
  coupon: "كوبون",
  purchase: "مدفوع",
};

const PLATFORM_ICON: Record<string, string> = {
  ios: "🍎",
  android: "🤖",
  web: "🌐",
  unknown: "❔",
};

function UsageBar({ used, limit, label }: { used: number; limit: number | null; label: string }) {
  const isUnlimited = limit === -1;
  const isDisabled = limit === 0;
  const isUntracked = limit === null;
  const pct = !isUnlimited && !isDisabled && !isUntracked && limit > 0 ? Math.min((used / limit) * 100, 100) : 0;
  const over = !isUnlimited && !isDisabled && !isUntracked && used >= (limit || 0);

  let rightText: string;
  if (isDisabled) rightText = "معطّل";
  else if (isUnlimited) rightText = `${used} / ∞`;
  else if (isUntracked) rightText = `${used} / —`;
  else rightText = `${used} / ${limit}`;

  return (
    <div>
      <div className="flex justify-between text-xs mb-1">
        <span className="text-gray-600">{label}</span>
        <span className={`font-medium ${over ? "text-red-600" : "text-gray-700"}`}>{rightText}</span>
      </div>
      <div className="h-2 bg-gray-100 rounded-full overflow-hidden">
        <div
          className={`h-full transition-all ${over ? "bg-red-500" : "bg-blue-500"}`}
          style={{ width: `${isUnlimited || isDisabled || isUntracked ? (isUnlimited ? 100 : 0) : pct}%`, opacity: isUnlimited ? 0.25 : 1 }}
        />
      </div>
    </div>
  );
}

export default function UserDetailPage() {
  const { id } = useParams();
  const router = useRouter();
  const [user, setUser] = useState<UserDetail | null>(null);
  const [sessions, setSessions] = useState<SessionItem[]>([]);
  const [plans, setPlans] = useState<PlanAdminItem[]>([]);
  const currentAdminId = getCurrentAdminId();
  const isSelf = user !== null && currentAdminId === user.id;

  const [editOpen, setEditOpen] = useState(false);
  const [editForm, setEditForm] = useState({ full_name: "", email: "" });
  const [editError, setEditError] = useState<string | null>(null);

  const [subOpen, setSubOpen] = useState(false);
  const [subForm, setSubForm] = useState({ plan_id: "", duration_days: "", coupon_code: "" });
  const [subError, setSubError] = useState<string | null>(null);

  const load = useCallback(async () => {
    const [u, s, p] = await Promise.all([
      api<UserDetail>(`/admin/users/${id}`),
      api<SessionItem[]>(`/admin/users/${id}/sessions?limit=50`),
      api<PlanAdminItem[]>("/admin/plans"),
    ]);
    setUser(u);
    setSessions(s);
    setPlans(p);
  }, [id]);

  useEffect(() => { load(); }, [load]);

  // Scroll to sessions if hash is #sessions
  useEffect(() => {
    if (typeof window !== "undefined" && window.location.hash === "#sessions" && user) {
      const el = document.getElementById("sessions");
      el?.scrollIntoView({ behavior: "smooth" });
    }
  }, [user]);

  async function toggleActive() {
    if (!user) return;
    await api(`/admin/users/${id}`, { method: "PUT", body: JSON.stringify({ is_active: !user.is_active }) });
    await load();
  }

  async function toggleRole() {
    if (!user) return;
    const newRole = user.role === "admin" ? "user" : "admin";
    await api(`/admin/users/${id}`, { method: "PUT", body: JSON.stringify({ role: newRole }) });
    await load();
  }

  function openEdit() {
    if (!user) return;
    setEditForm({ full_name: user.full_name || "", email: user.email || "" });
    setEditError(null);
    setEditOpen(true);
  }

  async function saveEdit() {
    try {
      await api(`/admin/users/${id}`, {
        method: "PUT",
        body: JSON.stringify({ full_name: editForm.full_name || null, email: editForm.email || null }),
      });
      setEditOpen(false);
      await load();
    } catch (e) {
      setEditError(e instanceof Error ? e.message : "فشل الحفظ");
    }
  }

  function openSubscribe() {
    setSubForm({ plan_id: "", duration_days: "", coupon_code: "" });
    setSubError(null);
    setSubOpen(true);
  }

  async function saveSubscribe() {
    if (!subForm.plan_id) {
      setSubError("اختر باقة");
      return;
    }
    try {
      await api(`/admin/users/${id}/subscribe`, {
        method: "POST",
        body: JSON.stringify({
          plan_id: Number(subForm.plan_id),
          duration_days: subForm.duration_days ? Number(subForm.duration_days) : null,
          coupon_code: subForm.coupon_code.trim() || null,
        }),
      });
      setSubOpen(false);
      await load();
    } catch (e) {
      setSubError(e instanceof Error ? e.message : "فشل الاشتراك");
    }
  }

  async function cancelSubscription() {
    if (!window.confirm("إلغاء الاشتراك الحالي؟ (الباقة ستبقى فعّالة حتى انتهاء المدة لو أنت بتلغي بالواجهة الرسمية، لكن هذا الأمر بيلغيها فوراً ويرجعها للمجاني)")) return;
    await api(`/admin/users/${id}/cancel-subscription`, { method: "POST" });
    await load();
  }

  if (!user) return <div className="flex items-center justify-center h-64"><div className="animate-spin w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full" /></div>;

  const sub = user.subscription;
  const usage = user.usage;
  const planLabel = PLAN_LABEL[sub.plan_name] || sub.plan_name;

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <Button variant="outline" size="sm" onClick={() => router.back()}>← رجوع</Button>
        <div className="flex gap-2">
          <RefreshButton onRefresh={load} />
          <Button variant="outline" onClick={openEdit}>تعديل البيانات</Button>
          <Button
            variant="outline"
            onClick={toggleRole}
            disabled={isSelf}
            title={isSelf ? "مينفعش تشيل صلاحيات الأدمن من نفسك" : undefined}
          >
            {user.role === "admin" ? "إزالة صلاحية الأدمن" : "ترقية لأدمن"}
          </Button>
          <Button
            variant={user.is_active ? "destructive" : "default"}
            onClick={toggleActive}
            disabled={isSelf}
            title={isSelf ? "مينفعش تحظر حسابك" : undefined}
          >
            {user.is_active ? "حظر المستخدم" : "تفعيل المستخدم"}
          </Button>
        </div>
      </div>
      {isSelf && (
        <div className="text-xs text-amber-700 bg-amber-50 border border-amber-200 rounded-lg px-3 py-2">
          ⚠️ ده حسابك أنت — أزرار إزالة الأدمن والحظر معطّلة عشان ماتقفلش نفسك بره.
        </div>
      )}

      <h1 className="text-2xl font-bold text-gray-900">{user.full_name || user.username}</h1>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Profile */}
        <Card className="p-6">
          <h2 className="text-lg font-bold mb-4">البيانات الشخصية</h2>
          <div className="space-y-3 text-sm">
            <Row label="الاسم" value={user.full_name || "-"} />
            <Row label="المستخدم" value={user.username} />
            <Row label="الإيميل" value={user.email || "-"} />
            <Row label="التسجيل عبر" value={<Badge variant="secondary">{user.auth_provider}</Badge>} />
            <Row label="تاريخ التسجيل" value={user.created_at ? new Date(user.created_at).toLocaleString("ar") : "-"} />
            <Row label="الدور" value={<Badge>{user.role}</Badge>} />
            <Row label="الحالة" value={<Badge variant={user.is_active ? "default" : "destructive"}>{user.is_active ? "نشط" : "محظور"}</Badge>} />
            <Row label="الجلسات النشطة (7 أيام)" value={<Badge variant={user.active_sessions > 0 ? "default" : "secondary"}>{user.active_sessions}</Badge>} />
            <Row label="إجمالي الطلبات" value={<span className="font-bold text-lg">{user.total_requests}</span>} />
          </div>

          {user.survey_response && (
            <div className="mt-6 p-4 bg-gray-50 rounded-lg">
              <h3 className="text-sm font-bold text-gray-700 mb-2">الاستبيان</h3>
              <pre className="text-xs text-gray-600 whitespace-pre-wrap break-words">{user.survey_response}</pre>
            </div>
          )}
        </Card>

        {/* Subscription */}
        <Card className="p-6">
          <div className="flex items-center justify-between mb-4">
            <h2 className="text-lg font-bold">الاشتراك الحالي</h2>
            <div className="flex gap-2">
              <Button size="sm" onClick={openSubscribe}>{sub.is_active && sub.plan_name !== "free" ? "ترقية / تغيير" : "إضافة باقة"}</Button>
              {sub.is_active && sub.plan_name !== "free" && (
                <Button size="sm" variant="outline" onClick={cancelSubscription}>إلغاء</Button>
              )}
            </div>
          </div>

          <div className="space-y-3 text-sm mb-4">
            <Row label="الباقة" value={
              <div className="flex items-center gap-2">
                <Badge variant={sub.plan_name === "free" ? "secondary" : "default"}>{planLabel}</Badge>
                <Badge variant="outline" className="text-xs">{SOURCE_LABEL[sub.plan_source]}</Badge>
              </div>
            } />
            {sub.coupon_code && <Row label="الكوبون المستخدم" value={<code className="text-xs bg-gray-100 px-2 py-0.5 rounded">{sub.coupon_code}</code>} />}
            {sub.starts_at && <Row label="بدأت" value={new Date(sub.starts_at).toLocaleString("ar")} />}
            {sub.expires_at && <Row label="تنتهي" value={new Date(sub.expires_at).toLocaleString("ar")} />}
            {sub.days_remaining !== null && (
              <Row label="المتبقي" value={
                <Badge variant={sub.days_remaining <= 3 ? "destructive" : sub.days_remaining <= 7 ? "secondary" : "default"}>
                  {sub.days_remaining} يوم
                </Badge>
              } />
            )}
          </div>

          <hr className="my-4" />
          <h3 className="text-sm font-bold mb-3">الاستهلاك</h3>
          <div className="space-y-3">
            <UsageBar label="طلبات اليوم (تحويل الصوت)" used={usage.requests_today} limit={usage.daily_limit} />
            <UsageBar label="طلبات الشهر الحالي" used={usage.requests_this_month} limit={usage.monthly_limit} />
            <UsageBar label="طلبات API اليوم" used={usage.requests_today_api} limit={usage.api_daily_limit === -1 ? usage.daily_limit : usage.api_daily_limit} />
            <Row label="أقصى مدة للصوت الواحد" value={usage.max_audio_seconds === -1 ? "بلا حدود" : `${usage.max_audio_seconds} ث`} />
          </div>
        </Card>
      </div>

      {/* Sessions */}
      <Card id="sessions" className="p-6">
        <h2 className="text-lg font-bold mb-4">الجلسات (آخر {sessions.length})</h2>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-gray-500">
                <th className="text-right pb-2">الوقت</th>
                <th className="text-right pb-2">النوع</th>
                <th className="text-right pb-2">الطريقة</th>
                <th className="text-right pb-2">الحالة</th>
                <th className="text-right pb-2">الجهاز</th>
                <th className="text-right pb-2">IP</th>
                <th className="text-right pb-2">الإصدار</th>
              </tr>
            </thead>
            <tbody>
              {sessions.map((s) => (
                <tr key={s.id} className="border-b last:border-0">
                  <td className="py-2 text-xs text-gray-600">{new Date(s.created_at).toLocaleString("ar")}</td>
                  <td className="py-2"><Badge variant="secondary">{s.event_type}</Badge></td>
                  <td className="py-2 text-xs">{s.auth_provider}</td>
                  <td className="py-2">
                    {s.success ? (
                      s.is_active
                        ? <Badge variant="default">نشط</Badge>
                        : <Badge variant="secondary">قديم</Badge>
                    ) : (
                      <Badge variant="destructive" title={s.error_message || undefined}>فشل</Badge>
                    )}
                  </td>
                  <td className="py-2 text-xs">
                    <div className="flex items-center gap-1">
                      <span>{PLATFORM_ICON[s.device_platform || "unknown"] || "❔"}</span>
                      <span>{s.device_model || s.device_platform || "—"}</span>
                      {s.device_os_version && <span className="text-gray-400">({s.device_os_version})</span>}
                    </div>
                  </td>
                  <td className="py-2 text-xs text-gray-600 font-mono">{s.ip_address || "—"}</td>
                  <td className="py-2 text-xs text-gray-500">{s.app_version || "—"}</td>
                </tr>
              ))}
              {sessions.length === 0 && (
                <tr><td colSpan={7} className="py-8 text-center text-gray-400">لا توجد جلسات مسجلة</td></tr>
              )}
            </tbody>
          </table>
        </div>
      </Card>

      {/* Edit dialog */}
      <Dialog open={editOpen} onOpenChange={setEditOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>تعديل بيانات المستخدم</DialogTitle>
            <DialogDescription>يمكن تعديل الاسم والإيميل. لتعديل الحالة أو الدور، استخدم الأزرار بالأعلى.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-3 py-2">
            <div>
              <Label className="text-xs">الاسم الكامل</Label>
              <Input className="mt-1" value={editForm.full_name} onChange={(e) => setEditForm({ ...editForm, full_name: e.target.value })} />
            </div>
            <div>
              <Label className="text-xs">الإيميل</Label>
              <Input type="email" className="mt-1" value={editForm.email} onChange={(e) => setEditForm({ ...editForm, email: e.target.value })} />
            </div>
            {editError && <div className="text-red-600 text-sm">{editError}</div>}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEditOpen(false)}>إلغاء</Button>
            <Button onClick={saveEdit}>حفظ</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Subscribe / Upgrade dialog */}
      <Dialog open={subOpen} onOpenChange={setSubOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>إضافة / ترقية الباقة</DialogTitle>
            <DialogDescription>المدة: فارغ = الافتراضي (شهرية=30 يوم، سنوية=365 يوم). الكوبون اختياري.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-3 py-2">
            <div>
              <Label className="text-xs">الباقة</Label>
              <select
                className="mt-1 w-full h-8 rounded-lg border border-input bg-transparent px-2.5 text-sm"
                value={subForm.plan_id}
                onChange={(e) => setSubForm({ ...subForm, plan_id: e.target.value })}
              >
                <option value="">اختر باقة...</option>
                {plans.filter(p => p.is_active).map((p) => (
                  <option key={p.id} value={p.id}>
                    {PLAN_LABEL[p.name] || p.name} — {p.price === 0 ? "مجاني" : `${p.price}`}
                  </option>
                ))}
              </select>
            </div>
            <div>
              <Label className="text-xs">المدة (أيام) — اختياري</Label>
              <Input type="number" className="mt-1" value={subForm.duration_days} onChange={(e) => setSubForm({ ...subForm, duration_days: e.target.value })} placeholder="سيُستخدم الافتراضي لو فارغ" />
            </div>
            <div>
              <Label className="text-xs">كود الكوبون — اختياري</Label>
              <Input className="mt-1" value={subForm.coupon_code} onChange={(e) => setSubForm({ ...subForm, coupon_code: e.target.value.toUpperCase() })} />
            </div>
            {subError && <div className="text-red-600 text-sm">{subError}</div>}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setSubOpen(false)}>إلغاء</Button>
            <Button onClick={saveSubscribe}>حفظ</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}

function Row({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex justify-between items-center">
      <span className="text-gray-500">{label}</span>
      <span>{value}</span>
    </div>
  );
}
