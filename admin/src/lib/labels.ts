// تسميات موحدة (Arabic labels) — لا تكرر هذه المعاجم في صفحات أخرى

export const PLAN_LABEL: Record<string, string> = {
  free: "مجاني",
  monthly: "شهري",
  annual: "سنوي",
};

export const TICKET_STATUS_LABEL: Record<string, string> = {
  open: "مفتوحة",
  in_progress: "قيد المعالجة",
  resolved: "محلولة",
  closed: "مغلقة",
};

export const TICKET_TYPE_LABEL: Record<string, string> = {
  contact: "تواصل",
  suggestion: "اقتراح",
  bug: "خطأ",
  other: "أخرى",
};

// مصدر الاشتراك (subscription source)
export const SUBSCRIPTION_SOURCE_LABEL: Record<string, string> = {
  free: "مجاني",
  coupon: "كوبون",
  purchase: "مدفوع",
};

// مصدر تحويل الصوت (request source) — للاستخدام مع جلسات/طلبات
export const SOURCE_LABEL: Record<string, string> = {
  upload: "رفع ملف",
  recording: "تسجيل",
  share: "مشاركة",
  api: "API",
};
