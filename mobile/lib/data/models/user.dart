class User {
  final int id;
  final String username;
  final String? email;
  final String? fullName;
  final String authProvider;
  final String role;
  final String? surveyResponse;
  final String createdAt;

  User({
    required this.id,
    required this.username,
    this.email,
    this.fullName,
    required this.authProvider,
    required this.role,
    this.surveyResponse,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      fullName: json['full_name'],
      authProvider: json['auth_provider'] ?? 'local',
      role: json['role'] ?? 'user',
      surveyResponse: json['survey_response'],
      createdAt: json['created_at'] ?? '',
    );
  }

  bool get isPaid => role != 'user'; // simplified, should check subscription
}
