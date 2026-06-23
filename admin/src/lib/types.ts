export interface AdminStats {
  total_users: number;
  active_subscribers: number;
  requests_today: number;
  requests_week: number;
  requests_month: number;
  total_requests: number;
}

export interface UserListItem {
  id: number;
  public_id: string | null;
  email: string | null;
  full_name: string | null;
  role: string;
  is_active: boolean;
  auth_provider: string;
  plan_name: string | null;
  active_sessions: number;
  last_session_at: string | null;
  // JSON blob like `{"reasons": ["hearing_impaired"], "other_text": "..."}` —
  // see SURVEY_REASON_LABEL in lib/labels.ts for the AR display names.
  survey_response: string | null;
  created_at: string;
}

export interface UserSubscriptionInfo {
  plan_name: string;
  plan_source: "free" | "coupon" | "purchase";
  starts_at: string | null;
  expires_at: string | null;
  days_remaining: number | null;
  coupon_code: string | null;
  coupon_id: number | null;
  is_active: boolean;
}

export interface UserUsageInfo {
  requests_today: number;
  requests_this_month: number;
  requests_today_api: number;
  daily_limit: number;
  monthly_limit: number | null;
  api_daily_limit: number;
  max_audio_seconds: number;
}

export interface UserDetail {
  id: number;
  public_id: string | null;
  email: string | null;
  full_name: string | null;
  role: string;
  is_active: boolean;
  auth_provider: string;
  survey_response: string | null;
  created_at: string | null;
  total_requests: number;
  subscription: UserSubscriptionInfo;
  usage: UserUsageInfo;
  active_sessions: number;
}

export interface SessionItem {
  id: number;
  event_type: "login" | "register" | "refresh";
  auth_provider: string;
  success: boolean;
  error_message: string | null;
  ip_address: string | null;
  user_agent: string | null;
  device_platform: string | null;
  device_model: string | null;
  device_os_version: string | null;
  app_version: string | null;
  is_active: boolean;
  created_at: string;
}

export interface PaginatedResponse<T> {
  total: number;
  page: number;
  per_page: number;
  users?: T[];
  requests?: T[];
  coupons?: T[];
}

export type RequestSource =
  | "upload"
  | "recording"
  | "share"
  | "api"
  | "telegram"
  | "translation";

export interface RequestItem {
  id: number;
  user_public_id: string | null;
  email: string | null;
  full_name: string | null;
  api_key_id: number | null;
  api_key_name: string | null;
  filename: string | null;
  duration_seconds: number;
  processed_seconds: number;
  language: string | null;
  word_count: number;
  was_trimmed: boolean;
  status: "processing" | "completed" | "failed";
  error_message: string | null;
  plan_name: string;
  plan_source: "free" | "coupon" | "purchase";
  daily_used: number;
  daily_limit: number;
  monthly_limit: number | null;
  // Origin of the request — closed set, telegram stamped server-side.
  source: RequestSource;
  is_live_recording: boolean;
  provider_used: string | null;
  model_used: string | null;
  latency_ms: number | null;
  created_at: string;
}

export interface SubscriptionLogItem {
  id: number;
  user_id: number;
  user_public_id: string | null;
  email: string | null;
  full_name: string | null;
  plan_id: number;
  plan_name: string;
  plan_source: "free" | "coupon" | "purchase";
  coupon_code: string | null;
  starts_at: string | null;
  expires_at: string | null;
  is_active: boolean;
  created_at: string | null;
}

export interface SubscriptionLogResponse {
  subscriptions: SubscriptionLogItem[];
  total: number;
  page: number;
  per_page: number;
}

export type TicketStatus = "open" | "in_progress" | "resolved" | "closed";
export type TicketType = "contact" | "suggestion" | "bug" | "other";

export interface TicketSummary {
  public_id: string;
  user_public_id: string | null;
  user_email: string | null;
  user_full_name: string | null;
  ticket_type: TicketType;
  subject: string;
  status: TicketStatus;
  reply_count: number;
  last_reply_at: string | null;
  created_at: string | null;
}

export interface TicketAttachmentItem {
  public_id: string;
  reply_public_id: string | null;
  original_filename: string | null;
  mime_type: string;
  size_bytes: number;
  created_at: string | null;
}

export interface TicketReplyItem {
  public_id: string | null;
  is_admin: boolean;
  author_name: string | null;
  message: string;
  created_at: string | null;
  attachments?: TicketAttachmentItem[];
}

export interface TicketDetail {
  public_id: string;
  user_public_id: string | null;
  user_email: string | null;
  user_full_name: string | null;
  ticket_type: TicketType;
  subject: string;
  message: string;
  status: TicketStatus;
  replies: TicketReplyItem[];
  attachments?: TicketAttachmentItem[];
  created_at: string | null;
  updated_at: string | null;
}

export interface TicketAttachLimits {
  max_bytes: number;
  allowed_extensions: string[];
}

export interface AdminTicketListResponse {
  tickets: TicketSummary[];
  total: number;
  page: number;
  per_page: number;
}

export interface PlanSubscriberItem {
  user_id: number;
  user_public_id: string | null;
  full_name: string | null;
  email: string | null;
  plan_source: "free" | "coupon" | "purchase";
  coupon_code: string | null;
  starts_at: string | null;
  expires_at: string | null;
  days_remaining: number | null;
}

export interface Coupon {
  id: number;
  code: string;
  plan_id: number;
  duration_days: number;
  max_uses: number;
  times_used: number;
  is_active: boolean;
  created_at: string;
  expires_at: string | null;
}

export interface Plan {
  id: number;
  name: string;
  price: number;
  original_price: number;
  max_audio_seconds: number;
}

export interface PlanAdminItem {
  id: number;
  name: string;
  price: number;
  original_price: number;
  max_audio_seconds: number;
  daily_request_limit: number;
  monthly_request_limit: number | null;
  api_daily_request_limit: number;
  rpm_default: number;
  api_keys_allowed: number;
  description: string | null;
  is_active: boolean;
  subscriber_count: number;
  transcription_provider: string | null;
  transcription_model: string | null;
}

export type PlanCreateBody = Omit<PlanAdminItem, "id" | "subscriber_count">;
export type PlanUpdateBody = Partial<Omit<PlanAdminItem, "id" | "name" | "subscriber_count">>;

export type TranscriptionProvider =
  | "speechmatics"
  | "gemini"
  | "groq"
  | "assemblyai";

export interface ModelOption {
  id: string;
  label: string;
  description: string | null;
}

export interface TranscriptionProviderInfo {
  name: TranscriptionProvider;
  label: string;
  description: string;
  available: boolean;
  models: ModelOption[];
  selected_model: string | null;
  default_model: string | null;
}

export interface ProviderTestResult {
  provider: TranscriptionProvider;
  model: string | null;
  duration_ms: number;
  audio_seconds: number;
  text: string;
  language: string | null;
  word_count: number;
  segment_count: number;
}

export interface TranscriptionProviderSetting {
  current: TranscriptionProvider;
  effective: TranscriptionProvider;
  updated_at: string | null;
  updated_by_user_id: number | null;
  providers: TranscriptionProviderInfo[];
  // Auto-failover priority — highest priority first. When the active provider
  // fails mid-request, the backend walks this list to the next one.
  provider_order: TranscriptionProvider[];
}

export interface ProviderUsageLocal {
  requests_today: number;
  requests_month: number;
  requests_total: number;
  seconds_today: number;
  seconds_month: number;
  seconds_total: number;
}

export interface ProviderUsageRemote {
  period: string;
  total_hours_month: number;
}

// -- Telegram bot ----------------------------------------------------------

export interface TelegramUserItem {
  id: number;
  telegram_id: number;
  first_name: string | null;
  last_name: string | null;
  username: string | null;
  language_code: string | null;
  is_premium: boolean;
  is_blocked: boolean;
  bio: string | null;
  photo_url: string | null;
  linked_user_id: number | null;
  linked_user_email: string | null;
  linked_user_full_name: string | null;
  linked_user_public_id: string | null;
  linked_at: string | null;
  last_interaction_at: string | null;
  created_at: string;
}

export interface TelegramUserListResponse {
  items: TelegramUserItem[];
  total: number;
  page: number;
  per_page: number;
}

export interface TelegramBotMessageItem {
  key: string;
  description: string | null;
  text_ar: string;
  default_text: string;
  is_default: boolean;
  updated_at: string | null;
  updated_by_user_id: number | null;
}

export interface TelegramWebhookInfo {
  configured: boolean;
  url: string | null;
  pending_update_count: number | null;
  last_error_date: string | null;
  last_error_message: string | null;
  bot_username: string | null;
}

export type TelegramAudience = "all" | "linked_only" | "unlinked_only" | "selected";

export interface ProviderUsage {
  provider: TranscriptionProvider;
  free_tier_label: string | null;
  free_tier_limit_text: string | null;
  billing_unit: string | null;
  local: ProviderUsageLocal;
  remote: ProviderUsageRemote | null;
}

export interface TranscriptionProviderUsageResponse {
  providers: ProviderUsage[];
}

// --- Admin audio analyzer ---

export interface AnalyzeFileInfo {
  filename: string;
  content_type: string | null;
  size_bytes: number;
}

export interface AnalyzeWordCount {
  word: string;
  count: number;
}

export interface AnalyzeSegment {
  id: number;
  start: number;
  end: number;
  text: string;
}

export interface AnalyzeAudioResponse {
  file: AnalyzeFileInfo;
  provider: string;
  model: string | null;
  language: string;
  language_name: string;
  duration_seconds: number;
  text: string;
  char_count: number;
  char_count_no_spaces: number;
  word_count: number;
  unique_word_count: number;
  avg_word_length: number;
  longest_word: string;
  sentence_count: number;
  paragraph_count: number;
  line_count: number;
  segment_count: number;
  speaking_rate_wpm: number | null;
  punctuation: Record<string, number>;
  top_words: AnalyzeWordCount[];
  segments: AnalyzeSegment[];
}

// --- Devices + push notifications --------------------------------------------

export interface DeviceItem {
  public_id: string;
  user_id: number;
  user_email: string | null;
  user_full_name: string | null;
  platform: "android" | "ios";
  device_model: string | null;
  device_marketing_name: string | null;
  device_os: string | null;
  device_os_version: string | null;
  device_locale: string | null;
  app_version: string | null;
  push_enabled: boolean;
  last_seen_at: string | null;
  created_at: string | null;
}

export interface DeviceListResponse {
  devices: DeviceItem[];
  total: number;
  page: number;
  per_page: number;
}

export type NotificationTarget =
  | "all"
  | "users"
  | "devices"
  | "hearing_impaired";

export interface NotificationSendRequest {
  title: string;
  body: string;
  target: NotificationTarget;
  user_ids?: number[];
  device_public_ids?: string[];
  deep_link?: string;
}

export interface NotificationSendResponse {
  sent: number;
  failed: number;
  skipped_no_token: number;
}
