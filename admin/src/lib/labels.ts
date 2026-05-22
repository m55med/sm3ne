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

// أسباب الاستخدام من استبيان الـ onboarding — نفس مفاتيح الموبايل في
// `mobile/lib/features/survey/survey_screen.dart`. هنا للـ rendering في
// `/users` page وكروت تفاصيل المستخدم.
export const SURVEY_REASON_LABEL: Record<string, string> = {
  hearing_impaired: "ضعف سمع",
  voice_messages: "رسائل صوتية",
  lectures: "محاضرات",
  meetings: "اجتماعات",
  accessibility: "إمكانية وصول",
  other: "أخرى",
};

// تنسيق الأيقونة (emoji) لكل سبب — يستخدم في الـ list view حيث المساحة ضيقة.
export const SURVEY_REASON_ICON: Record<string, string> = {
  hearing_impaired: "🦻",
  voice_messages: "💬",
  lectures: "🎓",
  meetings: "👥",
  accessibility: "♿",
  other: "❓",
};
