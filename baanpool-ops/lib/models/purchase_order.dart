/// PurchaseOrder model — maps to `purchase_orders` table
class PurchaseOrderItem {
  final String name;
  final int qty;
  final double unitPrice;

  const PurchaseOrderItem({
    required this.name,
    required this.qty,
    required this.unitPrice,
  });

  double get total => qty * unitPrice;

  Map<String, dynamic> toJson() => {
    'name': name,
    'qty': qty,
    'unit_price': unitPrice,
  };

  factory PurchaseOrderItem.fromJson(Map<String, dynamic> json) =>
      PurchaseOrderItem(
        name: json['name'] as String? ?? '',
        qty: (json['qty'] as num?)?.toInt() ?? 1,
        unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      );

  PurchaseOrderItem copyWith({String? name, int? qty, double? unitPrice}) =>
      PurchaseOrderItem(
        name: name ?? this.name,
        qty: qty ?? this.qty,
        unitPrice: unitPrice ?? this.unitPrice,
      );
}

enum POStatus {
  pending,
  approved,
  ordered,
  received,
  cancelled;

  String get displayName {
    switch (this) {
      case POStatus.pending:
        return 'รอ CEO อนุมัติ';
      case POStatus.approved:
        return 'PO ที่ได้รับ';
      case POStatus.ordered:
        return 'กำลังดำเนินการ';
      case POStatus.received:
        return 'รับของแล้ว';
      case POStatus.cancelled:
        return 'ยกเลิก';
    }
  }

  static POStatus fromString(String s) {
    switch (s) {
      case 'approved':
        return POStatus.approved;
      case 'ordered':
        return POStatus.ordered;
      case 'received':
        return POStatus.received;
      case 'cancelled':
        return POStatus.cancelled;
      default:
        return POStatus.pending;
    }
  }
}

class PurchaseOrder {
  final String id;
  final String title;
  final String? description;
  final String? propertyId;
  final String? createdBy;
  final String? createdByName;
  final String? poAssignedTo;
  final String? poAssignedToName;
  final POStatus status;
  final List<PurchaseOrderItem> items;
  final double totalPrice;
  final String? notes;
  final String? receiptImageUrl;
  final List<String> receiptImageUrls;
  final bool isSelfPurchase;
  final bool isEmergencyPurchase;
  final String? emergencyReason;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PurchaseOrder({
    required this.id,
    required this.title,
    this.description,
    this.propertyId,
    this.createdBy,
    this.createdByName,
    this.poAssignedTo,
    this.poAssignedToName,
    required this.status,
    this.items = const [],
    this.totalPrice = 0,
    this.notes,
    this.receiptImageUrl,
    this.receiptImageUrls = const [],
    this.isSelfPurchase = false,
    this.isEmergencyPurchase = false,
    this.emergencyReason,
    required this.createdAt,
    required this.updatedAt,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    List<PurchaseOrderItem> itemList = [];
    if (rawItems is List) {
      itemList = rawItems
          .map((e) => PurchaseOrderItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return PurchaseOrder(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      propertyId: json['property_id'] as String?,
      createdBy: json['created_by'] as String?,
      createdByName: (json['creator'] is Map)
          ? json['creator']['full_name'] as String?
          : null,
      poAssignedTo: json['po_assigned_to'] as String?,
      poAssignedToName: (json['assignee'] is Map)
          ? json['assignee']['full_name'] as String?
          : null,
      status: POStatus.fromString(json['status'] as String? ?? 'pending'),
      items: itemList,
      totalPrice: (json['total_price'] as num?)?.toDouble() ?? 0,
      notes: json['notes'] as String?,
      receiptImageUrl: json['receipt_image_url'] as String?,
      receiptImageUrls: (json['receipt_image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      isSelfPurchase: json['is_self_purchase'] as bool? ?? false,
      isEmergencyPurchase: json['is_emergency_purchase'] as bool? ?? false,
      emergencyReason: json['emergency_reason'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'property_id': propertyId,
    'created_by': createdBy,
    'po_assigned_to': poAssignedTo,
    'status': status.name,
    'items': items.map((e) => e.toJson()).toList(),
    'total_price': totalPrice,
    'notes': notes,
    'receipt_image_url': receiptImageUrl,
    'receipt_image_urls': receiptImageUrls,
    'is_self_purchase': isSelfPurchase,
    'is_emergency_purchase': isEmergencyPurchase,
    'emergency_reason': emergencyReason,
  };
}
