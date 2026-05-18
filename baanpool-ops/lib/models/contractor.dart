/// Contractor model — maps to `contractors` table in Supabase
/// ช่างภายนอก / ผู้รับเหมา
class Contractor {
  final String id;
  final String name;
  final String? phone;
  final String? email;
  final String? specialty; // คุณสมบัติ เช่น ไฟฟ้า, ประปา, แอร์, ทั่วไป
  final String? companyName;
  final String? notes;
  final String? zone; // พื้นที่ เช่น บางแสน, พัทยา, ทั่วไป
  final int? rating; // 1-5
  final bool isActive;
  final DateTime createdAt;
  final double? price; // ราคา/อัตราค่าบริการ
  final String? category; // หมวดหมู่ เช่น งานช่าง, งานทั่วไป, ร้านอาหาร

  const Contractor({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.specialty,
    this.companyName,
    this.notes,
    this.zone,
    this.rating,
    this.isActive = true,
    required this.createdAt,
    this.price,
    this.category,
  });

  factory Contractor.fromJson(Map<String, dynamic> json) {
    return Contractor(
      id: json['id'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      specialty: json['specialty'] as String?,
      companyName: json['company_name'] as String?,
      notes: json['notes'] as String?,
      zone: json['zone'] as String?,
      rating: json['rating'] as int?,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      price: (json['price'] as num?)?.toDouble(),
      category: json['category'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'email': email,
    'specialty': specialty,
    'company_name': companyName,
    'notes': notes,
    'zone': zone,
    'rating': rating,
    'is_active': isActive,
    'price': price,
    'category': category,
  };
}

/// Contractor History — ประวัติงานช่างภายนอก
class ContractorHistory {
  final String id;
  final String contractorId;
  final String? workOrderId;
  final String? propertyId;
  final String? description;
  final double? amount;
  final DateTime? workDate;
  final int? rating;
  final String? notes;
  final DateTime createdAt;

  // Joined fields
  final String? workOrderTitle;
  final String? propertyName;

  const ContractorHistory({
    required this.id,
    required this.contractorId,
    this.workOrderId,
    this.propertyId,
    this.description,
    this.amount,
    this.workDate,
    this.rating,
    this.notes,
    required this.createdAt,
    this.workOrderTitle,
    this.propertyName,
  });

  factory ContractorHistory.fromJson(Map<String, dynamic> json) {
    String? woTitle;
    if (json['work_orders'] is Map) {
      woTitle = json['work_orders']['title'] as String?;
    }
    String? propName;
    if (json['properties'] is Map) {
      propName = json['properties']['name'] as String?;
    }

    return ContractorHistory(
      id: json['id'] as String,
      contractorId: json['contractor_id'] as String,
      workOrderId: json['work_order_id'] as String?,
      propertyId: json['property_id'] as String?,
      description: json['description'] as String?,
      amount: json['amount'] != null
          ? (json['amount'] as num).toDouble()
          : null,
      workDate: json['work_date'] != null
          ? DateTime.parse(json['work_date'] as String)
          : null,
      rating: json['rating'] as int?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      workOrderTitle: woTitle,
      propertyName: propName,
    );
  }

  Map<String, dynamic> toJson() => {
    'contractor_id': contractorId,
    'work_order_id': workOrderId,
    'property_id': propertyId,
    'description': description,
    'amount': amount,
    'work_date': workDate?.toIso8601String().split('T').first,
    'rating': rating,
    'notes': notes,
  };
}
