// ─── Emergency Contact Model ──────────────────────────────────────────────────

class EmergencyContact {
  final String name;
  final String phoneNumber;

  const EmergencyContact({
    required this.name,
    required this.phoneNumber,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'phoneNumber': phoneNumber,
  };

  factory EmergencyContact.fromJson(Map<String, dynamic> json) =>
      EmergencyContact(
        name: json['name'] as String,
        phoneNumber: json['phoneNumber'] as String,
      );
}