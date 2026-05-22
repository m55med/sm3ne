"use client";

import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";
import { Card } from "@/components/ui/card";
import { Badge } from "@/components/ui/badge";
import { formatDateTime } from "@/lib/format";
import type { DeviceItem } from "@/lib/types";

/// Renders the per-user device list on the user-detail page. Auto-loads on
/// mount; failures fall back to an empty state without blocking the rest of
/// the user page.
export function UserDevicesSection({ userRef }: { userRef: string | number }) {
  const [devices, setDevices] = useState<DeviceItem[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  const load = useCallback(async () => {
    setError(null);
    try {
      const list = await api<DeviceItem[]>(`/admin/users/${userRef}/devices`);
      setDevices(list);
    } catch (e) {
      setError(e instanceof Error ? e.message : "تعذّر تحميل الأجهزة");
      setDevices([]);
    }
  }, [userRef]);

  useEffect(() => {
    load();
  }, [load]);

  return (
    <Card className="p-6">
      <div className="flex items-center justify-between mb-4">
        <h2 className="text-lg font-bold">الأجهزة المسجّلة</h2>
        <span className="text-sm text-gray-500">
          {devices?.length ?? "..."} جهاز
        </span>
      </div>
      {error && (
        <p className="text-sm text-red-600 mb-3">{error}</p>
      )}
      {devices === null ? (
        <div className="py-6 text-center text-gray-400 text-sm">جاري التحميل…</div>
      ) : devices.length === 0 ? (
        <p className="text-sm text-gray-500">لا يوجد أجهزة مسجلة لهذا المستخدم.</p>
      ) : (
        <div className="space-y-3">
          {devices.map((d) => (
            <div
              key={d.public_id}
              className="rounded-lg border border-gray-200 p-3 text-sm flex flex-wrap items-start gap-3"
            >
              <div className="flex-1 min-w-[180px]">
                <div className="font-semibold text-gray-900">
                  {d.device_marketing_name || d.device_model || "جهاز غير معروف"}
                </div>
                <div className="text-xs text-gray-500 flex flex-wrap gap-x-3 mt-1">
                  {d.device_model && d.device_marketing_name && (
                    <span dir="ltr">طراز: {d.device_model}</span>
                  )}
                  {d.device_os_version && (
                    <span dir="ltr">
                      {d.platform === "ios" ? "iOS" : "Android"} {d.device_os_version}
                    </span>
                  )}
                  {d.app_version && (
                    <span dir="ltr">إصدار التطبيق: {d.app_version}</span>
                  )}
                  {d.device_locale && (
                    <span dir="ltr">{d.device_locale}</span>
                  )}
                </div>
              </div>
              <div className="flex flex-col items-end gap-1">
                <Badge variant={d.platform === "ios" ? "default" : "secondary"}>
                  {d.platform === "ios" ? " iOS" : "Android"}
                </Badge>
                {d.push_enabled ? (
                  <Badge className="bg-green-100 text-green-700">إشعارات: ON</Badge>
                ) : (
                  <Badge variant="outline" className="text-gray-500">إشعارات: OFF</Badge>
                )}
                {d.last_seen_at && (
                  <span className="text-[10px] text-gray-400">
                    آخر ظهور: {formatDateTime(d.last_seen_at)}
                  </span>
                )}
              </div>
            </div>
          ))}
        </div>
      )}
    </Card>
  );
}
