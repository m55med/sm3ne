"use client";
import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { getCurrentAdminId } from "@/lib/auth";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
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
import { PLAN_LABEL, SURVEY_REASON_ICON, SURVEY_REASON_LABEL } from "@/lib/labels";
import { formatDate, formatNumber } from "@/lib/format";
import type { UserListItem, PaginatedResponse } from "@/lib/types";

/// Pulls the `reasons` array out of the survey_response JSON without trusting
/// it — returns an empty array on any parse / shape failure so the render
/// path can't crash on bad data.
function surveyReasons(raw: string | null): string[] {
  if (!raw) return [];
  try {
    const parsed = JSON.parse(raw) as { reasons?: unknown };
    if (!Array.isArray(parsed.reasons)) return [];
    return parsed.reasons.filter((x): x is string => typeof x === "string");
  } catch {
    return [];
  }
}

const PER_PAGE = 20;

interface CreateForm {
  email: string;
  password: string;
  full_name: string;
  role: "user" | "admin";
  is_active: boolean;
}

const EMPTY_CREATE_FORM: CreateForm = {
  email: "",
  password: "",
  full_name: "",
  role: "user",
  is_active: true,
};

export default function UsersPage() {
  const [users, setUsers] = useState<UserListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const debouncedSearch = useDebouncedValue(search, 300);
  const currentAdminId = getCurrentAdminId();

  const [confirmTarget, setConfirmTarget] = useState<UserListItem | null>(null);
  const [mutatingId, setMutatingId] = useState<number | null>(null);

  // إنشاء مستخدم جديد
  const [createOpen, setCreateOpen] = useState(false);
  const [createForm, setCreateForm] = useState<CreateForm>(EMPTY_CREATE_FORM);
  const [createError, setCreateError] = useState<string | null>(null);
  const [creating, setCreating] = useState(false);

  const load = useCallback(async () => {
    const params = new URLSearchParams({ page: String(page), per_page: String(PER_PAGE) });
    if (debouncedSearch) params.set("search", debouncedSearch);
    const r = await api<PaginatedResponse<UserListItem>>(`/admin/users?${params}`);
    setUsers(r.users || []);
    setTotal(r.total);
  }, [page, debouncedSearch]);

  // إعادة الصفحة لـ 1 عند تغيّر البحث (debounced)
  useEffect(() => { setPage(1); }, [debouncedSearch]);

  useEffect(() => { load(); }, [load]);

  async function performDelete() {
    if (!confirmTarget) return;
    const target = confirmTarget;
    setMutatingId(target.id);
    try {
      await api(`/admin/users/${target.id}`, { method: "DELETE" });
      toast.success(`تم تعطيل ${target.full_name || target.email || "الحساب"}`);
      await load();
    } catch (e) {
      toast.error(e instanceof Error ? e.message : "فشل التعطيل");
    } finally {
      setMutatingId(null);
      setConfirmTarget(null);
    }
  }

  function openCreate() {
    setCreateForm(EMPTY_CREATE_FORM);
    setCreateError(null);
    setCreateOpen(true);
  }

  async function createUser() {
    const email = createForm.email.trim().toLowerCase();
    // التحقق من المدخلات قبل إرسال الطلب — مطابق لقيود الـ backend.
    if (!email || !email.includes("@")) {
      setCreateError("أدخل بريداً إلكترونياً صحيحاً.");
      return;
    }
    if (createForm.password.length < 8) {
      setCreateError("كلمة المرور يجب أن تكون 8 أحرف على الأقل.");
      return;
    }
    setCreateError(null);
    setCreating(true);
    try {
      await api("/admin/users", {
        method: "POST",
        body: JSON.stringify({
          email,
          password: createForm.password,
          full_name: createForm.full_name.trim() || null,
          role: createForm.role,
          is_active: createForm.is_active,
        }),
      });
      toast.success(`تم إنشاء حساب ${createForm.full_name.trim() || email}`);
      setCreateOpen(false);
      setPage(1);
      await load();
    } catch (e) {
      const msg = e instanceof Error ? e.message : "فشل إنشاء المستخدم";
      setCreateError(msg);
      toast.error(msg);
    } finally {
      setCreating(false);
    }
  }

  const totalPages = Math.ceil(total / PER_PAGE) || 1;
  const showPagination = total > PER_PAGE;
  const isEmpty = !debouncedSearch && total === 0;

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">المستخدمين</h1>
        <div className="flex items-center gap-2">
          <Button onClick={openCreate}>+ مستخدم جديد</Button>
          <RefreshButton onRefresh={load} />
        </div>
      </div>
      <Card className="p-6">
        <div className="flex items-center gap-4 mb-6">
          <Input
            placeholder="بحث بالاسم أو الإيميل..."
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            className="max-w-sm"
          />
          <span className="text-sm text-gray-500">{formatNumber(total)} مستخدم</span>
        </div>
        {isEmpty ? (
          <div className="py-16 text-center">
            <div className="text-5xl mb-3">👥</div>
            <p className="text-gray-500">لا يوجد مستخدمون بعد</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b text-gray-500">
                  <th className="text-right pb-3">#</th>
                  <th className="text-right pb-3">المستخدم</th>
                  <th className="text-right pb-3">الإيميل</th>
                  <th className="text-right pb-3">سبب الاستخدام</th>
                  <th className="text-right pb-3">الباقة</th>
                  <th className="text-right pb-3">الجلسات</th>
                  <th className="text-right pb-3">الحالة</th>
                  <th className="text-right pb-3">التسجيل عبر</th>
                  <th className="text-right pb-3">التاريخ</th>
                  <th className="text-right pb-3">إجراءات</th>
                </tr>
              </thead>
              <tbody>
                {users.map((u) => (
                  <tr key={u.id} className="border-b last:border-0 hover:bg-gray-50">
                    <td className="py-3 text-gray-400">{u.id}</td>
                    <td className="py-3 font-medium">
                      <Link href={`/users/${u.public_id || u.id}`} className="hover:underline">
                        {u.full_name || u.email || "—"}
                      </Link>
                    </td>
                    <td className="py-3 text-gray-500">{u.email || "-"}</td>
                    <td className="py-3">
                      {(() => {
                        const reasons = surveyReasons(u.survey_response);
                        if (reasons.length === 0) {
                          return <span className="text-gray-300 text-xs">—</span>;
                        }
                        const isHearing = reasons.includes("hearing_impaired");
                        return (
                          <div className="flex flex-wrap gap-1">
                            {reasons.slice(0, 3).map((r) => (
                              <Badge
                                key={r}
                                variant={r === "hearing_impaired" ? "default" : "outline"}
                                className={
                                  r === "hearing_impaired"
                                    ? "bg-rose-100 text-rose-700 border-rose-200"
                                    : "text-xs"
                                }
                                title={SURVEY_REASON_LABEL[r] || r}
                              >
                                <span className="me-1">{SURVEY_REASON_ICON[r] || "•"}</span>
                                {SURVEY_REASON_LABEL[r] || r}
                              </Badge>
                            ))}
                            {reasons.length > 3 && (
                              <span className="text-xs text-gray-400 self-center">
                                +{reasons.length - 3}
                              </span>
                            )}
                            {isHearing && (
                              <span className="sr-only">ضعف سمع</span>
                            )}
                          </div>
                        );
                      })()}
                    </td>
                    <td className="py-3">
                      <Badge variant={u.plan_name === "free" ? "secondary" : "default"}>
                        {PLAN_LABEL[u.plan_name || "free"] || u.plan_name}
                      </Badge>
                    </td>
                    <td className="py-3">
                      <Link href={`/users/${u.public_id || u.id}#sessions`} className="inline-flex items-center gap-1 hover:underline">
                        {u.active_sessions > 0 && <span className="h-2 w-2 rounded-full bg-green-500" />}
                        <Badge variant={u.active_sessions > 0 ? "default" : "secondary"}>
                          {formatNumber(u.active_sessions)}
                        </Badge>
                      </Link>
                    </td>
                    <td className="py-3"><Badge variant={u.is_active ? "default" : "destructive"}>{u.is_active ? "نشط" : "محظور"}</Badge></td>
                    <td className="py-3 text-gray-500 text-xs">{u.auth_provider}</td>
                    <td className="py-3 text-gray-500 text-xs">{formatDate(u.created_at)}</td>
                    <td className="py-3">
                      <div className="flex gap-2">
                        <Link href={`/users/${u.public_id || u.id}`} className="text-blue-600 hover:underline text-xs">تفاصيل</Link>
                        {u.is_active && u.id !== currentAdminId && u.role !== "admin" && (
                          <button
                            onClick={() => setConfirmTarget(u)}
                            disabled={mutatingId === u.id}
                            className="text-red-600 hover:underline text-xs disabled:opacity-50 disabled:cursor-not-allowed"
                          >
                            {mutatingId === u.id ? "..." : "تعطيل"}
                          </button>
                        )}
                      </div>
                    </td>
                  </tr>
                ))}
                {users.length === 0 && (
                  <tr><td colSpan={10} className="py-8 text-center text-gray-400">لا توجد نتائج</td></tr>
                )}
              </tbody>
            </table>
          </div>
        )}
        {showPagination && (
          <div className="flex items-center justify-between mt-4">
            <Button variant="outline" size="sm" disabled={page === 1} onClick={() => setPage(page - 1)}>السابق</Button>
            <span className="text-sm text-gray-500">صفحة {formatNumber(page)} من {formatNumber(totalPages)}</span>
            <Button variant="outline" size="sm" disabled={page * PER_PAGE >= total} onClick={() => setPage(page + 1)}>التالي</Button>
          </div>
        )}
      </Card>

      <ConfirmDialog
        open={confirmTarget !== null}
        onOpenChange={(open) => { if (!open) setConfirmTarget(null); }}
        title="تعطيل الحساب؟"
        description={confirmTarget ? `سيتم تعطيل حساب "${confirmTarget.full_name || confirmTarget.email || ""}".` : ""}
        confirmLabel="تعطيل"
        destructive
        onConfirm={performDelete}
      />

      <Dialog open={createOpen} onOpenChange={(open) => { if (!creating) setCreateOpen(open); }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>مستخدم جديد</DialogTitle>
            <DialogDescription>
              إنشاء حساب بالبريد وكلمة المرور. يبدأ على الباقة المجانية.
            </DialogDescription>
          </DialogHeader>

          <div className="grid gap-4 py-2">
            <div>
              <Label htmlFor="new-user-email" className="text-xs">البريد الإلكتروني</Label>
              <Input
                id="new-user-email"
                name="email"
                type="email"
                dir="ltr"
                value={createForm.email}
                onChange={(e) => setCreateForm({ ...createForm, email: e.target.value })}
                placeholder="user@example.com"
                className="mt-1"
              />
            </div>
            <div>
              <Label htmlFor="new-user-password" className="text-xs">كلمة المرور (8 أحرف على الأقل)</Label>
              <Input
                id="new-user-password"
                name="password"
                type="password"
                dir="ltr"
                value={createForm.password}
                onChange={(e) => setCreateForm({ ...createForm, password: e.target.value })}
                className="mt-1"
              />
            </div>
            <div>
              <Label htmlFor="new-user-name" className="text-xs">الاسم (اختياري)</Label>
              <Input
                id="new-user-name"
                name="full_name"
                value={createForm.full_name}
                onChange={(e) => setCreateForm({ ...createForm, full_name: e.target.value })}
                className="mt-1"
              />
            </div>
            <div>
              <Label htmlFor="new-user-role" className="text-xs">الدور</Label>
              <select
                id="new-user-role"
                name="role"
                className="mt-1 w-full h-9 rounded-lg border border-input bg-transparent px-2.5 text-sm"
                value={createForm.role}
                onChange={(e) => setCreateForm({ ...createForm, role: e.target.value as CreateForm["role"] })}
              >
                <option value="user">مستخدم</option>
                <option value="admin">مشرف</option>
              </select>
            </div>
            <label className="flex items-center gap-2 text-sm" htmlFor="new-user-active">
              <input
                id="new-user-active"
                name="is_active"
                type="checkbox"
                checked={createForm.is_active}
                onChange={(e) => setCreateForm({ ...createForm, is_active: e.target.checked })}
              />
              نشط
            </label>
            {createError && <div className="text-red-600 text-sm">{createError}</div>}
          </div>

          <DialogFooter>
            <Button variant="outline" onClick={() => setCreateOpen(false)} disabled={creating}>إلغاء</Button>
            <Button onClick={createUser} disabled={creating}>{creating ? "جاري الإنشاء..." : "إنشاء"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
