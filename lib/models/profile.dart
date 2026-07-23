class Profile {
  final String id;
  final String? email;
  final String? displayName;
  final DateTime createdAt;

  const Profile({
    required this.id,
    this.email,
    this.displayName,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      email: json['email'] as String?,
      displayName: json['display_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
