/// User model — maps to `users` table in Supabase
class AppUser {
  final String id;
  final String email;
  final String fullName;
  final UserRole role;
  final String? phone;
  final DateTime createdAt;

  const AppUser({
    required this.id,
    required this.email,
    required this.fullName,
    required this.role,
    this.phone,
    required this.createdAt,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String,
      role: UserRole.fromString(json['role'] as String),
      phone: json['phone'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'full_name': fullName,
    'role': role.name,
    'phone': phone,
    'created_at': createdAt.toIso8601String(),
  };
}

enum UserRole {
  admin,
  owner,
  manager,
  caretaker,
  technician;

  static UserRole fromString(String value) {
    return UserRole.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UserRole.technician,
    );
  }

  String get displayName {
    switch (this) {
      case UserRole.admin:
        return 'Super Admin';
      case UserRole.owner:
        return 'CEO';
      case UserRole.manager:
        return 'ผู้จัดการ';
      case UserRole.caretaker:
        return 'ผู้ดูแลบ้าน';
      case UserRole.technician:
        return 'ช่าง';
    }
  }

  /// Returns true if this role has admin-level access (sees dashboard, expenses, etc.)
  bool get isAdmin =>
      this == admin || this == owner || this == manager || this == caretaker;

  /// Returns true only for the Super Admin role (full system control)
  bool get isSuperAdmin => this == admin;

  /// Returns true for CEO (owner) role
  bool get isCeo => this == owner;

  /// Returns true if this role can assign caretakers and technicians
  bool get canAssignCaretaker =>
      this == admin || this == owner || this == manager;

  /// Returns true if this role can assign technicians
  bool get canAssignTechnician =>
      this == admin || this == owner || this == manager || this == caretaker;

  /// Returns true if this role can add/view expenses
  bool get canManageExpenses =>
      this == admin || this == owner || this == manager || this == caretaker;
}
