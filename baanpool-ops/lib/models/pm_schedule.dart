/// PM Schedule model — maps to `pm_schedules` table in Supabase
class PmSchedule {
  final String id;
  final String propertyId;
  final String? assetId;
  final String title;
  final String? description;
  final PmFrequency frequency;
  final DateTime nextDueDate;
  final DateTime? lastCompletedDate;
  final bool isActive;
  final String? assignedTo;
  final String? assignedToName; // joined from users table
  final String? propertyName; // joined from properties table
  final String? assetName; // joined from assets table
  final DateTime createdAt;

  const PmSchedule({
    required this.id,
    required this.propertyId,
    this.assetId,
    required this.title,
    this.description,
    required this.frequency,
    required this.nextDueDate,
    this.lastCompletedDate,
    this.isActive = true,
    this.assignedTo,
    this.assignedToName,
    this.propertyName,
    this.assetName,
    required this.createdAt,
  });

  factory PmSchedule.fromJson(Map<String, dynamic> json) {
    // Handle joined user data
    String? techName;
    if (json['users'] is Map) {
      techName = json['users']['full_name'] as String?;
    }

    // Handle joined property data
    String? propName;
    if (json['properties'] is Map) {
      propName = json['properties']['name'] as String?;
    }

    // Handle joined asset data
    String? aName;
    if (json['assets'] is Map) {
      aName = json['assets']['name'] as String?;
    }

    return PmSchedule(
      id: json['id'] as String,
      propertyId: json['property_id'] as String,
      assetId: json['asset_id'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      frequency: PmFrequency.fromString(json['frequency'] as String),
      nextDueDate: DateTime.parse(json['next_due_date'] as String),
      lastCompletedDate: json['last_completed_date'] != null
          ? DateTime.parse(json['last_completed_date'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? true,
      assignedTo: json['assigned_to'] as String?,
      assignedToName: techName,
      propertyName: propName,
      assetName: aName,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'property_id': propertyId,
    'asset_id': assetId,
    'title': title,
    'description': description,
    'frequency': frequency.name,
    'next_due_date': nextDueDate.toIso8601String(),
    'last_completed_date': lastCompletedDate?.toIso8601String(),
    'is_active': isActive,
    'assigned_to': assignedTo,
  };

  bool get isDueSoon =>
      nextDueDate.difference(DateTime.now()).inDays <= 7 && isActive;
}

enum PmFrequency {
  weekly,
  biweekly,
  monthly,
  threeMonth,
  sixMonth,
  year;

  static PmFrequency fromString(String value) {
    return PmFrequency.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PmFrequency.monthly,
    );
  }

  String get displayName {
    switch (this) {
      case PmFrequency.weekly:
        return '1 สัปดาห์';
      case PmFrequency.biweekly:
        return '2 สัปดาห์';
      case PmFrequency.monthly:
        return '1 เดือน';
      case PmFrequency.threeMonth:
        return '3 เดือน';
      case PmFrequency.sixMonth:
        return '6 เดือน';
      case PmFrequency.year:
        return '1 ปี';
    }
  }
}
