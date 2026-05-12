"use client";
import { useEffect, useState, useCallback } from "react";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { RefreshButton } from "@/components/refresh-button";
import type {
  TranscriptionProvider,
  TranscriptionProviderSetting,
} from "@/lib/types";

export default function SettingsPage() {
  const [setting, setSetting] = useState<TranscriptionProviderSetting | null>(null);
  const [saving, setSaving] = useState<TranscriptionProvider | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [savedAt, setSavedAt] = useState<number | null>(null);

  const load = useCallback(async () => {
    const data = await api<TranscriptionProviderSetting>(
      "/admin/settings/transcription-provider"
    );
    setSetting(data);
  }, []);

  useEffect(() => {
    load();
  }, [load]);

  async function selectProvider(name: TranscriptionProvider) {
    if (!setting || setting.current === name || saving) return;
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
    } catch (e) {
      setError(e instanceof Error ? e.message : "حدث خطأ غير معروف");
    } finally {
      setSaving(null);
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

  return (
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
            <h2 className="text-lg font-bold text-gray-900">مزود التفريغ النصي</h2>
            <p className="text-sm text-gray-500 mt-1">
              الخدمة المُستخدَمة لتحويل الصوت إلى نص لكل المستخدمين
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
            ⚠️ المُختار حالياً <b>{labelFor(setting.current)}</b> لكنه غير
            مُعدّ، فالنظام يستخدم <b>{labelFor(setting.effective)}</b> كخيار
            بديل حتى تضبط الإعدادات.
          </div>
        )}

        {error && (
          <div className="mb-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
            {error}
          </div>
        )}

        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {setting.providers.map((p) => {
            const isCurrent = setting.current === p.name;
            const isEffective = setting.effective === p.name;
            const isSaving = saving === p.name;
            const disabled = !p.available || isSaving || isCurrent;
            return (
              <button
                key={p.name}
                onClick={() => selectProvider(p.name)}
                disabled={disabled}
                className={`text-right rounded-xl border-2 p-4 transition ${
                  isCurrent
                    ? "border-blue-600 bg-blue-50"
                    : p.available
                      ? "border-gray-200 bg-white hover:border-blue-300"
                      : "border-gray-200 bg-gray-50 opacity-60 cursor-not-allowed"
                }`}
              >
                <div className="flex items-center justify-between mb-2">
                  <div className="flex items-center gap-2">
                    <span className="font-bold text-gray-900">{p.label}</span>
                    {isCurrent && (
                      <Badge className="bg-blue-600 text-white">المُحدّد</Badge>
                    )}
                    {!isCurrent && isEffective && (
                      <Badge variant="secondary">قيد التشغيل</Badge>
                    )}
                  </div>
                  <Badge
                    variant={p.available ? "secondary" : "outline"}
                    className={p.available ? "bg-green-100 text-green-700" : "text-gray-500"}
                  >
                    {p.available ? "جاهز" : "غير مُعدّ"}
                  </Badge>
                </div>
                <p className="text-xs text-gray-600 leading-relaxed">
                  {p.description}
                </p>
                {isSaving && (
                  <div className="mt-2 text-xs text-blue-600">جاري التبديل…</div>
                )}
              </button>
            );
          })}
        </div>

        {setting.updated_at && (
          <p className="text-xs text-gray-400 mt-4">
            آخر تحديث: {new Date(setting.updated_at).toLocaleString("ar-EG")}
            {setting.updated_by_user_id != null && (
              <> · بواسطة المستخدم #{setting.updated_by_user_id}</>
            )}
          </p>
        )}
      </Card>

      <Card className="p-6">
        <h3 className="font-bold text-gray-900 mb-2">ملاحظات</h3>
        <ul className="text-sm text-gray-600 space-y-1 list-disc pr-5">
          <li>التبديل بين المزوّدين يأخذ تأثيره فوراً على الطلبات الجديدة.</li>
          <li>
            Speechmatics يحتاج المتغيّر <code className="font-mono">SP</code> في
            ملف <code className="font-mono">.env</code>؛ إذا كان فارغاً سيظهر
            كـ &quot;غير مُعدّ&quot;.
          </li>
          <li>
            تبديلك لمزود Whisper بعد بداية السيرفر يحمّل النموذج عند أول طلب
            (قد يأخذ ثواني أوّل مرة).
          </li>
        </ul>
      </Card>
    </div>
  );
}

function labelFor(name: TranscriptionProvider): string {
  return name === "whisper" ? "Whisper (محلي)" : "Speechmatics";
}
