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
  username: string;
  email: string | null;
  full_name: string | null;
  role: string;
  is_active: boolean;
  auth_provider: string;
  plan_name: string | null;
  active_sessions: number;
  last_session_at: string | null;
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
  username: string;
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
}

export interface RequestItem {
  id: number;
  user_public_id: string | null;
  username: string;
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
  created_at: string;
}

export interface SubscriptionLogItem {
  id: number;
  user_id: number;
  user_public_id: string | null;
  username: string;
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
  username: string | null;
  ticket_type: TicketType;
  subject: string;
  status: TicketStatus;
  reply_count: number;
  last_reply_at: string | null;
  created_at: string | null;
}

export interface TicketReplyItem {
  public_id: string | null;
  is_admin: boolean;
  author_name: string | null;
  message: string;
  created_at: string | null;
}

export interface TicketDetail {
  public_id: string;
  user_public_id: string | null;
  username: string | null;
  ticket_type: TicketType;
  subject: string;
  message: string;
  status: TicketStatus;
  replies: TicketReplyItem[];
  created_at: string | null;
  updated_at: string | null;
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
  username: string;
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
}

export type PlanCreateBody = Omit<PlanAdminItem, "id" | "subscriber_count">;
export type PlanUpdateBody = Partial<Omit<PlanAdminItem, "id" | "name" | "subscriber_count">>;
