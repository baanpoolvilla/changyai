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
  week1,
  week2,
  week3,
  month1,
  month2,
  month3,
  month4,
  month5,
  month6,
  month7,
  month8,
  month9,
  month10,
  month11,
  month12;

  static PmFrequency fromString(String value) {
    // backward compat for old DB values
    const legacyMap = {
      'weekly': 'week1',
      'biweekly': 'week2',
      'monthly': 'month1',
      'quarterly': 'month3',
      'semiannual': 'month6',
      'annual': 'month12',
    };
    final mapped = legacyMap[value] ?? value;
    return PmFrequency.values.firstWhere(
      (e) => e.name == mapped,
      orElse: () => PmFrequency.month1,
    );
  }

  String get displayName {
    switch (this) {
      case PmFrequency.week1:
        return '1 สัปดาห์';
      case PmFrequency.week2:
        return '2 สัปดาห์';
      case PmFrequency.week3:
        return '3 สัปดาห์';
      case PmFrequency.month1:
        return '1 เดือน';
      case PmFrequency.month2:
        return '2 เดือน';
      case PmFrequency.month3:
        return '3 เดือน';
      case PmFrequency.month4:
        return '4 เดือน';
      case PmFrequency.month5:
        return '5 เดือน';
      case PmFrequency.month6:
        return '6 เดือน';
      case PmFrequency.month7:
        return '7 เดือน';
      case PmFrequency.month8:
        return '8 เดือน';
      case PmFrequency.month9:
        return '9 เดือน';
      case PmFrequency.month10:
        return '10 เดือน';
      case PmFrequency.month11:
        return '11 เดือน';
      case PmFrequency.month12:
        return '12 เดือน';
    }
  }
}
