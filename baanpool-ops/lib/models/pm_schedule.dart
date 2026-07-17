import '../utils/thai_datetime.dart';

/// PM Schedule model — maps to `pm_schedules` table in Supabase
class PmSchedule {
  final String id;
  final String propertyId;
  final String? assetId;
  final String title;
  final String? description;
  final PmFrequency frequency;
  final DateTime nextDueDate;
  /// วันตั้งต้นของรอบ — ใช้ยึดไม่ให้วันกำหนดดริฟต์ตามวันจบงาน
  final DateTime? anchorDate;
  /// จำนวนรอบต่อปี (นับจาก anchor) — null = ทำต่อเนื่อง ไม่มีการเว้น
  final int? roundsPerYear;
  /// จำนวนครั้งทั้งหมดที่ต้องทำ เช่น ฉีดปลวก 6 ครั้ง — null = ทำไม่จำกัด
  final int? totalRounds;
  /// ทำไปแล้วกี่ครั้ง (ใช้คู่กับ totalRounds)
  final int roundsDone;
  /// true = จบครั้งล่าสุดแล้ว รอคนนัดวันครั้งถัดไป
  final bool awaitingSchedule;
  final DateTime? lastCompletedDate;
  final bool isActive;
  final String? assignedTo;
  /// ผู้รับสำเนาแจ้งเตือน — คัดลอกไปที่ใบงานทุกใบที่สร้างจาก PM นี้
  final List<String> ccUserIds;
  final String? assignedToName; // joined from users table
  final String? createdByName; // joined from users table (creator)
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
    this.anchorDate,
    this.roundsPerYear,
    this.totalRounds,
    this.roundsDone = 0,
    this.awaitingSchedule = false,
    this.lastCompletedDate,
    this.isActive = true,
    this.assignedTo,
    this.ccUserIds = const [],
    this.assignedToName,
    this.createdByName,
    this.propertyName,
    this.assetName,
    required this.createdAt,
  });

  factory PmSchedule.fromJson(Map<String, dynamic> json) {
    // Handle joined user data (assigned to)
    String? techName;
    if (json['users'] is Map) {
      techName = json['users']['full_name'] as String?;
    }

    // Handle joined creator data
    String? creatorName;
    if (json['creator'] is Map) {
      creatorName = json['creator']['full_name'] as String?;
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
      anchorDate: json['anchor_date'] != null
          ? DateTime.parse(json['anchor_date'] as String)
          : null,
      roundsPerYear: json['rounds_per_year'] as int?,
      totalRounds: json['total_rounds'] as int?,
      roundsDone: json['rounds_done'] as int? ?? 0,
      awaitingSchedule: json['awaiting_schedule'] as bool? ?? false,
      lastCompletedDate: json['last_completed_date'] != null
          ? DateTime.parse(json['last_completed_date'] as String)
          : null,
      isActive: json['is_active'] as bool? ?? true,
      assignedTo: json['assigned_to'] as String?,
      ccUserIds:
          (json['cc_user_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const [],
      assignedToName: techName,
      createdByName: creatorName,
      propertyName: propName,
      assetName: aName,
      createdAt: parseServerTimestampToThai(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'property_id': propertyId,
    'asset_id': assetId,
    'title': title,
    'description': description,
    'frequency': frequency.toDbValue,
    'next_due_date': nextDueDate.toIso8601String(),
    'anchor_date': anchorDate?.toIso8601String().split('T').first,
    'rounds_per_year': roundsPerYear,
    'last_completed_date': lastCompletedDate?.toIso8601String(),
    'is_active': isActive,
    'assigned_to': assignedTo,
  };

  bool get isDueSoon =>
      nextDueDate.difference(thaiNow()).inDays <= 7 && isActive;

  /// ประเภทของ PM — แยกจากข้อมูล ไม่ได้เก็บเป็นคอลัมน์แยก
  PmMode get mode {
    if (totalRounds != null) return PmMode.limitedCount;
    if (roundsPerYear != null) return PmMode.yearlyRounds;
    return PmMode.continuous;
  }

  /// เหลืออีกกี่ครั้ง (เฉพาะแบบจำกัดจำนวนครั้ง)
  int? get roundsLeft =>
      totalRounds == null ? null : (totalRounds! - roundsDone);
}

/// ประเภทการทำซ้ำของ PM
enum PmMode {
  /// ทำทุก N เดือน/สัปดาห์ ไปเรื่อยๆ ไม่มีวันจบ
  continuous,

  /// ทำ N รอบต่อปีแล้วเว้นยาว วนกลับวันเดิมปีถัดไป (เช่น ล้างแอร์)
  yearlyRounds,

  /// ทำทั้งหมด N ครั้งแล้วจบ ไม่มีความถี่ นัดวันทีละครั้ง (เช่น ฉีดปลวก)
  limitedCount;

  String get displayName {
    switch (this) {
      case PmMode.continuous:
        return 'ทำต่อเนื่อง';
      case PmMode.yearlyRounds:
        return 'ทำเป็นรอบต่อปี';
      case PmMode.limitedCount:
        return 'จำกัดจำนวนครั้ง';
    }
  }

  String get description {
    switch (this) {
      case PmMode.continuous:
        return 'ทำซ้ำตามความถี่ไปเรื่อยๆ ไม่มีวันจบ';
      case PmMode.yearlyRounds:
        return 'ทำครบรอบแล้วเว้นยาว กลับมาเริ่มใหม่วันเดิมปีหน้า';
      case PmMode.limitedCount:
        return 'ทำครบจำนวนครั้งแล้วจบ นัดวันเองทีละครั้ง';
    }
  }
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
      'triweekly': 'week3',
      'monthly': 'month1',
      'bimonthly': 'month2',
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

  /// Map enum back to the DB-accepted value
  String get toDbValue {
    switch (this) {
      case PmFrequency.week1:
        return 'weekly';
      case PmFrequency.week2:
        return 'biweekly';
      case PmFrequency.week3:
        return 'triweekly';
      case PmFrequency.month1:
        return 'monthly';
      case PmFrequency.month2:
        return 'bimonthly';
      case PmFrequency.month3:
        return 'quarterly';
      case PmFrequency.month4:
        return 'month4';
      case PmFrequency.month5:
        return 'month5';
      case PmFrequency.month6:
        return 'semiannual';
      case PmFrequency.month7:
        return 'month7';
      case PmFrequency.month8:
        return 'month8';
      case PmFrequency.month9:
        return 'month9';
      case PmFrequency.month10:
        return 'month10';
      case PmFrequency.month11:
        return 'month11';
      case PmFrequency.month12:
        return 'annual';
    }
  }

  /// จำนวนเดือนของความถี่ — null ถ้าเป็นความถี่แบบสัปดาห์
  int? get months {
    switch (this) {
      case PmFrequency.week1:
      case PmFrequency.week2:
      case PmFrequency.week3:
        return null;
      case PmFrequency.month1:
        return 1;
      case PmFrequency.month2:
        return 2;
      case PmFrequency.month3:
        return 3;
      case PmFrequency.month4:
        return 4;
      case PmFrequency.month5:
        return 5;
      case PmFrequency.month6:
        return 6;
      case PmFrequency.month7:
        return 7;
      case PmFrequency.month8:
        return 8;
      case PmFrequency.month9:
        return 9;
      case PmFrequency.month10:
        return 10;
      case PmFrequency.month11:
        return 11;
      case PmFrequency.month12:
        return 12;
    }
  }

  /// จำนวนวันของความถี่แบบสัปดาห์ — null ถ้าเป็นความถี่แบบเดือน
  int? get weekDays {
    switch (this) {
      case PmFrequency.week1:
        return 7;
      case PmFrequency.week2:
        return 14;
      case PmFrequency.week3:
        return 21;
      default:
        return null;
    }
  }

  /// จำนวนรอบต่อปีสูงสุดที่เป็นไปได้ เช่น ทุก 3 เดือน → ได้ไม่เกิน 4 รอบ/ปี
  /// (ความถี่แบบสัปดาห์ไม่ใช้ระบบรอบต่อปี จึงคืน 0)
  int get maxRoundsPerYear {
    final m = months;
    if (m == null) return 0;
    return 12 ~/ m;
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
