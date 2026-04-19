"use client";
import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import { api } from "@/lib/api";
import { getCurrentAdminId } from "@/lib/auth";
import { Card } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { RefreshButton } from "@/components/refresh-button";
import type { UserListItem, PaginatedResponse } from "@/lib/types";

const PLAN_LABEL: Record<string, string> = {
  free: "مجاني",
  monthly: "شهري",
  annual: "سنوي",
};

export default function UsersPage() {
  const [users, setUsers] = useState<UserListItem[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(1);
  const [search, setSearch] = useState("");
  const currentAdminId = getCurrentAdminId();

  const load = useCallback(async () => {
    const params = new URLSearchParams({ page: String(page), per_page: "20" });
    if (search) params.set("search", search);
    const r = await api<PaginatedResponse<UserListItem>>(`/admin/users?${params}`);
    setUsers(r.users || []);
    setTotal(r.total);
  }, [page, search]);

  useEffect(() => { load(); }, [load]);

  async function handleDelete(u: UserListItem) {
    if (!window.confirm(`تعطيل حساب "${u.username}"؟`)) return;
    try {
      await api(`/admin/users/${u.id}`, { method: "DELETE" });
      await load();
    } catch (e) {
      alert(e instanceof Error ? e.message : "فشل التعطيل");
    }
  }

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <h1 className="text-2xl font-bold text-gray-900">المستخدمين</h1>
        <RefreshButton onRefresh={load} />
      </div>
      <Card className="p-6">
        <div className="flex items-center gap-4 mb-6">
          <Input placeholder="بحث بالاسم أو الإيميل..." value={search} onChange={(e) => { setSearch(e.target.value); setPage(1); }} className="max-w-sm" />
          <span className="text-sm text-gray-500">{total} مستخدم</span>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b text-gray-500">
                <th className="text-right pb-3">#</th>
                <th className="text-right pb-3">المستخدم</th>
                <th className="text-right pb-3">الإيميل</th>
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
                      {u.full_name || u.username}
                    </Link>
                  </td>
                  <td className="py-3 text-gray-500">{u.email || "-"}</td>
                  <td className="py-3">
                    <Badge variant={u.plan_name === "free" ? "secondary" : "default"}>
                      {PLAN_LABEL[u.plan_name || "free"] || u.plan_name}
                    </Badge>
                  </td>
                  <td className="py-3">
                    <Link href={`/users/${u.public_id || u.id}#sessions`} className="inline-flex items-center gap-1 hover:underline">
                      {u.active_sessions > 0 && <span className="h-2 w-2 rounded-full bg-green-500" />}
                      <Badge variant={u.active_sessions > 0 ? "default" : "secondary"}>
                        {u.active_sessions}
                      </Badge>
                    </Link>
                  </td>
                  <td className="py-3"><Badge variant={u.is_active ? "default" : "destructive"}>{u.is_active ? "نشط" : "محظور"}</Badge></td>
                  <td className="py-3 text-gray-500 text-xs">{u.auth_provider}</td>
                  <td className="py-3 text-gray-500 text-xs">{new Date(u.created_at).toLocaleDateString("ar")}</td>
                  <td className="py-3">
                    <div className="flex gap-2">
                      <Link href={`/users/${u.public_id || u.id}`} className="text-blue-600 hover:underline text-xs">تفاصيل</Link>
                      {u.is_active && u.id !== currentAdminId && u.role !== "admin" && (
                        <button onClick={() => handleDelete(u)} className="text-red-600 hover:underline text-xs">تعطيل</button>
                      )}
                    </div>
                  </td>
                </tr>
              ))}
              {users.length === 0 && (
                <tr><td colSpan={9} className="py-8 text-center text-gray-400">لا توجد نتائج</td></tr>
              )}
            </tbody>
          </table>
        </div>
        <div className="flex items-center justify-between mt-4">
          <Button variant="outline" size="sm" disabled={page === 1} onClick={() => setPage(page - 1)}>السابق</Button>
          <span className="text-sm text-gray-500">صفحة {page} من {Math.ceil(total / 20) || 1}</span>
          <Button variant="outline" size="sm" disabled={page * 20 >= total} onClick={() => setPage(page + 1)}>التالي</Button>
        </div>
      </Card>
    </div>
  );
}
