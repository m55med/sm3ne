class User {
  final int id;
  final String? email;
  final String? fullName;
  final String authProvider;
  final String role;
  final String? surveyResponse;
  final String createdAt;

  /// Name of the user's current subscription plan as returned by the backend
  /// (e.g. `'free'`, `'monthly'`, `'annual'`). May be null if the backend has
  /// not yet attached subscription info to `/profile/me` — in which case the
  /// caller can hydrate it via a follow-up `/plans/current` request.
  final String? currentPlanName;

  User({
    required this.id,
    this.email,
    this.fullName,
    required this.authProvider,
    required this.role,
    this.surveyResponse,
    required this.createdAt,
    this.currentPlanName,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as int,
      email: json['email'] as String?,
      fullName: json['full_name'] as String?,
      authProvider: (json['auth_provider'] as String?) ?? 'local',
      role: (json['role'] as String?) ?? 'user',
      surveyResponse: json['survey_response'] as String?,
      createdAt: (json['created_at'] as String?) ?? '',
      // Parse defensively — backend may or may not yet send this field.
      currentPlanName: json['current_plan_name'] as String?,
    );
  }

  User copyWith({
    int? id,
    String? email,
    String? fullName,
    String? authProvider,
    String? role,
    String? surveyResponse,
    String? createdAt,
    String? currentPlanName,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      authProvider: authProvider ?? this.authProvider,
      role: role ?? this.role,
      surveyResponse: surveyResponse ?? this.surveyResponse,
      createdAt: createdAt ?? this.createdAt,
      currentPlanName: currentPlanName ?? this.currentPlanName,
    );
  }

  /// Best-effort display name: prefer `fullName`, fall back to the email
  /// local-part, finally an empty string. Used wherever the UI greets the
  /// user or labels a record.
  String get displayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final mail = email?.trim();
    if (mail == null || mail.isEmpty) return '';
    final at = mail.indexOf('@');
    return at > 0 ? mail.substring(0, at) : mail;
  }

  /// True when the user is on a paid plan. Free plan (or missing plan) → false.
  bool get isPaid =>
      currentPlanName != null &&
      currentPlanName!.isNotEmpty &&
      currentPlanName != 'free';
}
