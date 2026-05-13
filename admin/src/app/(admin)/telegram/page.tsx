"use client";
import { useCallback, useEffect, useMemo, useState } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
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
import { ConfirmDialog } from "@/components/confirm-dialog";
import { toast } from "@/components/toast";
import { useDebouncedValue } from "@/hooks/use-debounced-value";
import { formatDateTime, formatNumber } from "@/lib/format";
import type {
  TelegramAudience,
  TelegramUserItem,
  TelegramUserListResponse,
  TelegramWebhookInfo,
} from "@/lib/types";

const PER_PAGE = 20;
type FilterState = "all" | "linked" | "unlinked" | "blocked";
const FILTERS: { key: FilterState; label: string }[] = [
  { key: "all", label: "الكل" },
  { key: "linked", label: "مربوطون" },
  { key: "unlinked", label: "غير مربوطين" },
  { key: "blocked", label: "حاظرون البوت" },
];

const AUDIENCE_LABEL: Record<TelegramAudience, string> = {
  all: "كل المستخدمين (مع استثناء الحاظرين)",
  linked_only: "المربوطون فقط",
  unlinked_only: "غير المربوطين فقط",
  selected: "المحددون من القائمة",
};

function displayName(t: TelegramUserItem): string {
  const first = (t.first_name || "").trim();
  const last = (t.last_name || "").trim();
  const full = [first, last].filter(Boolean).join(" ").trim();
  if (full) return full;
  if (t.username) return `@${t.username}`;
  return `#${t.telegram_id}`;
}

function Avatar({ user }: { user: TelegramUserItem }) {
  if (user.photo_url) {
    // eslint-disable-next-line @next/next/no-img-element
    return (
      <img
        src={user.photo_url}
        alt={displayName(user)}
        className="h-9 w-9 rounded-full object-cover"
      />
    );
  }
  const initials = displayName(user).slice(0, 1).toUpperCase();
  return (
    <div className="h-9 w-9 rounded-full bg-blue-100 text-blue-700 flex items-center justify-center text-sm font-semibold">
      {initials}
    </div>
  );
}

export default function TelegramUsersPage() {
  const [items, setItems] = useState<TelegramUserItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const debouncedSearch = useDebouncedValue(search, 300);
  const [filterState, setFilterState] = useState<FilterState>("all");
  const [loading, setLoading] = useState(false);
  const [selected, setSelected] = useState<Set<number>>(new Set());

  // Webhook diagnostics card.
  const [webhook, setWebhook] = useState<TelegramWebhookInfo | null>(null);

  // Single-message dialog.
  const [sendTarget, setSendTarget] = useState<TelegramUserItem | null>(null);
  const [sendText, setSendText] = useState("");
  const [sendBusy, setSendBusy] = useState(false);

  // Broadcast dialog.
  const [broadcastOpen, setBroadcastOpen] = useState(false);
  const [broadcastText, setBroadcastText] = useState("");
  const [broadcastAudience, setBroadcastAudience] = useState<TelegramAudience>("all");
  const [broadcastBusy, setBroadcastBusy] = useState(false);

  // Delete confirm.
  const [deleteTarget, setDeleteTarget] = useState<TelegramUserItem | null>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      const params = new URLSearchParams({
        page: String(page),
        per_page: String(PER_PAGE),
        filter_state: filterState,
      });
      if (debouncedSearch) params.set("search", debouncedSearch);
      const r = await api<TelegramUserListResponse>(`/admin/telegram/users?${params}`);
      setItems(r.items || []);
      setTotal(r.total);
      // Drop selections that fell off the page.
      setSelected((prev) => new Set([...prev].filter((id) => (r.items || []).some((u) => u.id === id))));
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "تعذّر تحميل القائمة");
    } finally {
      setLoading(false);
    }
  }, [page, debouncedSearch, filterState]);

  const loadWebhook = useCallback(async () => {
    try {
      const w = await api<TelegramWebhookInfo>("/admin/telegram/webhook");
      setWebhook(w);
    } catch {
      // Non-fatal — the API returns 503 when telegram is unconfigured.
      setWebhook({
        configured: false,
        url: null,
        pending_update_count: null,
        last_error_date: null,
        last_error_message: null,
        bot_username: null,
      });
    }
  }, []);

  useEffect(() => { setPage(1); }, [debouncedSearch, filterState]);
  useEffect(() => { void load(); }, [load]);
  useEffect(() => { void loadWebhook(); }, [loadWebhook]);

  const totalPages = Math.ceil(total / PER_PAGE) || 1;
  const showPagination = total > PER_PAGE;

  const visibleIds = useMemo(() => items.map((i) => i.id), [items]);
  const allSelectedOnPage = visibleIds.length > 0 && visibleIds.every((id) => selected.has(id));

  function toggleSelectAll() {
    setSelected((prev) => {
      const next = new Set(prev);
      if (allSelectedOnPage) {
        for (const id of visibleIds) next.delete(id);
      } else {
        for (const id of visibleIds) next.add(id);
      }
      return next;
    });
  }

  function toggleSelectOne(id: number) {
    setSelected((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  async function doSendSingle() {
    if (!sendTarget || !sendText.trim()) return;
    setSendBusy(true);
    try {
      const r = await api<{ sent: boolean; error: string | null }>(
        `/admin/telegram/users/${sendTarget.id}/message`,
        { method: "POST", body: JSON.stringify({ text: sendText }) },
      );
      if (r.sent) {
        toast.success(`تم إرسال الرسالة إلى ${displayName(sendTarget)}`);
        setSendTarget(null);
        setSendText("");
      } else {
        toast.error(r.error || "تعذّر الإرسال");
      }
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "تعذّر الإرسال");
    } finally {
      setSendBusy(false);
    }
  }

  async function doBroadcast() {
    if (!broadcastText.trim()) return;
    setBroadcastBusy(true);
    try {
      const body = {
        text: broadcastText,
        audience: broadcastAudience,
        telegram_user_ids: broadcastAudience === "selected" ? Array.from(selected) : [],
      };
      const r = await api<{ queued: number }>("/admin/telegram/broadcast", {
        method: "POST",
        body: JSON.stringify(body),
      });
      toast.success(`بدأ الإرسال إلى ${formatNumber(r.queued)} مستخدم. الإرسال يتم في الخلفية.`);
      setBroadcastOpen(false);
      setBroadcastText("");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "تعذّر بدء الإرسال");
    } finally {
      setBroadcastBusy(false);
    }
  }

  async function doDelete() {
    if (!deleteTarget) return;
    try {
      await api(`/admin/telegram/users/${deleteTarget.id}`, { method: "DELETE" });
      toast.success(`تم حذف ${displayName(deleteTarget)}`);
      setDeleteTarget(null);
      await load();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "فشل الحذف");
    }
  }

  async function refreshUser(t: TelegramUserItem) {
    try {
      const r = await api<TelegramUserItem>(
        `/admin/telegram/users/${t.id}/refresh`,
        { method: "POST" },
      );
      setItems((prev) => prev.map((u) => (u.id === r.id ? r : u)));
      toast.success("تم تحديث البيانات");
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "تعذّر التحديث");
    }
  }

  async function registerWebhook() {
    try {
      await api("/admin/telegram/webhook/register", {
        method: "POST",
        body: JSON.stringify({}),
      });
      toast.success("تم تسجيل الـ webhook");
      await loadWebhook();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "فشل تسجيل الـ webhook");
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">تيليجرام</h1>
          <p className="text-sm text-gray-500 mt-1">
            كل من تفاعل مع البوت — مربوط، غير مربوط، أو حاظر.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Link href="/telegram/messages">
            <Button variant="outline" size="sm">📝 رسائل البوت</Button>
          </Link>
          <Button
            variant="default"
            size="sm"
            onClick={() => {
              if (selected.size > 0) setBroadcastAudience("selected");
              else setBroadcastAudience("all");
              setBroadcastOpen(true);
            }}
          >
            📣 إرسال جماعي
          </Button>
          <RefreshButton onRefresh={async () => { await load(); await loadWebhook(); }} />
        </div>
      </div>

      <WebhookStatusCard info={webhook} onRegister={registerWebhook} />

      <Card className="p-6">
        <div className="flex flex-wrap items-center gap-3 mb-4">
          <Input
            placeholder="بحث بالاسم أو @username أو telegram_id..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="max-w-sm"
          />
          <span className="text-sm text-gray-500">{formatNumber(total)} مستخدم</span>
          <div className="flex-1" />
          <div className="flex gap-1 bg-gray-100 p-1 rounded-lg">
            {FILTERS.map((f) => (
              <button
                key={f.key}
                onClick={() => setFilterState(f.key)}
                className={`px-3 py-1.5 text-xs rounded transition ${
                  filterState === f.key
                    ? "bg-white text-gray-900 shadow-sm font-semibold"
                    : "text-gray-600 hover:text-gray-900"
                }`}
              >
                {f.label}
              </button>
            ))}
          </div>
        </div>

        {selected.size > 0 && (
          <div className="mb-3 px-4 py-2 rounded bg-blue-50 text-blue-800 text-sm flex items-center justify-between">
            <span>محدد: {formatNumber(selected.size)}</span>
            <div className="flex gap-2">
              <button
                onClick={() => setSelected(new Set())}
                className="text-blue-700 hover:underline text-xs"
              >
                إلغاء التحديد
              </button>
              <button
                onClick={() => {
                  setBroadcastAudience("selected");
                  setBroadcastOpen(true);
                }}
                className="font-semibold text-blue-700 hover:underline text-xs"
              >
                إرسال للمحدد
              </button>
            </div>
          </div>
        )}

        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-gray-500">
                <th className="text-right pb-3 w-8">
                  <input
                    type="checkbox"
                    checked={allSelectedOnPage}
                    onChange={toggleSelectAll}
                    className="cursor-pointer"
                    aria-label="تحديد الكل في الصفحة"
                  />
                </th>
                <th className="text-right pb-3">المستخدم</th>
                <th className="text-right pb-3">المعرف</th>
                <th className="text-right pb-3">الحالة</th>
                <th className="text-right pb-3">حساب التطبيق</th>
                <th className="text-right pb-3">آخر تفاعل</th>
                <th className="text-right pb-3">إجراءات</th>
              </tr>
            </thead>
            <tbody>
              {items.map((t) => (
                <tr key={t.id} className="border-b last:border-0 hover:bg-gray-50">
                  <td className="py-3">
                    <input
                      type="checkbox"
                      checked={selected.has(t.id)}
                      onChange={() => toggleSelectOne(t.id)}
                      className="cursor-pointer"
                      aria-label="تحديد"
                    />
                  </td>
                  <td className="py-3">
                    <div className="flex items-center gap-3">
                      <Avatar user={t} />
                      <div>
                        <div className="font-medium">{displayName(t)}</div>
                        {t.username && (
                          <div className="text-xs text-gray-500" dir="ltr">@{t.username}</div>
                        )}
                        {t.bio && (
                          <div className="text-xs text-gray-400 max-w-md truncate">{t.bio}</div>
                        )}
                      </div>
                    </div>
                  </td>
                  <td className="py-3 text-xs text-gray-500" dir="ltr">{t.telegram_id}</td>
                  <td className="py-3">
                    {t.is_blocked ? (
                      <Badge variant="destructive">حاظر البوت</Badge>
                    ) : t.linked_user_id ? (
                      <Badge variant="default">مربوط</Badge>
                    ) : (
                      <Badge variant="secondary">غير مربوط</Badge>
                    )}
                  </td>
                  <td className="py-3">
                    {t.linked_user_id ? (
                      <Link
                        href={`/users/${t.linked_user_public_id || t.linked_user_id}`}
                        className="text-blue-600 hover:underline text-xs"
                      >
                        {t.linked_user_username || `#${t.linked_user_id}`}
                      </Link>
                    ) : (
                      <span className="text-gray-400 text-xs">—</span>
                    )}
                  </td>
                  <td className="py-3 text-xs text-gray-500">
                    {t.last_interaction_at ? formatDateTime(t.last_interaction_at) : "—"}
                  </td>
                  <td className="py-3">
                    <div className="flex gap-3 text-xs">
                      <button
                        onClick={() => setSendTarget(t)}
                        disabled={t.is_blocked}
                        className="text-blue-600 hover:underline disabled:text-gray-300 disabled:cursor-not-allowed"
                      >
                        رسالة
                      </button>
                      <button
                        onClick={() => refreshUser(t)}
                        className="text-gray-500 hover:underline"
                      >
                        تحديث
                      </button>
                      {!t.linked_user_id && (
                        <button
                          onClick={() => setDeleteTarget(t)}
                          className="text-red-600 hover:underline"
                        >
                          حذف
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
              {items.length === 0 && !loading && (
                <tr>
                  <td colSpan={7} className="py-12 text-center text-gray-400">
                    لا توجد نتائج
                  </td>
                </tr>
              )}
              {loading && items.length === 0 && (
                <tr>
                  <td colSpan={7} className="py-12 text-center text-gray-400">
                    جاري التحميل...
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>

        {showPagination && (
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

      {/* --- Single message dialog --- */}
      <Dialog
        open={sendTarget !== null}
        onOpenChange={(open) => {
          if (!open) {
            setSendTarget(null);
            setSendText("");
          }
        }}
      >
        <DialogContent>
          <DialogHeader>
            <DialogTitle>إرسال رسالة</DialogTitle>
            <DialogDescription>
              إلى {sendTarget ? displayName(sendTarget) : ""} عبر البوت.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-2">
            <Label htmlFor="send-text">نص الرسالة</Label>
            <Textarea
              id="send-text"
              value={sendText}
              onChange={(e) => setSendText(e.target.value)}
              placeholder="اكتب الرسالة هنا... (Markdown مدعوم)"
              rows={6}
              maxLength={4096}
            />
            <div className="text-xs text-gray-400 text-end">{sendText.length} / 4096</div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setSendTarget(null)} disabled={sendBusy}>
              إلغاء
            </Button>
            <Button onClick={doSendSingle} disabled={sendBusy || !sendText.trim()}>
              {sendBusy ? "جاري الإرسال..." : "إرسال"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* --- Broadcast dialog --- */}
      <Dialog open={broadcastOpen} onOpenChange={setBroadcastOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>إرسال جماعي</DialogTitle>
            <DialogDescription>
              الرسالة تُرسل في الخلفية مع احترام حد تيليجرام للسرعة.
            </DialogDescription>
          </DialogHeader>
          <div className="space-y-3">
            <div>
              <Label>الجمهور</Label>
              <div className="grid grid-cols-1 gap-2 mt-2">
                {(["all", "linked_only", "unlinked_only", "selected"] as TelegramAudience[]).map((a) => {
                  const disabled = a === "selected" && selected.size === 0;
                  return (
                    <label
                      key={a}
                      className={`flex items-center gap-2 text-sm rounded border px-3 py-2 cursor-pointer ${
                        disabled
                          ? "bg-gray-50 text-gray-400 cursor-not-allowed"
                          : broadcastAudience === a
                            ? "border-blue-500 bg-blue-50"
                            : "hover:bg-gray-50"
                      }`}
                    >
                      <input
                        type="radio"
                        name="audience"
                        checked={broadcastAudience === a}
                        onChange={() => setBroadcastAudience(a)}
                        disabled={disabled}
                      />
                      <span>{AUDIENCE_LABEL[a]}</span>
                      {a === "selected" && selected.size > 0 && (
                        <span className="ms-auto text-xs text-blue-700">
                          ({formatNumber(selected.size)})
                        </span>
                      )}
                    </label>
                  );
                })}
              </div>
            </div>
            <div>
              <Label htmlFor="broadcast-text">نص الرسالة</Label>
              <Textarea
                id="broadcast-text"
                value={broadcastText}
                onChange={(e) => setBroadcastText(e.target.value)}
                placeholder="اكتب الرسالة هنا... (Markdown مدعوم)"
                rows={6}
                maxLength={4096}
              />
              <div className="text-xs text-gray-400 text-end mt-1">
                {broadcastText.length} / 4096
              </div>
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setBroadcastOpen(false)} disabled={broadcastBusy}>
              إلغاء
            </Button>
            <Button onClick={doBroadcast} disabled={broadcastBusy || !broadcastText.trim()}>
              {broadcastBusy ? "جاري الإرسال..." : "بدء الإرسال"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* --- Delete confirm --- */}
      <ConfirmDialog
        open={deleteTarget !== null}
        onOpenChange={(open) => { if (!open) setDeleteTarget(null); }}
        title="حذف هذا الحساب؟"
        description={
          deleteTarget
            ? `سيتم حذف ${displayName(deleteTarget)} من قاعدة البيانات. لو راسلنا مرة أخرى سيتم إنشاء سجل جديد.`
            : ""
        }
        confirmLabel="حذف"
        destructive
        onConfirm={doDelete}
      />
    </div>
  );
}

function WebhookStatusCard({
  info,
  onRegister,
}: {
  info: TelegramWebhookInfo | null;
  onRegister: () => void | Promise<void>;
}) {
  if (!info) return null;

  const ok = info.configured;
  const hasError = !!info.last_error_message;
  return (
    <Card className="p-4 mb-6">
      <div className="flex items-center justify-between flex-wrap gap-3">
        <div className="flex items-center gap-3">
          <span
            className={`inline-flex h-2 w-2 rounded-full ${
              ok ? (hasError ? "bg-yellow-500" : "bg-green-500") : "bg-red-500"
            }`}
          />
          <div>
            <div className="text-sm font-semibold">
              حالة الـ Webhook: {ok ? (hasError ? "نشط مع تحذيرات" : "نشط") : "غير مسجّل"}
            </div>
            {info.bot_username && (
              <div className="text-xs text-gray-500" dir="ltr">@{info.bot_username}</div>
            )}
            {info.url && (
              <div className="text-xs text-gray-400 mt-1" dir="ltr">{info.url}</div>
            )}
            {hasError && (
              <div className="text-xs text-yellow-700 mt-1">
                آخر خطأ: {info.last_error_message}
                {info.last_error_date && ` — ${formatDateTime(info.last_error_date)}`}
              </div>
            )}
            {info.pending_update_count !== null && info.pending_update_count > 0 && (
              <div className="text-xs text-gray-500 mt-1">
                تحديثات معلّقة: {formatNumber(info.pending_update_count)}
              </div>
            )}
          </div>
        </div>
        <Button variant="outline" size="sm" onClick={() => void onRegister()}>
          {ok ? "إعادة تسجيل" : "تسجيل الـ Webhook"}
        </Button>
      </div>
    </Card>
  );
}
