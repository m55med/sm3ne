"use client";
import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { RefreshButton } from "@/components/refresh-button";
import { ErrorBoundary } from "@/components/error-boundary";
import { SkeletonTable } from "@/components/skeleton-table";
import { EmptyState } from "@/components/empty-state";
import { useDebouncedValue } from "@/hooks/use-debounced-value";
import { formatNumber, formatDateTime } from "@/lib/format";
import type { RequestItem, PaginatedResponse } from "@/lib/types";

const REFRESH_INTERVAL_MS = 5000;
const PER_PAGE = 20;
const MAX_ERROR_MSG = 200;

const STATUS_META: Record<
  RequestItem["status"],
  { label: string; variant: "default" | "secondary" | "destructive"; pulse?: boolean }
> = {
  processing: { label: "جاري", variant: "secondary", pulse: true },
  completed: { label: "مكتمل", variant: "default" },
  failed: { label: "فشل", variant: "destructive" },
};

const PLAN_LABEL: Record<string, string> = {
  free: "مجاني",
  monthly: "شهري",
  annual: "سنوي",
};

const SOURCE_LABEL: Record<RequestItem["plan_source"], string> = {
  free: "—",
  coupon: "كوبون",
  purchase: "مدفوع",
};

// Origin of each transcription request. The set is closed on the backend
// (FartAPI rejects anything else with 422), and `telegram` is stamped
// server-side — so a client cannot forge its origin. We still surface it
// prominently so abuse patterns (e.g. a flood of `api` requests from one key)
// are visible at a glance.
const REQUEST_SOURCE_META: Record<
  RequestItem["source"],
  { label: string; icon: string; variant: "default" | "secondary" | "outline" | "destructive" }
> = {
  upload: { label: "التطبيق — رفع", icon: "📤", variant: "outline" },
  recording: { label: "التطبيق — تسجيل", icon: "🎙️", variant: "outline" },
  share: { label: "التطبيق — مشاركة", icon: "🔗", variant: "outline" },
  api: { label: "API", icon: "🔑", variant: "secondary" },
  telegram: { label: "تيليجرام", icon: "💬", variant: "default" },
  translation: { label: "ترجمة", icon: "🌐", variant: "secondary" },
};

const SOURCE_FILTERS: { value: string; label: string }[] = [
  { value: "", label: "كل المصادر" },
  { value: "upload", label: "التطبيق — رفع" },
  { value: "recording", label: "التطبيق — تسجيل" },
  { value: "share", label: "التطبيق — مشاركة" },
  { value: "api", label: "API" },
  { value: "telegram", label: "تيليجرام" },
  { value: "translation", label: "ترجمة" },
];

// `client_side` rows are the on-device STT path — no audio uploaded, no
// quota consumed, no per-request cost. Surfacing them as a first-class
// filter lets us track how much load the OS-level recognizer is absorbing.
const PROVIDER_FILTERS: { value: string; label: string }[] = [
  { value: "", label: "كل المُحركات" },
  { value: "client_side", label: "داخل الجهاز" },
  { value: "whisper", label: "Whisper" },
  { value: "gemini", label: "Gemini" },
  { value: "speechmatics", label: "Speechmatics" },
  { value: "groq", label: "Groq" },
  { value: "assemblyai", label: "AssemblyAI" },
];

// Pretty-prints the engine identifier shown in the table cell. We special-case
// `client_side` so the badge reads as an Arabic label instead of a slug, and
// so the eye picks out "free, on-device" volume at a glance.
const PROVIDER_DISPLAY: Record<string, { label: string; isClientSide: boolean }> = {
  client_side: { label: "داخل الجهاز", isClientSide: true },
};

const CLIENT_ENGINE_LABEL: Record<string, string> = {
  apple_speech: "Apple Speech",
  android_speech: "Android Speech",
};

function truncateError(msg: string | null | undefined): string | undefined {
  if (!msg) return undefined;
  // Trim and limit to MAX_ERROR_MSG chars. Strip newlines so tooltip stays tidy.
  const oneLine = msg.replace(/\s+/g, " ").trim();
  if (oneLine.length <= MAX_ERROR_MSG) return oneLine;
  return oneLine.slice(0, MAX_ERROR_MSG) + "…";
}

export default function RequestsPage() {
  const [requests, setRequests] = useState<RequestItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [langFilter, setLangFilter] = useState("");
  const [sourceFilter, setSourceFilter] = useState("");
  const [providerFilter, setProviderFilter] = useState("");
  const debouncedLang = useDebouncedValue(langFilter, 400);
  const [lastRefresh, setLastRefresh] = useState<Date | null>(null);
  const [autoRefreshEnabled, setAutoRefreshEnabled] = useState(true);
  const [isTyping, setIsTyping] = useState(false);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchRequests = useCallback(async () => {
    const params = new URLSearchParams({
      page: String(page),
      per_page: String(PER_PAGE),
    });
    if (debouncedLang) params.set("language", debouncedLang);
    if (sourceFilter) params.set("source", sourceFilter);
    if (providerFilter) params.set("provider_used", providerFilter);
    try {
      const r = await api<PaginatedResponse<RequestItem>>(
        `/admin/requests?${params}`
      );
      setRequests(r.requests || []);
      setTotal(r.total);
      setLastRefresh(new Date());
      setError(null);
    } catch (e) {
      setError(e instanceof Error ? e.message : "تعذّر تحميل الطلبات");
    } finally {
      setLoading(false);
    }
  }, [page, debouncedLang, sourceFilter, providerFilter]);

  // Mark typing when input value diverges from debounced value
  useEffect(() => {
    setIsTyping(langFilter !== debouncedLang);
  }, [langFilter, debouncedLang]);

  // Initial + dep-change load
  useEffect(() => {
    fetchRequests();
  }, [fetchRequests]);

  // Auto-refresh polling
  useEffect(() => {
    if (!autoRefreshEnabled) return;
    const id = setInterval(() => {
      if (isTyping) return;
      fetchRequests();
    }, REFRESH_INTERVAL_MS);
    return () => clearInterval(id);
  }, [autoRefreshEnabled, fetchRequests, isTyping]);

  const totalPages = Math.max(1, Math.ceil(total / PER_PAGE));
  const showPagination = total > PER_PAGE;

  return (
    <ErrorBoundary>
      <div>
        <div className="flex items-center justify-between mb-6">
          <h1 className="text-2xl font-bold text-gray-900">سجل الطلبات</h1>
          <RefreshButton onRefresh={fetchRequests} />
        </div>
        <Card className="p-6">
          <div className="flex items-center gap-4 mb-6 flex-wrap">
            <Input
              placeholder="فلتر حسب اللغة (ar, en...)"
              value={langFilter}
              onChange={(e) => {
                setLangFilter(e.target.value);
                setPage(1);
              }}
              className="max-w-xs"
              dir="ltr"
            />
            <select
              value={sourceFilter}
              onChange={(e) => {
                setSourceFilter(e.target.value);
                setPage(1);
              }}
              className="h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm"
              aria-label="فلتر حسب المصدر"
            >
              {SOURCE_FILTERS.map((s) => (
                <option key={s.value} value={s.value}>
                  {s.label}
                </option>
              ))}
            </select>
            <select
              value={providerFilter}
              onChange={(e) => {
                setProviderFilter(e.target.value);
                setPage(1);
              }}
              className="h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm"
              aria-label="فلتر حسب المُحرك"
            >
              {PROVIDER_FILTERS.map((p) => (
                <option key={p.value} value={p.value}>
                  {p.label}
                </option>
              ))}
            </select>
            <span className="text-sm text-gray-500">
              <span dir="ltr">{formatNumber(total)}</span> طلب
            </span>
            <label className="inline-flex items-center gap-2 text-xs text-gray-600 cursor-pointer select-none">
              <input
                type="checkbox"
                checked={autoRefreshEnabled}
                onChange={(e) => setAutoRefreshEnabled(e.target.checked)}
              />
              تحديث تلقائي كل <span dir="ltr">5</span>ث
            </label>
            {lastRefresh && (
              <span className="text-xs text-gray-400 ms-auto inline-flex items-center gap-1">
                <span
                  className={`inline-block h-2 w-2 rounded-full ${
                    autoRefreshEnabled
                      ? "bg-green-500 animate-pulse"
                      : "bg-gray-400"
                  }`}
                  aria-hidden="true"
                />
                آخر تحديث:{" "}
                <span dir="ltr">{lastRefresh.toLocaleTimeString("ar")}</span>
              </span>
            )}
          </div>

          {error && (
            <div className="mb-4 rounded-lg border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700">
              {error}
            </div>
          )}

          <div className="overflow-x-auto">
            {loading && requests.length === 0 ? (
              <SkeletonTable rows={8} cols={6} />
            ) : requests.length === 0 ? (
              <EmptyState
                title="لا توجد طلبات"
                description={
                  debouncedLang
                    ? "لا توجد نتائج مطابقة للفلتر الحالي."
                    : "لم يقم أي مستخدم بتقديم طلب حتى الآن."
                }
              />
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b text-gray-500">
                    <th className="text-right pb-3">#</th>
                    <th className="text-right pb-3">الحالة</th>
                    <th className="text-right pb-3">المصدر</th>
                    <th className="text-right pb-3">النموذج</th>
                    <th className="text-right pb-3">الزمن</th>
                    <th className="text-right pb-3 sticky end-0 bg-white z-10">
                      المستخدم
                    </th>
                    <th className="text-right pb-3">الباقة</th>
                    <th className="text-right pb-3">الملف</th>
                    <th className="text-right pb-3">المدة</th>
                    <th className="text-right pb-3">المعالج</th>
                    <th className="text-right pb-3">اللغة</th>
                    <th className="text-right pb-3">استخدام اليوم</th>
                    <th className="text-right pb-3">الكلمات</th>
                    <th className="text-right pb-3">مقصوص</th>
                    <th className="text-right pb-3">التاريخ</th>
                  </tr>
                </thead>
                <tbody>
                  {requests.map((r) => {
                    const statusMeta =
                      STATUS_META[r.status] || STATUS_META.completed;
                    const planLabel = PLAN_LABEL[r.plan_name] || r.plan_name;
                    const isPaid = r.plan_source !== "free";
                    const limitText =
                      r.daily_limit === -1 ? "∞" : String(r.daily_limit);
                    const overLimit =
                      r.daily_limit !== -1 && r.daily_used >= r.daily_limit;
                    const errorTooltip = truncateError(r.error_message);
                    return (
                      <tr key={r.id} className="border-b last:border-0">
                        <td className="py-3 text-gray-400" dir="ltr">
                          {r.id}
                        </td>
                        <td className="py-3">
                          <Badge
                            variant={statusMeta.variant}
                            className={statusMeta.pulse ? "animate-pulse" : ""}
                            title={errorTooltip}
                          >
                            {statusMeta.label}
                          </Badge>
                        </td>
                        <td className="py-3">
                          {(() => {
                            const sm =
                              REQUEST_SOURCE_META[r.source] ||
                              REQUEST_SOURCE_META.upload;
                            return (
                              <div className="flex flex-col gap-1 items-start">
                                <Badge variant={sm.variant} title={`source=${r.source}`}>
                                  {sm.icon} {sm.label}
                                </Badge>
                                {r.source === "api" && r.api_key_name && (
                                  <span
                                    className="text-[10px] text-gray-400 font-mono"
                                    dir="ltr"
                                  >
                                    {r.api_key_name}
                                  </span>
                                )}
                              </div>
                            );
                          })()}
                        </td>
                        {/* النموذج المستخدم: المزوّد + الموديل الفعلي.
                             `client_side` يبقى أخضر مميز لأنه مجاني وما بيستهلكش
                             quota — مهم نقدر نشوف نسبته بنظرة واحدة. */}
                        <td className="py-3">
                          {r.provider_used ? (
                            <div className="flex flex-col gap-0.5 items-start">
                              {(() => {
                                const display = PROVIDER_DISPLAY[r.provider_used];
                                if (display?.isClientSide) {
                                  return (
                                    <Badge
                                      variant="outline"
                                      className="text-[10px] border-emerald-500 bg-emerald-50 text-emerald-700 dark:bg-emerald-950/40 dark:text-emerald-300"
                                    >
                                      <span className="me-1">📱</span>
                                      {display.label}
                                    </Badge>
                                  );
                                }
                                return (
                                  <Badge variant="secondary" className="text-[10px]">
                                    <span dir="ltr">{r.provider_used}</span>
                                  </Badge>
                                );
                              })()}
                              {r.model_used && (
                                <span
                                  className="text-[10px] text-gray-400 font-mono"
                                  dir="ltr"
                                  title={r.model_used}
                                >
                                  {CLIENT_ENGINE_LABEL[r.model_used] ?? r.model_used}
                                </span>
                              )}
                            </div>
                          ) : (
                            <span className="text-gray-300">—</span>
                          )}
                        </td>
                        {/* الزمن المستغرق (request → response) */}
                        <td className="py-3" dir="ltr">
                          {r.latency_ms != null ? (
                            <span
                              className={
                                r.latency_ms > 15000
                                  ? "text-red-600 font-medium"
                                  : r.latency_ms > 6000
                                    ? "text-amber-600"
                                    : "text-gray-700"
                              }
                            >
                              {r.latency_ms < 1000
                                ? `${r.latency_ms}ms`
                                : `${(r.latency_ms / 1000).toFixed(1)}s`}
                            </span>
                          ) : (
                            <span className="text-gray-300">—</span>
                          )}
                        </td>
                        <td className="py-3 font-medium sticky end-0 bg-white z-10">
                          {r.user_public_id ? (
                            <Link
                              href={`/users/${r.user_public_id}`}
                              className="hover:underline text-blue-700"
                            >
                              {r.full_name || r.email || "—"}
                            </Link>
                          ) : (
                            r.full_name || r.email || "—"
                          )}
                        </td>
                        <td className="py-3">
                          <div className="flex flex-col gap-1 items-start">
                            <Badge variant={isPaid ? "default" : "outline"}>
                              {planLabel}
                            </Badge>
                            {isPaid && (
                              <Badge
                                variant="secondary"
                                className="text-[10px]"
                              >
                                {SOURCE_LABEL[r.plan_source]}
                              </Badge>
                            )}
                          </div>
                        </td>
                        <td className="py-3 text-gray-500 max-w-[120px] truncate">
                          {r.filename || "—"}
                        </td>
                        <td className="py-3">
                          <span dir="ltr">{r.duration_seconds.toFixed(1)}</span>ث
                        </td>
                        <td className="py-3">
                          <span dir="ltr">
                            {r.processed_seconds.toFixed(1)}
                          </span>
                          ث
                        </td>
                        <td className="py-3">
                          <Badge variant="secondary">
                            <span dir="ltr">{r.language || "—"}</span>
                          </Badge>
                        </td>
                        <td
                          className={`py-3 font-medium ${
                            overLimit ? "text-red-600" : "text-gray-700"
                          }`}
                          dir="ltr"
                        >
                          {r.daily_used} / {limitText}
                        </td>
                        <td className="py-3" dir="ltr">
                          {formatNumber(r.word_count)}
                        </td>
                        <td className="py-3">
                          {r.was_trimmed ? (
                            <Badge variant="destructive">نعم</Badge>
                          ) : (
                            "—"
                          )}
                        </td>
                        <td className="py-3 text-gray-500 text-xs">
                          {formatDateTime(r.created_at)}
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </table>
            )}
          </div>

          {showPagination && (
            <div className="flex items-center justify-between mt-4">
              <Button
                variant="outline"
                size="sm"
                disabled={page === 1}
                onClick={() => setPage(page - 1)}
              >
                السابق
              </Button>
              <span className="text-sm text-gray-500">
                صفحة <span dir="ltr">{page}</span> من{" "}
                <span dir="ltr">{totalPages}</span>
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
      </div>
    </ErrorBoundary>
  );
}
