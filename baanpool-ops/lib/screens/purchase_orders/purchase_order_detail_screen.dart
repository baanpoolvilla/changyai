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

  /// CEO กดอนุมัติ → dialog กรอกจำนวน+ราคา → บันทึก expense
  Future<void> _approveWithPricing() async {
    if (_order == null) return;
    final items = _order!.items;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีรายการอุปกรณ์')),
      );
      return;
    }

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
            title: const Text('กรอกจำนวนและราคา'),
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
                                    labelText: 'จำนวน',
                                    isDense: true,
                                  ),
                                  onChanged: (_) => setDialogState(() {}),
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
                                  onChanged: (_) => setDialogState(() {}),
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
                child: const Text('อนุมัติ'),
              ),
            ],
          );
        },
      ),
    );

    // capture values before disposing
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

      await _service.updatePurchaseOrder(widget.orderId, {
        'status': 'approved',
        'items': updatedItems,
        'total_price': totalPrice,
        'updated_at': now.toIso8601String(),
      });

      if (totalPrice > 0) {
        await _service.createExpense({
          'property_id': _order!.propertyId,
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
          const SnackBar(
              content: Text('อนุมัติแล้ว และบันทึกค่าใช้จ่ายเรียบร้อย')),
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
        title: const Text('ลบคำสั่งซื้อ'),
        content: Text('ต้องการลบ "${_order!.title}" ใช่หรือไม่?\nไม่สามารถกู้คืนได้'),
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
          const SnackBar(content: Text('ลบคำสั่งซื้อเรียบร้อยแล้ว')),
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

  Future<void> _uploadReceiptAndReceive() async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    if (xFile == null) return;

    setState(() => _actionLoading = true);
    try {
      final bytes = await xFile.readAsBytes();
      final ext = xFile.path.split('.').last.toLowerCase();
      final fileName =
          'po_${widget.orderId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final url = await _service.uploadFile('po-receipts', fileName, bytes);

      await _service.updatePurchaseOrder(widget.orderId, {
        'status': 'received',
        'receipt_image_url': url,
        'updated_at': DateTime.now().toIso8601String(),
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

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('\u0e23\u0e39\u0e1b\u0e43\u0e1a\u0e40\u0e2a\u0e23\u0e47\u0e08'),
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
    final isCreator = _order?.createdBy == currentUserId;

    final isAdmin = role == UserRole.admin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('รายละเอียดคำสั่งซื้อ'),
        actions: [
          if (isAdmin && _order != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'ลบคำสั่งซื้อ',
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
                      // Header card
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                ],
                              ),
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
                                                color: theme
                                                    .colorScheme.outline)),
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

                      // Items table
                      if (_order!.items.isNotEmpty) ...[
                        Text('รายการอุปกรณ์',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _order!.status == POStatus.pending
                                // pending → ชื่ออุปกรณ์อย่างเดียว (ยังไม่มีราคา)
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'รอ CEO กรอกราคาและจำนวนตอนอนุมัติ',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: theme
                                                    .colorScheme.outline),
                                      ),
                                      const SizedBox(height: 8),
                                      ..._order!.items.map(
                                        (item) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                  Icons.circle,
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
                                // อนุมัติแล้ว → แสดงตารางเต็ม
                                : Column(
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                              flex: 4,
                                              child: Text('ชื่อ',
                                                  style: theme
                                                      .textTheme.labelMedium
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight
                                                                  .bold))),
                                          Expanded(
                                              flex: 2,
                                              child: Text('จำนวน',
                                                  textAlign: TextAlign.center,
                                                  style: theme
                                                      .textTheme.labelMedium
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight
                                                                  .bold))),
                                          Expanded(
                                              flex: 3,
                                              child: Text('ราคา/หน่วย',
                                                  textAlign: TextAlign.right,
                                                  style: theme
                                                      .textTheme.labelMedium
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight
                                                                  .bold))),
                                          Expanded(
                                              flex: 3,
                                              child: Text('รวม',
                                                  textAlign: TextAlign.right,
                                                  style: theme
                                                      .textTheme.labelMedium
                                                      ?.copyWith(
                                                          fontWeight:
                                                              FontWeight
                                                                  .bold))),
                                        ],
                                      ),
                                      const Divider(),
                                      ..._order!.items.map(
                                        (item) => Padding(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 4),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                  flex: 4,
                                                  child: Text(item.name)),
                                              Expanded(
                                                  flex: 2,
                                                  child: Text('${item.qty}',
                                                      textAlign:
                                                          TextAlign.center)),
                                              Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                      '฿${item.unitPrice.toStringAsFixed(2)}',
                                                      textAlign:
                                                          TextAlign.right)),
                                              Expanded(
                                                  flex: 3,
                                                  child: Text(
                                                      '฿${item.total.toStringAsFixed(2)}',
                                                      textAlign:
                                                          TextAlign.right)),
                                            ],
                                          ),
                                        ),
                                      ),
                                const Divider(),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Text(
                                      'รวม: ฿${_order!.totalPrice.toStringAsFixed(2)}',
                                      style: theme.textTheme.titleSmall
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: theme.colorScheme.primary),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Notes
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

                      // Receipt photo
                      if (_order!.receiptImageUrl != null) ...[
                        Text('รูปใบเสร็จ',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: () => _showFullImage(context, _order!.receiptImageUrl!),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              _order!.receiptImageUrl!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ─── Action Buttons ────────────────────────────
                      if (_actionLoading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        // CEO: approve pending PO
                        // CEO / Super Admin: approve pending PO
                        if (isCeo &&
                            _order!.status == POStatus.pending) ...[
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _approveWithPricing,
                                  icon: const Icon(Icons.check),
                                  label: const Text('อนุมัติ'),  
                                  style: FilledButton.styleFrom(
                                      backgroundColor: Colors.green),
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
                        // CEO: mark as ordered
                        if (isCeo &&
                            _order!.status == POStatus.approved) ...[
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _updateStatus('ordered'),
                              icon:
                                  const Icon(Icons.local_shipping_outlined),
                              label: const Text('ดำเนินการสั่งซื้อแล้ว'),
                            ),
                          ),
                        ],
                        // Caretaker (creator): receive
                        if ((isCreator || isCeo) &&
                            (_order!.status == POStatus.approved ||
                                _order!.status == POStatus.ordered)) ...[
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
      child:
          Text(status.displayName, style: TextStyle(color: color, fontSize: 12)),
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
