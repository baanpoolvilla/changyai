import '../utils/thai_datetime.dart';

/// WorkOrderComment model — maps to `work_order_comments` table in Supabase
class WorkOrderComment {
  final String id;
  final String workOrderId;
  final String? userId;
  final String? userName; // joined from users table
  final String content;
  final DateTime createdAt;

  const WorkOrderComment({
    required this.id,
    required this.workOrderId,
    this.userId,
    this.userName,
    required this.content,
    required this.createdAt,
  });

  factory WorkOrderComment.fromJson(Map<String, dynamic> json) {
    String? uName;
    if (json['user'] is Map) {
      uName = json['user']['full_name'] as String?;
    }
    return WorkOrderComment(
      id: json['id'] as String,
      workOrderId: json['work_order_id'] as String,
      userId: json['user_id'] as String?,
      userName: uName,
      content: json['content'] as String,
      createdAt: parseServerTimestampToThai(json['created_at'] as String),
    );
  }
}
