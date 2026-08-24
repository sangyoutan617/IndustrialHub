class Profile {
  final String id;
  final String? email;
  final String? displayName;
  final String? phone;
  final String? jobTitle;
  final String? company;
  final bool onboarded;
  final DateTime createdAt;

  const Profile({
    required this.id,
    this.email,
    this.displayName,
    this.phone,
    this.jobTitle,
    this.company,
    this.onboarded = false,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      phone: json['phone'] as String?,
      jobTitle: json['job_title'] as String?,
      company: json['company'] as String?,
      onboarded: json['onboarded'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
