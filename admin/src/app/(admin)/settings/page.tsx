"use client";
import { useEffect, useState, useCallback, useRef } from "react";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { RefreshButton } from "@/components/refresh-button";
import { ErrorBoundary } from "@/components/error-boundary";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { toast } from "@/components/toaster";
import { formatNumber, formatDateTime } from "@/lib/format";
import type {
  ProviderTestResult,
  ProviderUsage,
  TicketAttachLimits,
  TranscriptionProvider,
  TranscriptionProviderInfo,
  TranscriptionProviderSetting,
  TranscriptionProviderUsageResponse,
} from "@/lib/types";

const API_BASE = process.env.NEXT_PUBLIC_API_URL || "/api/v1";

export default function SettingsPage() {
  const [setting, setSetting] = useState<TranscriptionProviderSetting | null>(null);
  const [usage, setUsage] = useState<ProviderUsage[]>([]);
  const [saving, setSaving] = useState<TranscriptionProvider | null>(null);
  const [savingModel, setSavingModel] = useState<TranscriptionProvider | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [savedAt, setSavedAt] = useState<number | null>(null);
  const [pending, setPending] = useState<TranscriptionProvider | null>(null);
  const [savingOrder, setSavingOrder] = useState(false);

  const load = useCallback(async () => {
    const [s, u] = await Promise.all([
      api<TranscriptionProviderSetting>("/admin/settings/transcription-provider"),
      api<TranscriptionProviderUsageResponse>(
        "/admin/settings/transcription-provider/usage"
      ),
    ]);
    setSetting(s);
    setUsage(u.providers);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  // Open a confirm dialog before switching — switching affects all in-flight
  // and future jobs that don't pin a specific provider.
  function requestSelectProvider(name: TranscriptionProvider) {
    if (!setting || setting.current === name || saving) return;
    setPending(name);
  }

  async function applyProvider(name: TranscriptionProvider) {
    if (!setting || setting.current === name) return;
    setSaving(name);
    setError(null);
    try {
      const data = await api<TranscriptionProviderSetting>(
        "/admin/settings/transcription-provider",
        {
          method: "PUT",
          body: JSON.stringify({ provider: name }),
        }
      );
      setSetting(data);
      setSavedAt(Date.now());
      toast.success(`تم تبديل المزوّد الافتراضي إلى ${labelFor(name)}`);
    } catch (e) {
      const msg = e instanceof Error ? e.message : "حدث خطأ غير معروف";
      setError(msg);
      toast.error(`فشل التبديل: ${msg}`);
    } finally {
      setSaving(null);
      setPending(null);
    }
  }

  async function selectModel(name: TranscriptionProvider, modelId: string) {
    if (!setting || savingModel) return;
    setSavingModel(name);
    setError(null);
    try {
      const data = await api<TranscriptionProviderSetting>(
        "/admin/settings/transcription-provider/model",
        {
          method: "PUT",
          body: JSON.stringify({ provider: name, model: modelId }),
        }
      );
      setSetting(data);
      setSavedAt(Date.now());
      toast.success("تم حفظ النموذج");
    } catch (e) {
      const msg = e instanceof Error ? e.message : "حدث خطأ غير معروف";
      setError(msg);
      toast.error(`فشل الحفظ: ${msg}`);
    } finally {
      setSavingModel(null);
    }
  }

  // Reorder the failover priority and persist it. `delta` is -1 (move up =
  // higher priority) or +1 (move down).
  async function moveInOrder(index: number, delta: number) {
    if (!setting || savingOrder) return;
    const order = [...setting.provider_order];
    const target = index + delta;
    if (target < 0 || target >= order.length) return;
    [order[index], order[target]] = [order[target], order[index]];
    setSavingOrder(true);
    setError(null);
    try {
      const data = await api<TranscriptionProviderSetting>(
        "/admin/settings/transcription-provider/order",
        { method: "PUT", body: JSON.stringify({ order }) }
      );
      setSetting(data);
      setSavedAt(Date.now());
      toast.success("تم حفظ ترتيب الأولوية");
    } catch (e) {
      const msg = e instanceof Error ? e.message : "حدث خطأ غير معروف";
      setError(msg);
      toast.error(`فشل الحفظ: ${msg}`);
    } finally {
      setSavingOrder(false);
    }
  }

  if (!setting) {
    return (
      <div className="flex items-center justify-center h-64">
        <div className="animate-spin w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full" />
      </div>
    );
  }

  const fallbackActive = setting.current !== setting.effective;
  const usageByProvider: Record<string, ProviderUsage> = Object.fromEntries(
    usage.map((u) => [u.provider, u])
  );

  return (
    <ErrorBoundary>
      <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">إعدادات النظام</h1>
          <p className="text-sm text-gray-500 mt-1">
            تحكّم في سلوك الـ Backend بدون إعادة نشر
          </p>
        </div>
        <RefreshButton onRefresh={load} />
      </div>

      <Card className="p-6 mb-6">
        <div className="flex items-start justify-between gap-4 mb-4">
          <div>
            <h2 className="text-lg font-bold text-gray-900">مزود التفريغ النصي الافتراضي</h2>
            <p className="text-sm text-gray-500 mt-1">
              الخدمة المُستخدَمة للطلبات التي لا تُحدّد باقتها مزوّداً
              صراحةً.{" "}
              <a href="/plans" className="text-blue-600 underline">
                تحديد مزوّد لباقة معيّنة من صفحة الباقات
              </a>
            </p>
          </div>
          {savedAt && (
            <Badge variant="secondary" className="bg-green-100 text-green-700">
              تم الحفظ
            </Badge>
          )}
        </div>

        {fallbackActive && (
          <div className="mb-4 rounded-lg border border-amber-200 bg-amber-50 px-4 py-3 text-sm text-amber-800">
            ⚠️ المُختار حالياً <b>{labelFor(setting.current)}</b> لكنه غير مُعدّ
            — النظام يستخدم <b>{labelFor(setting.effective)}</b> كخيار بديل.
          </div>
        )}

        {error && (
          <div className="mb-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            {error}
          </div>
        )}

        <fieldset
          disabled={saving !== null}
          className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3"
        >
          {setting.providers.map((p) => (
            <ProviderCard
              key={p.name}
              provider={p}
              isCurrent={setting.current === p.name}
              isEffective={setting.effective === p.name}
              isSaving={saving === p.name}
              isSavingModel={savingModel === p.name}
              anySaving={saving !== null}
              usage={usageByProvider[p.name]}
              onSelect={() => requestSelectProvider(p.name)}
              onSelectModel={(m) => selectModel(p.name, m)}
              onError={setError}
            />
          ))}
        </fieldset>

        {setting.updated_at && (
          <p className="text-xs text-gray-400 mt-4">
            آخر تحديث للمزود: {formatDateTime(setting.updated_at)}
            {setting.updated_by_user_id != null && (
              <>
                {" "}· بواسطة المستخدم #
                <span dir="ltr">{setting.updated_by_user_id}</span>
              </>
            )}
          </p>
        )}
      </Card>

      {/* Auto-failover priority order */}
      <Card className="p-6 mb-6">
        <div className="mb-3">
          <h2 className="text-lg font-bold text-gray-900">
            ترتيب التبديل التلقائي (Auto-failover)
          </h2>
          <p className="text-sm text-gray-500 mt-1">
            لو المزوّد النشط فشل أثناء الطلب (الكريدت خلص، rate-limit، خطأ سيرفر)
            — النظام ينتقل تلقائياً للمزوّد اللي بعده في الترتيب ده. الطلب
            مايفشلش إلا لو <b>كل</b> المزوّدين فشلوا.
          </p>
        </div>
        <ol className="space-y-2">
          {setting.provider_order.map((name, i) => {
            const info = setting.providers.find((p) => p.name === name);
            const available = info?.available ?? false;
            return (
              <li
                key={name}
                className={`flex items-center gap-3 rounded-lg border px-3 py-2 ${
                  available
                    ? "border-gray-200 bg-white"
                    : "border-gray-200 bg-gray-50 opacity-60"
                }`}
              >
                <span className="w-6 h-6 shrink-0 rounded-full bg-blue-600 text-white text-xs font-bold flex items-center justify-center">
                  {i + 1}
                </span>
                <span className="flex-1 font-medium text-gray-800">
                  {labelFor(name)}
                </span>
                {!available && (
                  <Badge variant="outline" className="text-gray-500">
                    غير مُعدّ
                  </Badge>
                )}
                <div className="flex gap-1">
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={i === 0 || savingOrder}
                    onClick={() => moveInOrder(i, -1)}
                    aria-label="رفع الأولوية"
                  >
                    ↑
                  </Button>
                  <Button
                    variant="outline"
                    size="sm"
                    disabled={i === setting.provider_order.length - 1 || savingOrder}
                    onClick={() => moveInOrder(i, 1)}
                    aria-label="خفض الأولوية"
                  >
                    ↓
                  </Button>
                </div>
              </li>
            );
          })}
        </ol>
        <p className="text-xs text-gray-400 mt-3">
          رقم 1 = الأعلى أولوية. المزوّدين &quot;غير مُعدّ&quot; بيتم تخطّيهم
          تلقائياً في السلسلة.
        </p>
      </Card>

      <TicketAttachmentSettings />

      <Card className="p-6">
        <h3 className="font-bold text-gray-900 mb-2">ملاحظات</h3>
        <ul className="text-sm text-gray-600 space-y-1 list-disc pe-5">
          <li>
            <b>الافتراضي</b> أعلاه يطبَّق فقط لما الباقة لا تُحدّد مزوّداً
            بنفسها — تقدر تحدّد مزوّداً مختلفاً لكل باقة من <a href="/plans" className="text-blue-600 underline">صفحة الباقات</a>.
          </li>
          <li>
            <b>زر التجربة</b> يأخذ ملف صوتي صغير (mp3/wav/m4a) ويحاول التفريغ
            بالمزوّد+الموديل المختار — لا يُسجَّل ضمن طلبات المستخدمين.
          </li>
          <li>
            أرقام &quot;اليوم/الشهر/الإجمالي&quot; محسوبة من قاعدة بياناتنا
            بناءً على عمود <code className="font-mono">provider_used</code>.
          </li>
        </ul>
      </Card>

      <ConfirmDialog
        open={pending !== null}
        onOpenChange={(o) => {
          if (!o) setPending(null);
        }}
        title="تأكيد تبديل المزوّد الافتراضي"
        description={
          pending ? (
            <span>
              سيتم تحويل كل الطلبات الجديدة (التي لا تُحدّد باقتها مزوّداً) إلى{" "}
              <b>{labelFor(pending)}</b>. الطلبات الجارية حالياً قد تتأثر إذا
              لم تنتهِ بعد. هل تريد المتابعة؟
            </span>
          ) : null
        }
        confirmLabel="نعم، بدّل الآن"
        cancelLabel="إلغاء"
        destructive
        loading={saving !== null}
        onConfirm={async () => {
          if (pending) await applyProvider(pending);
        }}
      />
      </div>
    </ErrorBoundary>
  );
}

function ProviderCard({
  provider,
  isCurrent,
  isEffective,
  isSaving,
  isSavingModel,
  anySaving,
  usage,
  onSelect,
  onSelectModel,
  onError,
}: {
  provider: TranscriptionProviderInfo;
  isCurrent: boolean;
  isEffective: boolean;
  isSaving: boolean;
  isSavingModel: boolean;
  anySaving: boolean;
  usage: ProviderUsage | undefined;
  onSelect: () => void;
  onSelectModel: (modelId: string) => void;
  onError: (msg: string) => void;
}) {
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<ProviderTestResult | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);

  const effectiveModelId =
    provider.selected_model || provider.default_model || provider.models[0]?.id;

  async function runTest(file: File) {
    setTesting(true);
    setTestResult(null);
    onError("");
    try {
      const form = new FormData();
      form.append("provider", provider.name);
      if (effectiveModelId) form.append("model", effectiveModelId);
      form.append("file", file);

      const token = localStorage.getItem("admin_token");
      const res = await fetch(
        `${API_BASE}/admin/settings/transcription-provider/test`,
        {
          method: "POST",
          headers: token ? { Authorization: `Bearer ${token}` } : undefined,
          body: form,
        }
      );
      if (!res.ok) {
        const err = await res.json().catch(() => ({}));
        throw new Error(err.detail || `Error ${res.status}`);
      }
      const data = (await res.json()) as ProviderTestResult;
      setTestResult(data);
    } catch (e) {
      onError(e instanceof Error ? e.message : "فشل الاختبار");
    } finally {
      setTesting(false);
    }
  }

  return (
    <div
      className={`text-right rounded-xl border-2 p-4 flex flex-col gap-3 ${
        isCurrent
          ? "border-blue-600 bg-blue-50"
          : provider.available
            ? "border-gray-200 bg-white"
            : "border-gray-200 bg-gray-50 opacity-70"
      }`}
    >
      <div>
        <div className="flex items-center justify-between mb-2 flex-wrap gap-2">
          <div className="flex items-center gap-2 flex-wrap">
            <span className="font-bold text-gray-900">{provider.label}</span>
            {isCurrent && <Badge className="bg-blue-600 text-white">المُحدّد</Badge>}
            {!isCurrent && isEffective && (
              <Badge variant="secondary">قيد التشغيل</Badge>
            )}
          </div>
          <Badge
            variant={provider.available ? "secondary" : "outline"}
            className={
              provider.available
                ? "bg-green-100 text-green-700"
                : "text-gray-500"
            }
          >
            {provider.available ? "جاهز" : "غير مُعدّ"}
          </Badge>
        </div>
        <p className="text-xs text-gray-600 leading-relaxed">
          {provider.description}
        </p>
      </div>

      {/* Sub-model dropdown */}
      {provider.models.length > 0 && (
        <div>
          <label className="text-xs font-semibold text-gray-700 block mb-1">
            النموذج
          </label>
          <select
            value={effectiveModelId || ""}
            onChange={(e) => onSelectModel(e.target.value)}
            disabled={!provider.available || isSavingModel}
            className="w-full text-xs border border-gray-300 rounded-md px-2 py-1.5 bg-white disabled:bg-gray-100"
          >
            {provider.models.map((m) => (
              <option key={m.id} value={m.id}>
                {m.label}
              </option>
            ))}
          </select>
          {isSavingModel && (
            <div className="text-[10px] text-blue-600 mt-1">جاري الحفظ…</div>
          )}
        </div>
      )}

      {/* Usage block */}
      {usage && (
        <div className="border-t border-gray-200 pt-2 text-xs space-y-1">
          {usage.free_tier_limit_text && (
            <div className="text-gray-500">
              <span className="font-semibold text-gray-700">Free tier: </span>
              {usage.free_tier_limit_text}
            </div>
          )}
          <div className="grid grid-cols-3 gap-1 mt-1">
            <UsageStat label="اليوم" value={usage.local.requests_today} />
            <UsageStat label="الشهر" value={usage.local.requests_month} />
            <UsageStat label="إجمالي" value={usage.local.requests_total} />
          </div>
          <div className="text-gray-500">
            مدّة معالجة الشهر:{" "}
            <b>{formatSeconds(usage.local.seconds_month)}</b>
          </div>
          {usage.remote && (
            <div className="text-emerald-700 bg-emerald-50 rounded px-2 py-1 mt-1">
              من المزوّد: {usage.remote.total_hours_month} ساعة هذا الشهر
            </div>
          )}
        </div>
      )}

      {/* Actions */}
      <div className="flex gap-2 mt-auto pt-2 border-t border-gray-200">
        <Button
          variant={isCurrent ? "secondary" : "default"}
          size="sm"
          onClick={onSelect}
          disabled={!provider.available || anySaving || isCurrent}
          className="flex-1"
        >
          {isSaving ? "جاري…" : isCurrent ? "نشط" : "اعتمده افتراضي"}
        </Button>
        <Button
          variant="outline"
          size="sm"
          onClick={() => fileInputRef.current?.click()}
          disabled={!provider.available || testing}
        >
          {testing ? "اختبار…" : "اختبار"}
        </Button>
        <input
          ref={fileInputRef}
          type="file"
          accept="audio/*,.mp3,.wav,.m4a,.ogg,.flac,.aac,.webm,.mp4"
          className="hidden"
          onChange={(e) => {
            const f = e.target.files?.[0];
            if (f) runTest(f);
            e.target.value = "";
          }}
        />
      </div>

      {/* Test result */}
      {testResult && (
        <div className="rounded-md border border-emerald-200 bg-emerald-50 p-2 text-xs">
          <div className="flex justify-between mb-1 text-emerald-800 font-semibold">
            <span>نجح الاختبار</span>
            <span>{(testResult.duration_ms / 1000).toFixed(2)}s</span>
          </div>
          <div className="text-gray-600 mb-1">
            صوت {testResult.audio_seconds}s · {testResult.word_count} كلمة ·{" "}
            {testResult.language}
          </div>
          <div className="bg-white rounded p-2 max-h-24 overflow-y-auto text-gray-800 leading-relaxed">
            {testResult.text || <span className="text-gray-400">(لا نص)</span>}
          </div>
        </div>
      )}
    </div>
  );
}

function UsageStat({ label, value }: { label: string; value: number }) {
  return (
    <div className="bg-gray-50 rounded px-2 py-1 text-center">
      <div className="text-[10px] text-gray-500">{label}</div>
      <div className="font-bold text-gray-900" dir="ltr">
        {formatNumber(value)}
      </div>
    </div>
  );
}

function labelFor(name: TranscriptionProvider): string {
  const map: Record<TranscriptionProvider, string> = {
    speechmatics: "Speechmatics",
    gemini: "Gemini",
    groq: "Groq",
    assemblyai: "AssemblyAI",
  };
  return map[name] || name;
}

// Allowed extensions exposed in the UI — server keeps its own whitelist as a
// safety net, so we only show ones that are known-safe.
const ATTACH_EXT_CHOICES = ["jpg", "jpeg", "png", "webp", "heic"] as const;

function TicketAttachmentSettings() {
  const [limits, setLimits] = useState<TicketAttachLimits | null>(null);
  const [maxMb, setMaxMb] = useState<string>("5");
  const [extensions, setExtensions] = useState<Set<string>>(new Set());
  const [saving, setSaving] = useState(false);

  const load = useCallback(async () => {
    const data = await api<TicketAttachLimits>(
      "/admin/settings/ticket-attachments",
    );
    setLimits(data);
    setMaxMb((data.max_bytes / (1024 * 1024)).toString());
    setExtensions(new Set(data.allowed_extensions));
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  function toggleExt(ext: string) {
    setExtensions((prev) => {
      const next = new Set(prev);
      if (next.has(ext)) next.delete(ext);
      else next.add(ext);
      return next;
    });
  }

  async function save() {
    const mb = Number.parseFloat(maxMb);
    if (!Number.isFinite(mb) || mb <= 0) {
      toast.error("الحجم الأقصى يجب أن يكون رقماً موجباً");
      return;
    }
    if (mb > 100) {
      toast.error("الحجم الأقصى لا يتجاوز 100 ميجا");
      return;
    }
    if (extensions.size === 0) {
      toast.error("اختر امتداداً واحداً على الأقل");
      return;
    }
    setSaving(true);
    try {
      const data = await api<TicketAttachLimits>(
        "/admin/settings/ticket-attachments",
        {
          method: "PUT",
          body: JSON.stringify({
            max_bytes: Math.round(mb * 1024 * 1024),
            allowed_extensions: Array.from(extensions),
          }),
        },
      );
      setLimits(data);
      setMaxMb((data.max_bytes / (1024 * 1024)).toString());
      setExtensions(new Set(data.allowed_extensions));
      toast.success("تم حفظ حدود المرفقات");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "فشل الحفظ");
    } finally {
      setSaving(false);
    }
  }

  if (!limits) {
    return (
      <Card className="p-6 mb-6">
        <div className="h-24 animate-pulse bg-gray-100 rounded" />
      </Card>
    );
  }

  return (
    <Card className="p-6 mb-6">
      <div className="mb-4">
        <h2 className="text-lg font-bold text-gray-900">
          حدود مرفقات تذاكر الدعم
        </h2>
        <p className="text-sm text-gray-500 mt-1">
          الحد الأقصى لحجم الصورة والامتدادات المسموح بها للمستخدمين عند رفع
          سكرين شوت داخل تذكرة دعم.
        </p>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div>
          <Label htmlFor="ticket-attach-max-mb">الحجم الأقصى (ميجا بايت)</Label>
          <Input
            id="ticket-attach-max-mb"
            type="number"
            min={1}
            max={100}
            step={1}
            value={maxMb}
            onChange={(e) => setMaxMb(e.target.value)}
            className="mt-1"
            dir="ltr"
          />
          <p className="text-xs text-gray-400 mt-1">
            الحد الأقصى المطلق 100 ميجا — موصى به 5–10 ميجا.
          </p>
        </div>
        <div>
          <span className="text-sm font-medium text-gray-700">
            الامتدادات المسموح بها
          </span>
          <div className="mt-2 flex flex-wrap gap-2">
            {ATTACH_EXT_CHOICES.map((ext) => {
              const checked = extensions.has(ext);
              return (
                <label
                  key={ext}
                  className={`inline-flex items-center gap-1.5 rounded-lg border px-3 py-1.5 text-sm cursor-pointer select-none ${
                    checked
                      ? "border-blue-600 bg-blue-50 text-blue-700"
                      : "border-gray-200 bg-white text-gray-700"
                  }`}
                >
                  <input
                    type="checkbox"
                    checked={checked}
                    onChange={() => toggleExt(ext)}
                    className="accent-blue-600"
                  />
                  <span dir="ltr">.{ext}</span>
                </label>
              );
            })}
          </div>
        </div>
      </div>

      <div className="flex justify-end mt-4">
        <Button onClick={save} disabled={saving}>
          {saving ? "جاري الحفظ…" : "حفظ الحدود"}
        </Button>
      </div>
    </Card>
  );
}

function formatSeconds(s: number): string {
  if (s < 60) return `${s.toFixed(0)} ث`;
  if (s < 3600) return `${(s / 60).toFixed(1)} د`;
  return `${(s / 3600).toFixed(2)} س`;
}
