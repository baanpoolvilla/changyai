/// EquipmentReturn model — maps to `equipment_returns` table.
/// แจ้ง "คืนของ / ของมีปัญหา" ที่ผูกกับ PurchaseOrder เดิม
enum ReturnProblemType {
  defective,
  wrong,
  damaged,
  missing,
  other;

  String get displayName {
    switch (this) {
      case ReturnProblemType.defective:
        return 'ชำรุด / ใช้งานไม่ได้';
      case ReturnProblemType.wrong:
        return 'ผิดรุ่น / ผิดสเปก';
      case ReturnProblemType.damaged:
        return 'แตกหักระหว่างส่ง';
      case ReturnProblemType.missing:
        return 'ของขาด / ไม่ครบ';
      case ReturnProblemType.other:
        return 'อื่น ๆ';
    }
  }

  static ReturnProblemType fromString(String? s) {
    return ReturnProblemType.values.firstWhere(
      (e) => e.name == s,
      orElse: () => ReturnProblemType.other,
    );
  }
}

enum ReturnStatus {
  pending,
  processing,
  resolved,
  cancelled;

  String get displayName {
    switch (this) {
      case ReturnStatus.pending:
        return 'รอดำเนินการ';
      case ReturnStatus.processing:
        return 'กำลังดำเนินการ';
      case ReturnStatus.resolved:
        return 'จบเรื่องแล้ว';
      case ReturnStatus.cancelled:
        return 'ยกเลิก';
    }
  }

  static ReturnStatus fromString(String? s) {
    return ReturnStatus.values.firstWhere(
      (e) => e.name == s,
      orElse: () => ReturnStatus.pending,
    );
  }
}

class EquipmentReturn {
  final String id;
  final String purchaseOrderId;
  final String? poTitle;
  final String? propertyId;
  final String? itemName;
  final int qty;
  final ReturnProblemType problemType;
  final String reason;
  final ReturnStatus status;
  final List<String> imageUrls;
  final String? resolutionNote;
  final String? createdBy;
  final String? createdByName;
  final String? resolvedBy;
  final String? resolvedByName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? resolvedAt;

  const EquipmentReturn({
    required this.id,
    required this.purchaseOrderId,
    this.poTitle,
    this.propertyId,
    this.itemName,
    this.qty = 1,
    this.problemType = ReturnProblemType.other,
    required this.reason,
    this.status = ReturnStatus.pending,
    this.imageUrls = const [],
    this.resolutionNote,
    this.createdBy,
    this.createdByName,
    this.resolvedBy,
    this.resolvedByName,
    required this.createdAt,
    required this.updatedAt,
    this.resolvedAt,
  });

  factory EquipmentReturn.fromJson(Map<String, dynamic> json) {
    return EquipmentReturn(
      id: json['id'] as String,
      purchaseOrderId: json['purchase_order_id'] as String,
      poTitle: (json['purchase_order'] is Map)
          ? json['purchase_order']['title'] as String?
          : null,
      propertyId: json['property_id'] as String?,
      itemName: json['item_name'] as String?,
      qty: (json['qty'] as num?)?.toInt() ?? 1,
      problemType: ReturnProblemType.fromString(json['problem_type'] as String?),
      reason: json['reason'] as String? ?? '',
      status: ReturnStatus.fromString(json['status'] as String?),
      imageUrls: (json['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      resolutionNote: json['resolution_note'] as String?,
      createdBy: json['created_by'] as String?,
      createdByName: (json['creator'] is Map)
          ? json['creator']['full_name'] as String?
          : null,
      resolvedBy: json['resolved_by'] as String?,
      resolvedByName: (json['resolver'] is Map)
          ? json['resolver']['full_name'] as String?
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      resolvedAt: json['resolved_at'] != null
          ? DateTime.parse(json['resolved_at'] as String)
          : null,
    );
  }
}
