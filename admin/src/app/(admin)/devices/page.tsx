"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { Label } from "@/components/ui/label";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from "@/components/ui/dialog";
import { RefreshButton } from "@/components/refresh-button";
import { ConfirmDialog } from "@/components/confirm-dialog";
import { toast } from "@/components/toast";
import { useDebouncedValue } from "@/hooks/use-debounced-value";
import { formatDateTime, formatNumber } from "@/lib/format";
import type {
  DeviceItem,
  DeviceListResponse,
  NotificationSendRequest,
  NotificationSendResponse,
  NotificationTarget,
} from "@/lib/types";

const PER_PAGE = 50;

export default function DevicesPage() {
  const [items, setItems] = useState<DeviceItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [platform, setPlatform] = useState<"" | "android" | "ios">("");
  const [pushOnly, setPushOnly] = useState<"" | "yes" | "no">("");
  const [search, setSearch] = useState("");
  const debouncedSearch = useDebouncedValue(search, 300);
  const [loading, setLoading] = useState(true);
  const [selected, setSelected] = useState<Set<string>>(new Set());

  // Notification composer
  const [composerOpen, setComposerOpen] = useState(false);
  const [confirmSend, setConfirmSend] = useState(false);
  const [target, setTarget] = useState<NotificationTarget>("all");
  const [title, setTitle] = useState("");
  const [body, setBody] = useState("");
  const [deepLink, setDeepLink] = useState("");
  const [sending, setSending] = useState(false);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams({
        page: String(page),
        per_page: String(PER_PAGE),
      });
      if (platform) params.set("platform", platform);
      if (pushOnly) params.set("push_enabled", pushOnly === "yes" ? "true" : "false");
      if (debouncedSearch) params.set("search", debouncedSearch);
      const data = await api<DeviceListResponse>(`/admin/devices?${params}`);
      setItems(data.devices);
      setTotal(data.total);
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "تعذّر تحميل الأجهزة");
    } finally {
      setLoading(false);
    }
  }, [page, platform, pushOnly, debouncedSearch]);

  useEffect(() => {
    load();
  }, [load]);

  function toggleSelect(id: string) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function openComposer(initialTarget: NotificationTarget = "all") {
    setTarget(initialTarget);
    setTitle("");
    setBody("");
    setDeepLink("");
    setComposerOpen(true);
  }

  const audienceCount = useMemo(() => {
    if (target === "all") return null;
    if (target === "devices") return selected.size;
    if (target === "hearing_impaired") return null;
    return null;
  }, [target, selected]);

  async function performSend() {
    setSending(true);
    try {
      const payload: NotificationSendRequest = {
        target,
        title: title.trim(),
        body: body.trim(),
        ...(deepLink.trim() ? { deep_link: deepLink.trim() } : {}),
      };
      if (target === "devices") {
        payload.device_public_ids = Array.from(selected);
      }
      const res = await api<NotificationSendResponse>(
        "/admin/notifications/send",
        { method: "POST", body: JSON.stringify(payload) },
      );
      toast.success(
        `تم الإرسال — نجح ${formatNumber(res.sent)} / فشل ${formatNumber(res.failed)}`,
      );
      setComposerOpen(false);
      setConfirmSend(false);
      if (target === "devices") setSelected(new Set());
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "تعذّر الإرسال");
    } finally {
      setSending(false);
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE) || 1;

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">الأجهزة والإشعارات</h1>
        <div className="flex gap-2">
          <Button onClick={() => openComposer("all")} className="bg-blue-600">
            📣 إرسال للكل
          </Button>
          <Button
            variant="outline"
            onClick={() => openComposer("hearing_impaired")}
          >
            🦻 إرسال لـ ضعاف السمع
          </Button>
          {selected.size > 0 && (
            <Button variant="outline" onClick={() => openComposer("devices")}>
              إرسال للمحدد ({formatNumber(selected.size)})
            </Button>
          )}
          <RefreshButton onRefresh={load} />
        </div>
      </div>

      <Card className="p-6">
        <div className="flex flex-wrap items-center gap-4 mb-6">
          <Input
            placeholder="بحث (إيميل، اسم، موديل…)"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="max-w-sm"
          />
          <select
            value={platform}
            onChange={(e) => {
              setPlatform(e.target.value as typeof platform);
              setPage(1);
            }}
            className="h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm"
          >
            <option value="">كل الأنظمة</option>
            <option value="android">Android</option>
            <option value="ios">iOS</option>
          </select>
          <select
            value={pushOnly}
            onChange={(e) => {
              setPushOnly(e.target.value as typeof pushOnly);
              setPage(1);
            }}
            className="h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm"
          >
            <option value="">الإشعارات (الكل)</option>
            <option value="yes">مفعّلة فقط</option>
            <option value="no">معطّلة فقط</option>
          </select>
          <span className="text-sm text-gray-500 ms-auto">
            {formatNumber(total)} جهاز
          </span>
        </div>

        {loading && items.length === 0 ? (
          <div className="py-16 text-center text-gray-400">جاري التحميل…</div>
        ) : items.length === 0 ? (
          <div className="py-16 text-center">
            <div className="text-5xl mb-3">📱</div>
            <p className="text-gray-500">لا توجد أجهزة مسجّلة بعد</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-gray-500">
                  <th className="text-right pb-3 w-8">
                    <input
                      type="checkbox"
                      checked={selected.size === items.length && items.length > 0}
                      onChange={(e) =>
                        setSelected(
                          e.target.checked
                            ? new Set(items.map((d) => d.public_id))
                            : new Set(),
                        )
                      }
                      aria-label="تحديد الكل"
                    />
                  </th>
                  <th className="text-right pb-3">المستخدم</th>
                  <th className="text-right pb-3">الجهاز</th>
                  <th className="text-right pb-3">النظام</th>
                  <th className="text-right pb-3">الإصدار</th>
                  <th className="text-right pb-3">الإشعارات</th>
                  <th className="text-right pb-3">آخر ظهور</th>
                </tr>
              </thead>
              <tbody>
                {items.map((d) => (
                  <tr key={d.public_id} className="border-b last:border-0 hover:bg-gray-50">
                    <td className="py-3">
                      <input
                        type="checkbox"
                        checked={selected.has(d.public_id)}
                        onChange={() => toggleSelect(d.public_id)}
                        aria-label={`اختيار جهاز ${d.public_id}`}
                      />
                    </td>
                    <td className="py-3 font-medium">
                      <Link href={`/users/${d.user_id}`} className="hover:underline">
                        {d.user_full_name || d.user_email || `#${d.user_id}`}
                      </Link>
                      {d.user_email && d.user_full_name && (
                        <div className="text-xs text-gray-400">{d.user_email}</div>
                      )}
                    </td>
                    <td className="py-3">
                      <div className="font-medium">
                        {d.device_marketing_name || d.device_model || "—"}
                      </div>
                      {d.device_model && d.device_marketing_name && (
                        <div className="text-xs text-gray-400" dir="ltr">
                          {d.device_model}
                        </div>
                      )}
                    </td>
                    <td className="py-3">
                      <Badge variant={d.platform === "ios" ? "default" : "secondary"}>
                        {d.platform === "ios" ? " iOS" : "Android"}
                      </Badge>
                      {d.device_os_version && (
                        <span className="ms-2 text-xs text-gray-500" dir="ltr">
                          {d.device_os_version}
                        </span>
                      )}
                    </td>
                    <td className="py-3 text-gray-500 text-xs" dir="ltr">
                      {d.app_version || "—"}
                    </td>
                    <td className="py-3">
                      {d.push_enabled ? (
                        <Badge className="bg-green-100 text-green-700">مفعّلة</Badge>
                      ) : (
                        <Badge variant="outline" className="text-gray-500">معطّلة</Badge>
                      )}
                    </td>
                    <td className="py-3 text-gray-500 text-xs">
                      {d.last_seen_at ? formatDateTime(d.last_seen_at) : "—"}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}

        {total > PER_PAGE && (
          <div className="flex items-center justify-between mt-4">
            <Button variant="outline" size="sm" disabled={page === 1} onClick={() => setPage(page - 1)}>
              السابق
            </Button>
            <span className="text-sm text-gray-500">
              صفحة {formatNumber(page)} من {formatNumber(totalPages)}
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

      <Dialog open={composerOpen} onOpenChange={setComposerOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>إرسال إشعار push</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div>
              <Label className="text-sm">الجمهور</Label>
              <div className="mt-2 grid grid-cols-3 gap-2 text-sm">
                <button
                  type="button"
                  onClick={() => setTarget("all")}
                  className={`rounded-lg border-2 p-3 ${target === "all" ? "border-blue-600 bg-blue-50" : "border-gray-200"}`}
                >
                  🌍 الجميع
                </button>
                <button
                  type="button"
                  onClick={() => setTarget("hearing_impaired")}
                  className={`rounded-lg border-2 p-3 ${target === "hearing_impaired" ? "border-blue-600 bg-blue-50" : "border-gray-200"}`}
                >
                  🦻 ضعاف السمع
                </button>
                <button
                  type="button"
                  onClick={() => setTarget("devices")}
                  disabled={selected.size === 0}
                  className={`rounded-lg border-2 p-3 disabled:opacity-50 ${target === "devices" ? "border-blue-600 bg-blue-50" : "border-gray-200"}`}
                >
                  ✅ المحدد ({formatNumber(selected.size)})
                </button>
              </div>
            </div>
            <div>
              <Label htmlFor="notif-title">العنوان</Label>
              <Input
                id="notif-title"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                maxLength={120}
                placeholder="ميزة جديدة ✨"
              />
            </div>
            <div>
              <Label htmlFor="notif-body">النص</Label>
              <Textarea
                id="notif-body"
                value={body}
                onChange={(e) => setBody(e.target.value)}
                maxLength={1000}
                rows={3}
                placeholder="جرّب الميزة الجديدة في تطبيق بصوتك..."
              />
            </div>
            <div>
              <Label htmlFor="notif-link">رابط داخلي (اختياري)</Label>
              <Input
                id="notif-link"
                value={deepLink}
                onChange={(e) => setDeepLink(e.target.value)}
                placeholder="/plans"
                dir="ltr"
              />
              <p className="text-xs text-gray-400 mt-1">
                مثال: <code>/plans</code> لفتح صفحة الباقات لما المستخدم يضغط على الإشعار.
              </p>
            </div>
            {audienceCount !== null && (
              <p className="text-xs text-gray-500">
                سيُرسَل لـ {formatNumber(audienceCount)} جهاز محدّد.
              </p>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setComposerOpen(false)}>
              إلغاء
            </Button>
            <Button
              onClick={() => setConfirmSend(true)}
              disabled={
                !title.trim() ||
                !body.trim() ||
                (target === "devices" && selected.size === 0)
              }
            >
              متابعة
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      <ConfirmDialog
        open={confirmSend}
        onOpenChange={setConfirmSend}
        title="تأكيد الإرسال"
        description={`سيتم إرسال الإشعار لـ "${title}" — هل تأكد المتابعة؟`}
        confirmLabel={sending ? "جاري الإرسال…" : "إرسال"}
        onConfirm={performSend}
      />
    </div>
  );
}
