import '../utils/thai_datetime.dart';

/// WorkOrder model — maps to `work_orders` table in Supabase
class WorkOrder {
  final String id;
  final String propertyId;
  final String? assetId;
  final String? assignedTo; // user id of technician
  final String? createdBy; // user id who created the work order
  final String? createdByName; // joined from users table
  final String title;
  final String? description;
  final WorkOrderStatus status;
  final WorkOrderPriority priority;
  final DateTime? dueDate;
  final DateTime? completedAt;
  final String? completionNotes;
  final List<String> photoUrls;
  final List<String> afterPhotoUrls;
  final List<String> ccUserIds;
  final List<String> additionalPropertyIds;
  final String? pmScheduleId;
  final DateTime createdAt;

  const WorkOrder({
    required this.id,
    required this.propertyId,
    this.assetId,
    this.assignedTo,
    this.createdBy,
    this.createdByName,
    required this.title,
    this.description,
    required this.status,
    required this.priority,
    this.dueDate,
    this.completedAt,
    this.completionNotes,
    this.photoUrls = const [],
    this.afterPhotoUrls = const [],
    this.ccUserIds = const [],
    this.additionalPropertyIds = const [],
    this.pmScheduleId,
    required this.createdAt,
  });

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    // Handle joined creator data
    String? creatorName;
    if (json['creator'] is Map) {
      creatorName = json['creator']['full_name'] as String?;
    }
    return WorkOrder(
      id: json['id'] as String,
      propertyId: json['property_id'] as String,
      assetId: json['asset_id'] as String?,
      assignedTo: json['assigned_to'] as String?,
      createdBy: json['created_by'] as String?,
      createdByName: creatorName,
      title: json['title'] as String,
      description: json['description'] as String?,
      status: WorkOrderStatus.fromString(json['status'] as String),
      priority: WorkOrderPriority.fromString(json['priority'] as String),
      dueDate: json['due_date'] != null
          ? parseServerTimestampToThai(json['due_date'] as String)
          : null,
      completedAt: json['completed_at'] != null
          ? parseServerTimestampToThai(json['completed_at'] as String)
          : null,
      completionNotes: json['completion_notes'] as String?,
      photoUrls:
          (json['photo_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      afterPhotoUrls:
          (json['after_photo_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      ccUserIds:
          (json['cc_user_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      additionalPropertyIds:
          (json['additional_property_ids'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      pmScheduleId: json['pm_schedule_id'] as String?,
      createdAt: parseServerTimestampToThai(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'property_id': propertyId,
    'asset_id': assetId,
    'assigned_to': assignedTo,
    'title': title,
    'description': description,
    'status': status.name,
    'priority': priority.name,
    'due_date': dueDate?.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'completion_notes': completionNotes,
    'photo_urls': photoUrls,
    if (ccUserIds.isNotEmpty) 'cc_user_ids': ccUserIds,
    if (additionalPropertyIds.isNotEmpty)
      'additional_property_ids': additionalPropertyIds,
  };

  bool get isOverdue =>
      dueDate != null &&
      dueDate!.isBefore(thaiNow()) &&
      status != WorkOrderStatus.completed;
}

enum WorkOrderStatus {
  open,
  inProgress,
  completed,
  cancelled;

  static WorkOrderStatus fromString(String value) {
    switch (value) {
      case 'in_progress':
        return WorkOrderStatus.inProgress;
      default:
        return WorkOrderStatus.values.firstWhere(
          (e) => e.name == value,
          orElse: () => WorkOrderStatus.open,
        );
    }
  }

  String get displayName {
    switch (this) {
      case WorkOrderStatus.open:
        return 'เปิด';
      case WorkOrderStatus.inProgress:
        return 'กำลังดำเนินการ';
      case WorkOrderStatus.completed:
        return 'เสร็จแล้ว';
      case WorkOrderStatus.cancelled:
        return 'ยกเลิก';
    }
  }
}

enum WorkOrderPriority {
  low,
  medium,
  high,
  urgent;

  static WorkOrderPriority fromString(String value) {
    return WorkOrderPriority.values.firstWhere(
      (e) => e.name == value,
      orElse: () => WorkOrderPriority.medium,
    );
  }

  String get displayName {
    switch (this) {
      case WorkOrderPriority.low:
        return 'ต่ำ';
      case WorkOrderPriority.medium:
        return 'ปานกลาง';
      case WorkOrderPriority.high:
        return 'สูง';
      case WorkOrderPriority.urgent:
        return 'เร่งด่วน';
    }
  }
}
