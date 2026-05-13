"use client";
import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Label } from "@/components/ui/label";
import { Textarea } from "@/components/ui/textarea";
import { toast } from "@/components/toast";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { formatDateTime } from "@/lib/format";
import type { TelegramBotMessageItem } from "@/lib/types";

type ApiResponse = { items: TelegramBotMessageItem[] };

export default function TelegramBotMessagesPage() {
  const [items, setItems] = useState<TelegramBotMessageItem[]>([]);
  const [loading, setLoading] = useState(true);
  // Local edits keyed by message key. ``undefined`` means the textarea
  // mirrors the server value; a string means the admin has typed.
  const [drafts, setDrafts] = useState<Record<string, string>>({});
  const [savingKey, setSavingKey] = useState<string | null>(null);
  const [resetTarget, setResetTarget] = useState<TelegramBotMessageItem | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const r = await api<ApiResponse>("/admin/telegram/messages");
      setItems(r.items || []);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "تعذّر تحميل الرسائل");
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { void load(); }, [load]);

  function effectiveValue(item: TelegramBotMessageItem): string {
    return drafts[item.key] !== undefined ? drafts[item.key] : item.text_ar;
  }

  function isDirty(item: TelegramBotMessageItem): boolean {
    return drafts[item.key] !== undefined && drafts[item.key] !== item.text_ar;
  }

  async function save(item: TelegramBotMessageItem) {
    const value = effectiveValue(item);
    setSavingKey(item.key);
    try {
      await api(`/admin/telegram/messages/${encodeURIComponent(item.key)}`, {
        method: "PUT",
        body: JSON.stringify({ text_ar: value }),
      });
      toast.success("تم الحفظ");
      setDrafts((prev) => {
        const next = { ...prev };
        delete next[item.key];
        return next;
      });
      await load();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "فشل الحفظ");
    } finally {
      setSavingKey(null);
    }
  }

  async function doReset() {
    if (!resetTarget) return;
    const item = resetTarget;
    setSavingKey(item.key);
    try {
      await api(`/admin/telegram/messages/${encodeURIComponent(item.key)}`, {
        method: "PUT",
        body: JSON.stringify({ text_ar: "" }),
      });
      toast.success(`تم استرجاع النص الافتراضي لـ ${item.key}`);
      setDrafts((prev) => {
        const next = { ...prev };
        delete next[item.key];
        return next;
      });
      setResetTarget(null);
      await load();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "فشل الاسترجاع");
    } finally {
      setSavingKey(null);
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">رسائل البوت</h1>
          <p className="text-sm text-gray-500 mt-1">
            النصوص اللي البوت بيبعتها للمستخدمين. التعديل بياخد مفعوله فوراً.
          </p>
        </div>
        <Link href="/telegram">
          <Button variant="outline" size="sm">← الرجوع</Button>
        </Link>
      </div>

      <Card className="p-4 mb-6 bg-blue-50 border-blue-200">
        <div className="text-sm text-blue-900">
          <strong>الـ Placeholders المتاحة</strong> (تظهر داخل أقواس مجعدة): تختلف لكل رسالة.
          مثلاً <code dir="ltr">{`{first_name}`}</code> في رسالة الترحيب،{" "}
          <code dir="ltr">{`{plan}`}</code> و <code dir="ltr">{`{limit}`}</code> في رسائل الباقات.
          لو حذفت placeholder من النص، البوت هيرسل المتغير زي ما هو (مش هيكسر).
          اترك النص فاضي وضغط حفظ لاستعادة الافتراضي.
        </div>
      </Card>

      {loading && items.length === 0 ? (
        <div className="py-16 text-center text-gray-400">جاري التحميل...</div>
      ) : (
        <div className="space-y-4">
          {items.map((item) => {
            const dirty = isDirty(item);
            const value = effectiveValue(item);
            return (
              <Card key={item.key} className="p-5">
                <div className="flex items-start justify-between flex-wrap gap-3 mb-3">
                  <div>
                    <div className="flex items-center gap-2">
                      <code className="text-xs bg-gray-100 px-2 py-0.5 rounded font-mono" dir="ltr">
                        {item.key}
                      </code>
                      {item.is_default ? (
                        <Badge variant="secondary">افتراضي</Badge>
                      ) : (
                        <Badge variant="default">معدّل</Badge>
                      )}
                      {dirty && <Badge variant="destructive">تعديل غير محفوظ</Badge>}
                    </div>
                    {item.description && (
                      <p className="text-sm text-gray-600 mt-1.5">{item.description}</p>
                    )}
                    {item.updated_at && !item.is_default && (
                      <p className="text-xs text-gray-400 mt-1">
                        آخر تعديل: {formatDateTime(item.updated_at)}
                      </p>
                    )}
                  </div>
                  <div className="flex gap-2">
                    {!item.is_default && (
                      <button
                        onClick={() => setResetTarget(item)}
                        className="text-xs text-gray-500 hover:text-red-600 hover:underline"
                        disabled={savingKey === item.key}
                      >
                        ↺ استرجاع الافتراضي
                      </button>
                    )}
                  </div>
                </div>

                <Label htmlFor={`txt-${item.key}`} className="sr-only">
                  نص الرسالة
                </Label>
                <Textarea
                  id={`txt-${item.key}`}
                  value={value}
                  onChange={(e) =>
                    setDrafts((prev) => ({ ...prev, [item.key]: e.target.value }))
                  }
                  rows={Math.min(Math.max(value.split("\n").length + 1, 4), 14)}
                  className="font-mono text-sm"
                  dir="auto"
                />
                <div className="flex items-center justify-between mt-3">
                  <span className="text-xs text-gray-400">{value.length} حرف</span>
                  <div className="flex gap-2">
                    {dirty && (
                      <Button
                        variant="outline"
                        size="sm"
                        onClick={() =>
                          setDrafts((prev) => {
                            const next = { ...prev };
                            delete next[item.key];
                            return next;
                          })
                        }
                        disabled={savingKey === item.key}
                      >
                        تراجع
                      </Button>
                    )}
                    <Button
                      size="sm"
                      onClick={() => save(item)}
                      disabled={!dirty || savingKey === item.key}
                    >
                      {savingKey === item.key ? "جاري الحفظ..." : "حفظ"}
                    </Button>
                  </div>
                </div>
              </Card>
            );
          })}
        </div>
      )}

      <ConfirmDialog
        open={resetTarget !== null}
        onOpenChange={(open) => { if (!open) setResetTarget(null); }}
        title="استرجاع النص الافتراضي؟"
        description={
          resetTarget
            ? `سيتم استبدال التعديلات الخاصة بـ "${resetTarget.key}" بالنص الافتراضي. لا يمكن التراجع.`
            : ""
        }
        confirmLabel="استرجاع"
        destructive
        onConfirm={doReset}
      />
    </div>
  );
}
