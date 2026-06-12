class UserModel {
  final String email;
  final String displayName;

  UserModel({required this.email, required this.displayName});

  String get initials {
    final parts = displayName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return displayName.substring(0, 2).toUpperCase();
  }
}