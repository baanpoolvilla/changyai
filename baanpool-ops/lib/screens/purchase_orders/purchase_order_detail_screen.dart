import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/purchase_order.dart';
import '../../models/user.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_state_service.dart';
import '../../utils/thai_datetime.dart';

class PurchaseOrderDetailScreen extends StatefulWidget {
  final String orderId;
  const PurchaseOrderDetailScreen({super.key, required this.orderId});

  @override
  State<PurchaseOrderDetailScreen> createState() =>
      _PurchaseOrderDetailScreenState();
}

class _PurchaseOrderDetailScreenState
    extends State<PurchaseOrderDetailScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  final _authState = AuthStateService();

  PurchaseOrder? _order;
  bool _loading = true;
  bool _actionLoading = false;
  String _propertyName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getPurchaseOrder(widget.orderId);
      final po = PurchaseOrder.fromJson(data);
      String propName = '';
      if (po.propertyId != null) {
        final props = await _service.getPropertyNamesOnly();
        propName = props
            .firstWhere(
              (p) => p['id'] == po.propertyId,
              orElse: () => {'name': ''},
            )['name'] as String;
      }
      if (mounted) {
        setState(() {
          _order = po;
          _propertyName = propName;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('โหลดล้มเหลว: $e')));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _actionLoading = true);
    try {
      await _service.updatePurchaseOrder(widget.orderId, {
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      });
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('อัพเดตล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _actionLoading = false);
  }

  /// CEO อนุมัติ PR → กรอกราคา + เลือกคนรับ PO (normal) หรือข้าม→ received (emergency)
  Future<void> _approveWithPricing() async {
    if (_order == null) return;
    final items = _order!.items;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีรายการอุปกรณ์')),
      );
      return;
    }

    final isEmergency = _order!.isEmergencyPurchase;

    // โหลด users สำหรับเลือก PO assignee (เฉพาะ normal flow)
    List<Map<String, dynamic>> allUsers = [];
    if (!isEmergency) {
      try {
        allUsers = await _service.getUsers();
      } catch (_) {}
    }

    if (!mounted) return;

    final qtyControllers =
        items.map((_) => TextEditingController(text: '1')).toList();
    final priceControllers =
        items.map((_) => TextEditingController()).toList();
    String? selectedAssigneeId;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          double total = 0;
          for (int i = 0; i < items.length; i++) {
            final qty = int.tryParse(qtyControllers[i].text) ?? 0;
            final price = double.tryParse(priceControllers[i].text) ?? 0;
            total += qty * price;
          }
          return AlertDialog(
            title: Text(isEmergency
                ? 'อนุมัติ PR ฉุกเฉิน'
                : 'อนุมัติ PR และมอบ PO'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Emergency banner
                  if (isEmergency) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.warning_amber,
                                  color: Colors.red.shade700, size: 16),
                              const SizedBox(width: 6),
                              Text(
                                'กรณีฉุกเฉิน — ซื้อของแล้ว',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700,
                                    fontSize: 13),
                              ),
                            ],
                          ),
                          if (_order!.emergencyReason != null &&
                              _order!.emergencyReason!.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'เหตุผล: ${_order!.emergencyReason}',
                              style: TextStyle(
                                  color: Colors.red.shade700, fontSize: 12),
                            ),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'เมื่ออนุมัติจะข้ามไปยัง "เสร็จสิ้น" ทันที',
                            style: TextStyle(
                                color: Colors.red.shade600, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Pricing rows
                  ...items.asMap().entries.map((entry) {
                    final i = entry.key;
                    final item = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: qtyControllers[i],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    labelText: 'จำนวน',
                                    isDense: true,
                                  ),
                                  onChanged: (_) =>
                                      setDialogState(() {}),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: priceControllers[i],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'ราคา/หน่วย (฿)',
                                    isDense: true,
                                  ),
                                  onChanged: (_) =>
                                      setDialogState(() {}),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'รวม: ฿${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),

                  // Assignee dropdown (normal flow only)
                  if (!isEmergency && allUsers.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'มอบหมาย PO ให้',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedAssigneeId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'เลือกผู้รับผิดชอบ',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('— ไม่ระบุ —')),
                        ...allUsers.map((u) => DropdownMenuItem(
                              value: u['id'] as String,
                              child: Text(
                                '${u['full_name']} (${u['role']})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            )),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedAssigneeId = v),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                    backgroundColor:
                        isEmergency ? Colors.red.shade700 : Colors.green),
                child: Text(isEmergency
                    ? 'อนุมัติ (จบงาน)'
                    : 'อนุมัติ & มอบ PO'),
              ),
            ],
          );
        },
      ),
    );

    final capturedQty =
        qtyControllers.map((c) => int.tryParse(c.text) ?? 1).toList();
    final capturedPrice =
        priceControllers.map((c) => double.tryParse(c.text) ?? 0).toList();
    for (final c in [...qtyControllers, ...priceControllers]) {
      c.dispose();
    }

    if (confirmed != true || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      final now = DateTime.now();
      double totalPrice = 0;
      final updatedItems = <Map<String, dynamic>>[];
      for (int i = 0; i < items.length; i++) {
        final qty = capturedQty[i];
        final unitPrice = capturedPrice[i];
        totalPrice += qty * unitPrice;
        updatedItems.add({
          'name': items[i].name,
          'qty': qty,
          'unit_price': unitPrice,
        });
      }

      // Emergency → received, Normal → approved
      final newStatus = isEmergency ? 'received' : 'approved';

      await _service.updatePurchaseOrder(widget.orderId, {
        'status': newStatus,
        'items': updatedItems,
        'total_price': totalPrice,
        if (!isEmergency) 'po_assigned_to': selectedAssigneeId,
        'updated_at': now.toIso8601String(),
      });

      if (totalPrice > 0) {
        await _service.createExpense({
          'property_id': _order!.propertyId,
          'purchase_order_id': widget.orderId,
          'amount': totalPrice,
          'description': 'สั่งซื้ออุปกรณ์: ${_order!.title}',
          'category': 'material',
          'cost_type': 'work_order',
          'paid_by': 'company',
          'billable_to_partner': false,
          'is_no_expense': false,
          'expense_date': now.toIso8601String(),
        });
      }

      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isEmergency
                ? 'อนุมัติ PR ฉุกเฉิน — บันทึกเสร็จสิ้นแล้ว'
                : 'อนุมัติและมอบ PO เรียบร้อย'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('อนุมัติล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _actionLoading = false);
  }

  Future<void> _deletePo() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบ PR/PO'),
        content: Text(
            'ต้องการลบ "${_order!.title}" ใช่หรือไม่?\nไม่สามารถกู้คืนได้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      await _service.deletePurchaseOrder(widget.orderId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบเรียบร้อยแล้ว')),
        );
        context.go('/purchase-orders');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ลบล้มเหลว: $e')));
        setState(() => _actionLoading = false);
      }
    }
  }

  /// อัปโหลดใบเสร็จ → received (ราคาถูกกรอกตอน CEO approve แล้ว)
  Future<void> _uploadReceiptAndReceive() async {
    final picker = ImagePicker();

    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('ถ่ายรูป (กล้อง)'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('เลือกจากคลังภาพ (หลายรูป)'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    List<XFile> pickedFiles = [];
    if (source == 'camera') {
      final xFile =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (xFile != null) pickedFiles = [xFile];
    } else {
      pickedFiles = await picker.pickMultiImage(imageQuality: 80);
    }
    if (pickedFiles.isEmpty || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      final now = DateTime.now();
      final urls = <String>[];
      for (final xFile in pickedFiles) {
        final bytes = await xFile.readAsBytes();
        final ext = xFile.path.split('.').last.toLowerCase();
        final fileName =
            'po_${widget.orderId}_${now.millisecondsSinceEpoch}_${urls.length}.$ext';
        final url = await _service.uploadFile('po-receipts', fileName, bytes);
        urls.add(url);
      }

      final existingUrls = _order?.receiptImageUrls ?? [];
      final allUrls = [...existingUrls, ...urls];

      await _service.updatePurchaseOrder(widget.orderId, {
        'status': 'received',
        'receipt_image_url': allUrls.first,
        'receipt_image_urls': allUrls,
        'updated_at': now.toIso8601String(),
      });
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกการรับของเรียบร้อยแล้ว')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('อัพโหลดล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _actionLoading = false);
  }

  /// [Backward compat] Self-purchase: กรอกราคา + ถ่ายรูป → received
  Future<void> _selfReceiveWithPricing() async {
    if (_order == null) return;
    final items = _order!.items;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีรายการอุปกรณ์')),
      );
      return;
    }

    final picker = ImagePicker();
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('ถ่ายรูป (กล้อง)'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('เลือกจากคลังภาพ (หลายรูป)'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;

    List<XFile> pickedFiles = [];
    if (source == 'camera') {
      final xFile =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (xFile != null) pickedFiles = [xFile];
    } else {
      pickedFiles = await picker.pickMultiImage(imageQuality: 80);
    }
    if (pickedFiles.isEmpty || !mounted) return;

    final qtyControllers =
        items.map((_) => TextEditingController(text: '1')).toList();
    final priceControllers =
        items.map((_) => TextEditingController()).toList();

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          double total = 0;
          for (int i = 0; i < items.length; i++) {
            final qty = int.tryParse(qtyControllers[i].text) ?? 0;
            final price = double.tryParse(priceControllers[i].text) ?? 0;
            total += qty * price;
          }
          return AlertDialog(
            title: const Text('กรอกจำนวนและราคาที่ซื้อมา'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...items.asMap().entries.map((entry) {
                    final i = entry.key;
                    final item = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: qtyControllers[i],
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'จำนวน', isDense: true),
                                  onChanged: (_) =>
                                      setDialogState(() {}),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  controller: priceControllers[i],
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                      labelText: 'ราคา/หน่วย (฿)',
                                      isDense: true),
                                  onChanged: (_) =>
                                      setDialogState(() {}),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'รวม: ฿${total.toStringAsFixed(2)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ยกเลิก'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('บันทึก'),
              ),
            ],
          );
        },
      ),
    );

    final capturedQty =
        qtyControllers.map((c) => int.tryParse(c.text) ?? 1).toList();
    final capturedPrice =
        priceControllers.map((c) => double.tryParse(c.text) ?? 0).toList();
    for (final c in [...qtyControllers, ...priceControllers]) {
      c.dispose();
    }
    if (confirmed != true || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      final now = DateTime.now();
      final urls = <String>[];
      for (final xFile in pickedFiles) {
        final bytes = await xFile.readAsBytes();
        final ext = xFile.path.split('.').last.toLowerCase();
        final fileName =
            'po_${widget.orderId}_${now.millisecondsSinceEpoch}_${urls.length}.$ext';
        final url = await _service.uploadFile('po-receipts', fileName, bytes);
        urls.add(url);
      }

      final existingUrls = _order?.receiptImageUrls ?? [];
      final allUrls = [...existingUrls, ...urls];

      double totalPrice = 0;
      final updatedItems = <Map<String, dynamic>>[];
      for (int i = 0; i < items.length; i++) {
        final qty = capturedQty[i];
        final unitPrice = capturedPrice[i];
        totalPrice += qty * unitPrice;
        updatedItems.add({
          'name': items[i].name,
          'qty': qty,
          'unit_price': unitPrice,
        });
      }

      await _service.updatePurchaseOrder(widget.orderId, {
        'status': 'received',
        'receipt_image_url': allUrls.first,
        'receipt_image_urls': allUrls,
        'items': updatedItems,
        'total_price': totalPrice,
        'updated_at': now.toIso8601String(),
      });

      if (totalPrice > 0) {
        await _service.createExpense({
          'property_id': _order!.propertyId,
          'purchase_order_id': widget.orderId,
          'amount': totalPrice,
          'description': 'สั่งซื้ออุปกรณ์ (ซื้อเอง): ${_order!.title}',
          'category': 'material',
          'cost_type': 'work_order',
          'paid_by': 'company',
          'billable_to_partner': false,
          'is_no_expense': false,
          'expense_date': now.toIso8601String(),
        });
      }

      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกการรับของเรียบร้อยแล้ว')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('บันทึกล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _actionLoading = false);
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('รูปใบเสร็จ'),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = _authState.currentRole;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isCeo = role == UserRole.owner || role == UserRole.admin;
    final isAdmin = role == UserRole.admin;

    // ผู้ที่รับผิดชอบ PO นี้ (จาก po_assigned_to หรือ creator สำหรับ self-purchase)
    final isAssignedUser = currentUserId != null &&
        (_order?.poAssignedTo == currentUserId ||
            (_order?.isSelfPurchase == true &&
                _order?.createdBy == currentUserId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายละเอียด PR/PO'),
        actions: [
          if (isAdmin && _order != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'ลบ',
              onPressed: _actionLoading ? null : _deletePo,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _order == null
              ? const Center(child: Text('ไม่พบข้อมูล'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ─── Header Card ────────────────────────────
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _order!.title,
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _StatusChip(_order!.status),
                                  // Emergency badge
                                  if (_order!.isEmergencyPurchase) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.red.shade50,
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.red.shade200),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.warning_amber,
                                              size: 12,
                                              color: Colors.red.shade700),
                                          const SizedBox(width: 4),
                                          Text('ฉุกเฉิน',
                                              style: TextStyle(
                                                  color:
                                                      Colors.red.shade700,
                                                  fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                  ],
                                  // Legacy self-purchase badge
                                  if (_order!.isSelfPurchase &&
                                      !_order!.isEmergencyPurchase) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.green
                                            .withValues(alpha: 0.12),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        border: Border.all(
                                            color: Colors.green
                                                .withValues(alpha: 0.35)),
                                      ),
                                      child: const Text('ซื้อเอง',
                                          style: TextStyle(
                                              color: Colors.green,
                                              fontSize: 11)),
                                    ),
                                  ],
                                ],
                              ),

                              // Emergency reason
                              if (_order!.isEmergencyPurchase &&
                                  _order!.emergencyReason != null &&
                                  _order!.emergencyReason!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius:
                                        BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.red.shade100),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.info_outline,
                                          size: 14,
                                          color: Colors.red.shade700),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          'เหตุผลฉุกเฉิน: ${_order!.emergencyReason}',
                                          style: TextStyle(
                                              color: Colors.red.shade700,
                                              fontSize: 12),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              if (_propertyName.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.home_outlined,
                                        size: 14, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Text(_propertyName,
                                        style: theme.textTheme.bodyMedium
                                            ?.copyWith(
                                                color: theme.colorScheme
                                                    .outline)),
                                  ],
                                ),
                              ],

                              // Assigned user
                              if (_order!.poAssignedToName != null &&
                                  _order!.poAssignedToName!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(
                                        Icons.assignment_ind_outlined,
                                        size: 14,
                                        color: Colors.blue),
                                    const SizedBox(width: 4),
                                    Text(
                                      'ผู้รับ PO: ${_order!.poAssignedToName}',
                                      style: theme.textTheme.bodyMedium
                                          ?.copyWith(
                                              color:
                                                  Colors.blue.shade700),
                                    ),
                                  ],
                                ),
                              ],

                              if (_order!.description != null &&
                                  _order!.description!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(_order!.description!,
                                    style: theme.textTheme.bodyMedium),
                              ],
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  const Icon(Icons.person_outline,
                                      size: 13, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(
                                    'เปิด PR โดย: ${_order!.createdByName ?? 'ไม่ทราบ'}',
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(
                                            color:
                                                theme.colorScheme.outline),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'สร้างเมื่อ ${formatThaiDate(_order!.createdAt)}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ─── Items Table ─────────────────────────────
                      if (_order!.items.isNotEmpty) ...[
                        Text('รายการอุปกรณ์',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: (_order!.status == POStatus.pending ||
                                    (_order!.isSelfPurchase &&
                                        _order!.status ==
                                            POStatus.ordered &&
                                        _order!.totalPrice == 0))
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _order!.isSelfPurchase
                                            ? 'กรอกราคาตอนรับของ'
                                            : 'รอ CEO กรอกราคาและจำนวนตอนอนุมัติ',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: theme.colorScheme
                                                    .outline),
                                      ),
                                      const SizedBox(height: 8),
                                      ..._order!.items.map(
                                        (item) => Padding(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 4),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.circle,
                                                  size: 6,
                                                  color: Colors.grey),
                                              const SizedBox(width: 8),
                                              Text(item.name),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                              flex: 4,
                                              child: Text('ชื่อ',
                                                  style: theme.textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight
                                                                  .bold))),
                                          Expanded(
                                              flex: 2,
                                              child: Text('จำนวน',
                                                  textAlign:
                                                      TextAlign.center,
                                                  style: theme.textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight
                                                                  .bold))),
                                          Expanded(
                                              flex: 3,
                                              child: Text('ราคา/หน่วย',
                                                  textAlign:
                                                      TextAlign.right,
                                                  style: theme.textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight
                                                                  .bold))),
                                          Expanded(
                                              flex: 3,
                                              child: Text('รวม',
                                                  textAlign:
                                                      TextAlign.right,
                                                  style: theme.textTheme
                                                      .labelMedium
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight
                                                                  .bold))),
                                        ],
                                      ),
                                      const Divider(),
                                      ..._order!.items.map(
                                        (item) => Padding(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 4),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                  flex: 4,
                                                  child:
                                                      Text(item.name)),
                                              Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                      '${item.qty}',
                                                      textAlign: TextAlign
                                                          .center)),
                                              Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                      '฿${item.unitPrice.toStringAsFixed(2)}',
                                                      textAlign: TextAlign
                                                          .right)),
                                              Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                      '฿${item.total.toStringAsFixed(2)}',
                                                      textAlign: TextAlign
                                                          .right)),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const Divider(),
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          Text(
                                            'รวม: ฿${_order!.totalPrice.toStringAsFixed(2)}',
                                            style: theme
                                                .textTheme.titleSmall
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.bold,
                                                    color: theme
                                                        .colorScheme
                                                        .primary),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ─── Notes ───────────────────────────────────
                      if (_order!.notes != null &&
                          _order!.notes!.isNotEmpty) ...[
                        Text('หมายเหตุ',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(_order!.notes!),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ─── Receipt Photos ───────────────────────────
                      if (_order!.receiptImageUrls.isNotEmpty ||
                          _order!.receiptImageUrl != null) ...[
                        Text('รูปใบเสร็จ',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 150,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              ...(_order!.receiptImageUrls.isNotEmpty
                                      ? _order!.receiptImageUrls
                                      : [
                                          if (_order!.receiptImageUrl !=
                                              null)
                                            _order!.receiptImageUrl!
                                        ])
                                  .map((url) => Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: GestureDetector(
                                          onTap: () =>
                                              _showFullImage(context, url),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: Image.network(
                                              url,
                                              width: 150,
                                              height: 150,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) =>
                                                  const SizedBox(
                                                width: 150,
                                                height: 150,
                                                child: Center(
                                                    child: Icon(
                                                        Icons.broken_image)),
                                              ),
                                            ),
                                          ),
                                        ),
                                      )),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ─── Action Buttons ───────────────────────────
                      if (_actionLoading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        // [1] CEO: อนุมัติ / ปฏิเสธ PR
                        if (isCeo && _order!.status == POStatus.pending) ...[
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _approveWithPricing,
                                  icon: const Icon(Icons.check),
                                  label: Text(_order!.isEmergencyPurchase
                                      ? 'อนุมัติ (ฉุกเฉิน)'
                                      : 'อนุมัติ & มอบ PO'),
                                  style: FilledButton.styleFrom(
                                      backgroundColor:
                                          _order!.isEmergencyPurchase
                                              ? Colors.red.shade700
                                              : Colors.green),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () =>
                                      _updateStatus('cancelled'),
                                  icon: const Icon(Icons.close),
                                  label: const Text('ปฏิเสธ'),
                                  style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        ],

                        // [2] ผู้รับ PO หรือ CEO: ยืนยันดำเนินการ (approved → ordered)
                        if (_order!.status == POStatus.approved &&
                            !_order!.isSelfPurchase &&
                            (isCeo || isAssignedUser)) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _updateStatus('ordered'),
                              icon: const Icon(Icons.local_shipping_outlined),
                              label: const Text('ยืนยันดำเนินการ — ไปซื้อของแล้ว'),
                            ),
                          ),
                        ],

                        // [3] ผู้รับ PO หรือ CEO: รับของ + ถ่ายรูปใบเสร็จ (ordered → received)
                        if (_order!.status == POStatus.ordered &&
                            !_order!.isSelfPurchase &&
                            (isCeo || isAssignedUser)) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _uploadReceiptAndReceive,
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('รับของและถ่ายรูปใบเสร็จ'),
                            ),
                          ),
                        ],

                        // [4] [Backward compat] Self-purchase (ordered)
                        if (_order!.isSelfPurchase &&
                            _order!.status == POStatus.ordered) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _order!.totalPrice == 0
                                  ? _selfReceiveWithPricing
                                  : _uploadReceiptAndReceive,
                              icon: const Icon(Icons.shopping_bag),
                              label: Text(_order!.totalPrice == 0
                                  ? 'รับของ → ถ่ายรูป + กรอกราคา'
                                  : 'รับของและถ่ายรูปใบเสร็จ'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.green.shade700),
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final POStatus status;
  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(status.displayName,
          style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Color _color(POStatus s) {
    switch (s) {
      case POStatus.pending:
        return Colors.orange;
      case POStatus.approved:
        return Colors.blue;
      case POStatus.ordered:
        return Colors.indigo;
      case POStatus.received:
        return Colors.green;
      case POStatus.cancelled:
        return Colors.grey;
    }
  }
}
