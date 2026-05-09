import '../utils/thai_datetime.dart';

/// Expense model — maps to `expenses` table in Supabase
class Expense {
  final String id;
  final String? workOrderId;
  final String? pmScheduleId;
  final String? propertyId;
  final double amount;
  final String? description;
  final String? category; // material, labor, contractor, etc.
  final String? receiptUrl;
  final bool billableToPartner;
  final ExpenseCostType costType; // work_order or pm
  final ExpensePaidBy paidBy; // company or owner
  final DateTime expenseDate;
  final DateTime createdAt;
  final bool isNoExpense;
  final String? createdByName; // joined from users table

  const Expense({
    required this.id,
    this.workOrderId,
    this.pmScheduleId,
    this.propertyId,
    required this.amount,
    this.description,
    this.category,
    this.receiptUrl,
    this.billableToPartner = false,
    this.costType = ExpenseCostType.workOrder,
    this.paidBy = ExpensePaidBy.company,
    required this.expenseDate,
    required this.createdAt,
    this.isNoExpense = false,
    this.createdByName,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    String? creatorName;
    if (json['creator'] is Map) {
      creatorName = json['creator']['full_name'] as String?;
    }
    return Expense(
      id: json['id'] as String,
      workOrderId: json['work_order_id'] as String?,
      pmScheduleId: json['pm_schedule_id'] as String?,
      propertyId: json['property_id'] as String?,
      amount: (json['amount'] as num).toDouble(),
      description: json['description'] as String?,
      category: json['category'] as String?,
      receiptUrl: json['receipt_url'] as String?,
      billableToPartner: json['billable_to_partner'] as bool? ?? false,
      costType: ExpenseCostType.fromString(json['cost_type'] as String?),
      paidBy: ExpensePaidBy.fromString(json['paid_by'] as String?),
      expenseDate: DateTime.parse(json['expense_date'] as String),
      createdAt: parseServerTimestampToThai(json['created_at'] as String),
      isNoExpense: json['is_no_expense'] as bool? ?? false,
      createdByName: creatorName,
    );
  }

  Map<String, dynamic> toJson() => {
    if (workOrderId != null) 'work_order_id': workOrderId,
    if (pmScheduleId != null) 'pm_schedule_id': pmScheduleId,
    'property_id': propertyId,
    'amount': amount,
    'description': description,
    'category': category,
    'receipt_url': receiptUrl,
    'billable_to_partner': billableToPartner,
    'cost_type': costType.value,
    'paid_by': paidBy.value,
    'expense_date': expenseDate.toIso8601String(),
    'is_no_expense': isNoExpense,
  };
}

/// ประเภทค่าใช้จ่าย: ใบงาน หรือ PM
enum ExpenseCostType {
  workOrder('work_order'),
  pm('pm');

  final String value;
  const ExpenseCostType(this.value);

  static ExpenseCostType fromString(String? v) {
    if (v == 'pm') return ExpenseCostType.pm;
    return ExpenseCostType.workOrder;
  }

  String get displayName {
    switch (this) {
      case ExpenseCostType.workOrder:
        return 'ใบงาน';
      case ExpenseCostType.pm:
        return 'PM (บำรุงรักษา)';
    }
  }
}

/// รับผิดชอบโดย: บริษัท หรือ เจ้าของบ้าน
enum ExpensePaidBy {
  company('company'),
  owner('owner');

  final String value;
  const ExpensePaidBy(this.value);

  static ExpensePaidBy fromString(String? v) {
    if (v == 'owner') return ExpensePaidBy.owner;
    return ExpensePaidBy.company;
  }

  String get displayName {
    switch (this) {
      case ExpensePaidBy.company:
        return 'บริษัท';
      case ExpensePaidBy.owner:
        return 'เจ้าของบ้าน';
    }
  }
}
