import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/purchase_order.dart';
import '../../models/user.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_state_service.dart';
import '../../utils/thai_datetime.dart';
import '../../utils/error_message.dart';
import '../../utils/image_upload.dart';

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
  final _commentCtrl = TextEditingController();
  final _imagePicker = ImagePicker();

  PurchaseOrder? _order;
  bool _loading = true;
  bool _actionLoading = false;
  bool _commentLoading = false;
  String _propertyName = '';
  List<Map<String, dynamic>> _comments = [];
  XFile? _commentImage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
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
      final comments = await _service.getPOComments(widget.orderId);
      if (mounted) {
        setState(() {
          _order = po;
          _propertyName = propName;
          _comments = comments;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('โหลดล้มเหลว: ${friendlyError(e)}')));
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadComments() async {
    try {
      final data = await _service.getPOComments(widget.orderId);
      if (mounted) setState(() => _comments = data);
    } catch (_) {}
  }

  void _showDeleteCommentDialog(Map<String, dynamic> comment) {
    final content = comment['content'] as String? ?? '';
    // ตัดข้อความยาวไม่ให้ dialog ล้นจอ — '📷' คือคอมเมนต์ที่มีแต่รูป
    final body = content == '📷'
        ? 'ต้องการลบความคิดเห็นนี้หรือไม่?'
        : content.length > 60
            ? 'ต้องการลบความคิดเห็น "${content.substring(0, 60)}…" หรือไม่?'
            : 'ต้องการลบความคิดเห็น "$content" หรือไม่?';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบความคิดเห็น'),
        content: Text('$body\n\nการดำเนินการนี้ไม่สามารถย้อนกลับได้'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _service.deletePOComment(comment['id'] as String);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ลบความคิดเห็นแล้ว'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                await _loadComments();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('ลบไม่สำเร็จ: ${friendlyError(e)}')),
                  );
                }
              }
            },
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty && _commentImage == null) return;
    setState(() => _commentLoading = true);
    try {
      String? imageUrl;
      if (_commentImage != null) {
        final bytes = await _commentImage!.readAsBytes();
        final ext = uploadExtension(_commentImage!);
        final fileName = 'comment_${DateTime.now().millisecondsSinceEpoch}.$ext';
        imageUrl = await _service.uploadFile('po-receipts', fileName, bytes);
      }
      await _service.createPOComment({
        'purchase_order_id': widget.orderId,
        'user_id': Supabase.instance.client.auth.currentUser?.id,
        'content': text.isEmpty ? '📷' : text,
        if (imageUrl != null) 'image_url': imageUrl,
      });
      _commentCtrl.clear();
      setState(() => _commentImage = null);
      await _loadComments();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('เพิ่ม comment ล้มเหลว: ${friendlyError(e)}')));
      }
    }
    if (mounted) setState(() => _commentLoading = false);
  }

  /// หลังทำ action สำเร็จ → เด้งกลับหน้ารายการสั่งซื้อ (ไม่ค้างที่สเต็ปถัดไป)
  void _popWith(String message) {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop(message);
    } else {
      context.go('/purchase-orders');
    }
  }

  Future<void> _updateStatus(String newStatus,
      {String message = 'อัพเดตสถานะแล้ว'}) async {
    setState(() => _actionLoading = true);
    try {
      await _service.updatePurchaseOrder(widget.orderId, {
        'status': newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      });
      _popWith(message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('อัพเดตล้มเหลว: ${friendlyError(e)}')));
        setState(() => _actionLoading = false);
      }
    }
  }

  // ─── CEO อนุมัติปกติ: เลือกผู้รับ PO (ไม่ใส่ราคา) ───────
  Future<void> _approveNormal() async {
    List<Map<String, dynamic>> allUsers = [];
    try {
      allUsers = await _service.getUsers();
    } catch (_) {}
    if (!mounted) return;

    String? selectedAssigneeId;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('อนุมัติ PR — มอบ PO ให้'),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ผู้รับ PO จะเป็นคนไปซื้อของ\nและกรอกราคาตอนรับของ',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                if (allUsers.isNotEmpty)
                  DropdownButtonFormField<String>(
                    value: selectedAssigneeId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                        labelText: 'มอบหมายให้', isDense: true),
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
                        setDlg(() => selectedAssigneeId = v),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ยกเลิก')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('อนุมัติ & มอบ PO'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      final now = DateTime.now();
      final uid = Supabase.instance.client.auth.currentUser?.id;
      await _service.updatePurchaseOrder(widget.orderId, {
        'status': 'approved',
        'po_assigned_to': selectedAssigneeId,
        'po_created_by': uid,
        'po_created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      _popWith('อนุมัติและมอบ PO เรียบร้อย');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('อนุมัติล้มเหลว: ${friendlyError(e)}')));
        setState(() => _actionLoading = false);
      }
    }
  }

  // ─── CEO อนุมัติฉุกเฉิน: ยืนยันอย่างเดียว → received ───────
  Future<void> _approveEmergency() async {
    if (_order == null) return;

    final total = _order!.totalPrice;
    final reason = _order!.emergencyReason;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('อนุมัติ PR ฉุกเฉิน'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  Row(children: [
                    Icon(Icons.warning_amber,
                        color: Colors.red.shade700, size: 16),
                    const SizedBox(width: 6),
                    Text('ซื้อของแล้ว — จ่ายตังไปแล้ว',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.red.shade700,
                            fontSize: 13)),
                  ]),
                  if (reason != null && reason.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text('เหตุผล: $reason',
                        style: TextStyle(
                            color: Colors.red.shade700, fontSize: 12)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (total > 0)
              Text(
                'ยอดรวม: ฿${total.toStringAsFixed(2)}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 8),
            Text(
              'เมื่ออนุมัติจะบันทึกสถานะเป็น "เสร็จสิ้น" ทันที',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.red.shade700),
            child: const Text('อนุมัติ (จบงาน)'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      final now = DateTime.now();
      final uid = Supabase.instance.client.auth.currentUser?.id;
      await _service.updatePurchaseOrder(widget.orderId, {
        'status': 'received',
        'received_by': uid,
        'received_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      if (total > 0) await _createExpense(total, now, suffix: '(ฉุกเฉิน)');
      _popWith('อนุมัติ PR ฉุกเฉิน — บันทึกเสร็จสิ้นแล้ว');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('อนุมัติล้มเหลว: ${friendlyError(e)}')));
        setState(() => _actionLoading = false);
      }
    }
  }

  // ─── ยืนยันดำเนินการ: ราคา + รูป PO → ordered + expense ──────
  Future<void> _confirmOrderWithPricing() async {
    if (_order == null) return;
    final items = _order!.items;
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่มีรายการอุปกรณ์')));
      return;
    }

    final picker = ImagePicker();
    final qtyCtrl = items.map((item) => TextEditingController(
        text: item.qty > 0 ? '${item.qty}' : '1')).toList();
    final priceCtrl = items.map((item) => TextEditingController(
        text: item.unitPrice > 0 ? '${item.unitPrice}' : '')).toList();
    final pickedImages = <XFile>[];

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          double total = 0;
          for (int i = 0; i < items.length; i++) {
            total += (int.tryParse(qtyCtrl[i].text) ?? 0) *
                (double.tryParse(priceCtrl[i].text) ?? 0);
          }
          return AlertDialog(
            title: const Text('ยืนยันดำเนินการสั่งซื้อ'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'กรอกจำนวนและราคาของที่ซื้อ แล้วแนบรูปใบสั่งซื้อ (ถ้ามี)',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),
                  ..._pricingRows(items, qtyCtrl, priceCtrl, setDlg),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('รวม: ฿${total.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),
                  _imagePickerRow(picker, pickedImages, setDlg),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('ยกเลิก')),
              FilledButton(
                onPressed: () {
                  // validate all qty > 0 and price >= 0
                  for (int i = 0; i < items.length; i++) {
                    final qty = int.tryParse(qtyCtrl[i].text) ?? 0;
                    final price = double.tryParse(priceCtrl[i].text);
                    if (qty <= 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text(
                              'กรุณากรอกจำนวนของ "${items[i].name}"')));
                      return;
                    }
                    if (price == null || price < 0) {
                      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                          content: Text(
                              'กรุณากรอกราคาของ "${items[i].name}"')));
                      return;
                    }
                  }
                  Navigator.pop(ctx, true);
                },
                style: FilledButton.styleFrom(backgroundColor: Colors.blue),
                child: const Text('ยืนยันสั่งซื้อ'),
              ),
            ],
          );
        },
      ),
    );

    final capturedQty =
        qtyCtrl.map((c) => int.tryParse(c.text) ?? 1).toList();
    final capturedPrice =
        priceCtrl.map((c) => double.tryParse(c.text) ?? 0).toList();
    final capturedImages = List<XFile>.from(pickedImages);
    for (final c in [...qtyCtrl, ...priceCtrl]) c.dispose();

    if (confirmed != true || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      final now = DateTime.now();
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final urls = await _uploadImages(capturedImages, now);
      final totalPrice = _calcTotal(capturedQty, capturedPrice);
      final updatedItems = _buildItems(items, capturedQty, capturedPrice);

      await _service.updatePurchaseOrder(widget.orderId, {
        'status': 'ordered',
        if (urls.isNotEmpty) 'receipt_image_url': urls.first,
        'receipt_image_urls': urls,
        'items': updatedItems,
        'total_price': totalPrice,
        'ordered_by': uid,
        'ordered_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      if (totalPrice > 0) await _createExpense(totalPrice, now);
      _popWith('ยืนยันการสั่งซื้อเรียบร้อยแล้ว');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('บันทึกล้มเหลว: ${friendlyError(e)}')));
        setState(() => _actionLoading = false);
      }
    }
  }

  // ─── รับของ: แนบรูปใบเสร็จอย่างเดียว → received ──────────
  Future<void> _receiveWithImage() async {
    if (_order == null) return;

    final picker = ImagePicker();
    final pickedImages = <XFile>[];

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('ยืนยันรับของ'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'แนบรูปใบเสร็จหรือรูปสินค้าที่รับมา (ถ้ามี)',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              _imagePickerRow(picker, pickedImages, setDlg),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('ยกเลิก')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('ยืนยันรับของ'),
            ),
          ],
        ),
      ),
    );

    final capturedImages = List<XFile>.from(pickedImages);
    if (confirmed != true || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      final now = DateTime.now();
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final existingUrls = _order?.receiptImageUrls ?? [];
      final newUrls = await _uploadImages(capturedImages, now);
      final allUrls = [...existingUrls, ...newUrls];

      await _service.updatePurchaseOrder(widget.orderId, {
        'status': 'received',
        if (allUrls.isNotEmpty) 'receipt_image_url': allUrls.first,
        'receipt_image_urls': allUrls,
        'received_by': uid,
        'received_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      _popWith('บันทึกการรับของเรียบร้อยแล้ว');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('บันทึกล้มเหลว: ${friendlyError(e)}')));
        setState(() => _actionLoading = false);
      }
    }
  }

  // ─── [Backward compat] Self-purchase: ราคา + รูป ─────────
  Future<void> _selfReceiveWithPricing() async {
    if (_order == null) return;
    final items = _order!.items;
    if (items.isEmpty) return;

    final picker = ImagePicker();
    final qtyCtrl = items.map((_) => TextEditingController(text: '1')).toList();
    final priceCtrl = items.map((_) => TextEditingController()).toList();
    final pickedImages = <XFile>[];

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          double total = 0;
          for (int i = 0; i < items.length; i++) {
            total += (int.tryParse(qtyCtrl[i].text) ?? 0) *
                (double.tryParse(priceCtrl[i].text) ?? 0);
          }
          return AlertDialog(
            title: const Text('กรอกจำนวนและราคาที่ซื้อมา'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ..._pricingRows(items, qtyCtrl, priceCtrl, setDlg),
                  const Divider(),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text('รวม: ฿${total.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 16),
                  _imagePickerRow(picker, pickedImages, setDlg),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('ยกเลิก')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                child: const Text('บันทึก'),
              ),
            ],
          );
        },
      ),
    );

    final capturedQty =
        qtyCtrl.map((c) => int.tryParse(c.text) ?? 1).toList();
    final capturedPrice =
        priceCtrl.map((c) => double.tryParse(c.text) ?? 0).toList();
    final capturedImages = List<XFile>.from(pickedImages);
    for (final c in [...qtyCtrl, ...priceCtrl]) c.dispose();
    if (confirmed != true || !mounted) return;

    setState(() => _actionLoading = true);
    try {
      final now = DateTime.now();
      final uid = Supabase.instance.client.auth.currentUser?.id;
      final existingUrls = _order?.receiptImageUrls ?? [];
      final newUrls = await _uploadImages(capturedImages, now);
      final allUrls = [...existingUrls, ...newUrls];
      final totalPrice = _calcTotal(capturedQty, capturedPrice);
      final updatedItems = _buildItems(items, capturedQty, capturedPrice);

      await _service.updatePurchaseOrder(widget.orderId, {
        'status': 'received',
        if (allUrls.isNotEmpty) 'receipt_image_url': allUrls.first,
        'receipt_image_urls': allUrls,
        'items': updatedItems,
        'total_price': totalPrice,
        'received_by': uid,
        'received_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });
      if (totalPrice > 0) {
        await _createExpense(totalPrice, now, suffix: '(ซื้อเอง)');
      }
      _popWith('บันทึกการรับของเรียบร้อยแล้ว');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('บันทึกล้มเหลว: ${friendlyError(e)}')));
        setState(() => _actionLoading = false);
      }
    }
  }

  // ─── Helpers ──────────────────────────────────────────────

  /// Shared: pricing row widgets for dialog
  List<Widget> _pricingRows(
    List<PurchaseOrderItem> items,
    List<TextEditingController> qtyCtrl,
    List<TextEditingController> priceCtrl,
    StateSetter setDlg,
  ) {
    return items.asMap().entries.map((entry) {
      final i = entry.key;
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(items[i].name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: qtyCtrl[i],
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'จำนวน', isDense: true),
                  onChanged: (_) => setDlg(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: priceCtrl[i],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'ราคา/หน่วย (฿)', isDense: true),
                  onChanged: (_) => setDlg(() {}),
                ),
              ),
            ]),
          ],
        ),
      );
    }).toList();
  }

  /// Shared: image picker section widget for dialog
  Widget _imagePickerRow(
    ImagePicker picker,
    List<XFile> pickedImages,
    StateSetter setDlg,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('รูปใบเสร็จ',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            IconButton(
              onPressed: () async {
                final xFile =
                    await pickUploadImage(picker, ImageSource.camera);
                if (xFile != null) setDlg(() => pickedImages.add(xFile));
              },
              icon: const Icon(Icons.camera_alt_outlined, size: 20),
              tooltip: 'ถ่ายรูป',
            ),
            IconButton(
              onPressed: () async {
                final xFiles = await pickUploadImages(picker);
                if (xFiles.isNotEmpty) {
                  setDlg(() => pickedImages.addAll(xFiles));
                }
              },
              icon: const Icon(Icons.photo_library_outlined, size: 20),
              tooltip: 'แกลเลอรี่ (หลายรูป)',
            ),
          ],
        ),
        if (pickedImages.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline,
                    color: Colors.green.shade700, size: 18),
                const SizedBox(width: 8),
                Text('${pickedImages.length} รูป',
                    style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.bold)),
                const Spacer(),
                GestureDetector(
                  onTap: () => setDlg(() => pickedImages.clear()),
                  child: Text('ล้างทั้งหมด',
                      style: TextStyle(
                          color: Colors.red.shade600, fontSize: 12)),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 8),
          Text(
            'ยังไม่มีรูป — กดไอคอนกล้อง 📷 หรือแกลเลอรี่ 🖼️',
            style:
                TextStyle(color: Colors.grey.shade500, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Future<List<String>> _uploadImages(
      List<XFile> files, DateTime now) async {
    final urls = <String>[];
    for (final xFile in files) {
      final bytes = await xFile.readAsBytes();
      final ext = uploadExtension(xFile);
      final fileName =
          'po_${widget.orderId}_${now.millisecondsSinceEpoch}_${urls.length}.$ext';
      final url =
          await _service.uploadFile('po-receipts', fileName, bytes);
      urls.add(url);
    }
    return urls;
  }

  double _calcTotal(List<int> qty, List<double> price) {
    double total = 0;
    for (int i = 0; i < qty.length; i++) total += qty[i] * price[i];
    return total;
  }

  List<Map<String, dynamic>> _buildItems(
    List<PurchaseOrderItem> items,
    List<int> qty,
    List<double> price,
  ) =>
      List.generate(
        items.length,
        (i) => {
          'name': items[i].name,
          'qty': qty[i],
          'unit_price': price[i],
        },
      );

  Future<void> _createExpense(double amount, DateTime now,
      {String suffix = ''}) async {
    await _service.createExpense({
      'property_id': _order!.propertyId,
      'purchase_order_id': widget.orderId,
      'amount': amount,
      'description':
          'สั่งซื้ออุปกรณ์${suffix.isNotEmpty ? ' $suffix' : ''}: ${_order!.title}',
      'category': 'material',
      'cost_type': 'work_order',
      'paid_by': 'company',
      'billable_to_partner': false,
      'is_no_expense': false,
      'expense_date': now.toIso8601String(),
    });
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
              child: const Text('ยกเลิก')),
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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ลบเรียบร้อยแล้ว')));
        context.go('/purchase-orders');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ลบล้มเหลว: ${friendlyError(e)}')));
        setState(() => _actionLoading = false);
      }
    }
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
    final isAssignedUser = currentUserId != null &&
        (_order?.poAssignedTo == currentUserId ||
            _order?.createdBy == currentUserId ||
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
                      // ─── Header Card ──────────────────────────
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
                                              fontWeight:
                                                  FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _StatusChip(_order!.status),
                                  if (_order!.isEmergencyPurchase) ...[
                                    const SizedBox(width: 6),
                                    _Badge(
                                        label: 'ฉุกเฉิน',
                                        icon: Icons.warning_amber,
                                        color: Colors.red),
                                  ],
                                  if (_order!.isSelfPurchase &&
                                      !_order!.isEmergencyPurchase) ...[
                                    const SizedBox(width: 6),
                                    _Badge(
                                        label: 'ซื้อเอง',
                                        icon: Icons.shopping_bag_outlined,
                                        color: Colors.green),
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
                                _InfoRow(
                                    icon: Icons.home_outlined,
                                    text: _propertyName),
                              ],
                              if (_order!.poAssignedToName != null &&
                                  _order!.poAssignedToName!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _InfoRow(
                                    icon: Icons.assignment_ind_outlined,
                                    text:
                                        'ผู้รับ PO: ${_order!.poAssignedToName}',
                                    color: Colors.blue.shade700),
                              ],
                              if (_order!.description != null &&
                                  _order!.description!.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(_order!.description!,
                                    style: theme.textTheme.bodyMedium),
                              ],
                              const SizedBox(height: 12),
                              const Divider(height: 1),
                              const SizedBox(height: 10),
                              _StateTimeline(_order!),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ─── Items Table ──────────────────────────
                      if (_order!.items.isNotEmpty) ...[
                        Text('รายการอุปกรณ์',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: _order!.totalPrice == 0
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'รอกรอกราคาตอนรับของ',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: theme
                                                    .colorScheme.outline),
                                      ),
                                      const SizedBox(height: 8),
                                      ..._order!.items.map(
                                        (item) => Padding(
                                          padding:
                                              const EdgeInsets.symmetric(
                                                  vertical: 4),
                                          child: Row(children: [
                                            const Icon(Icons.circle,
                                                size: 6,
                                                color: Colors.grey),
                                            const SizedBox(width: 8),
                                            Text(item.name),
                                          ]),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(children: [
                                    Row(children: [
                                      Expanded(
                                          flex: 4,
                                          child: Text('ชื่อ',
                                              style: theme.textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                      Expanded(
                                          flex: 2,
                                          child: Text('จำนวน',
                                              textAlign: TextAlign.center,
                                              style: theme.textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                      Expanded(
                                          flex: 3,
                                          child: Text('ราคา/หน่วย',
                                              textAlign: TextAlign.right,
                                              style: theme.textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                      Expanded(
                                          flex: 3,
                                          child: Text('รวม',
                                              textAlign: TextAlign.right,
                                              style: theme.textTheme
                                                  .labelMedium
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold))),
                                    ]),
                                    const Divider(),
                                    ..._order!.items.map(
                                      (item) => Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 4),
                                        child: Row(children: [
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
                                        ]),
                                      ),
                                    ),
                                    const Divider(),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          'รวม: ฿${_order!.totalPrice.toStringAsFixed(2)}',
                                          style: theme.textTheme.titleSmall
                                              ?.copyWith(
                                                  fontWeight:
                                                      FontWeight.bold,
                                                  color: theme
                                                      .colorScheme.primary),
                                        ),
                                      ],
                                    ),
                                  ]),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ─── PR Images ───────────────────────────
                      if (_order!.prImageUrls.isNotEmpty) ...[
                        Text('รูปประกอบ PR',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 150,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: _order!.prImageUrls
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
                                                        child: Icon(Icons
                                                            .broken_image))),
                                          ),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ─── Notes ────────────────────────────────
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

                      // ─── Receipt Photos ────────────────────────
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
                                        padding: const EdgeInsets.only(
                                            right: 8),
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
                                                          child: Icon(Icons
                                                              .broken_image))),
                                            ),
                                          ),
                                        ),
                                      )),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ─── Action Buttons ────────────────────────
                      if (_actionLoading)
                        const Center(child: CircularProgressIndicator())
                      else ...[
                        // [1] CEO: อนุมัติ PR ปกติ
                        if (isCeo &&
                            _order!.status == POStatus.pending &&
                            !_order!.isEmergencyPurchase) ...[
                          Row(children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _approveNormal,
                                icon: const Icon(Icons.check),
                                label: const Text('อนุมัติ & มอบ PO'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.green),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _updateStatus('cancelled',
                                    message: 'ปฏิเสธคำขอแล้ว'),
                                icon: const Icon(Icons.close),
                                label: const Text('ปฏิเสธ'),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red),
                              ),
                            ),
                          ]),
                        ],

                        // [2] CEO: อนุมัติ PR ฉุกเฉิน
                        if (isCeo &&
                            _order!.status == POStatus.pending &&
                            _order!.isEmergencyPurchase) ...[
                          Row(children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _approveEmergency,
                                icon: const Icon(Icons.warning_amber),
                                label: const Text('อนุมัติ (ฉุกเฉิน)'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.red.shade700),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _updateStatus('cancelled',
                                    message: 'ปฏิเสธคำขอแล้ว'),
                                icon: const Icon(Icons.close),
                                label: const Text('ปฏิเสธ'),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red),
                              ),
                            ),
                          ]),
                        ],

                        // [3] ยืนยันดำเนินการ: กรอกราคา + รูป (approved → ordered)
                        if (_order!.status == POStatus.approved &&
                            !_order!.isSelfPurchase &&
                            (isCeo || isAssignedUser)) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _confirmOrderWithPricing,
                              icon: const Icon(
                                  Icons.local_shipping_outlined),
                              label: const Text(
                                  'ยืนยันดำเนินการ — กรอกราคา + แนบรูป'),
                            ),
                          ),
                        ],

                        // [4] รับของ: แนบรูปใบเสร็จ (ordered → received)
                        if (_order!.status == POStatus.ordered &&
                            !_order!.isSelfPurchase &&
                            (isCeo || isAssignedUser)) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _receiveWithImage,
                              icon: const Icon(
                                  Icons.inventory_2_outlined),
                              label: const Text(
                                  'รับของ — แนบรูปใบเสร็จ'),
                            ),
                          ),
                        ],

                        // [5] [Backward compat] Self-purchase
                        if (_order!.isSelfPurchase &&
                            _order!.status == POStatus.ordered) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _selfReceiveWithPricing,
                              icon: const Icon(Icons.shopping_bag),
                              label: const Text(
                                  'รับของ → ถ่ายรูป + กรอกราคา'),
                              style: FilledButton.styleFrom(
                                  backgroundColor:
                                      Colors.green.shade700),
                            ),
                          ),
                        ],

                        // [6] แจ้งของมีปัญหา / คืนของ (ordered หรือ received)
                        if ((_order!.status == POStatus.ordered ||
                                _order!.status == POStatus.received) &&
                            (isCeo || isAssignedUser)) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => context.push(
                                  '/purchase-orders/returns/new?poId=${_order!.id}'),
                              icon: const Icon(
                                  Icons.assignment_return_outlined),
                              label: const Text('แจ้งของมีปัญหา / คืนของ'),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.brown),
                            ),
                          ),
                        ],
                      ],

                      // ─── Comments ──────────────────────────────
                      const SizedBox(height: 24),
                      Text('ความเห็น',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 12),
                      if (_comments.isEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(vertical: 8),
                          child: Text('ยังไม่มีความเห็น',
                              style: TextStyle(
                                  color: Colors.grey.shade400,
                                  fontSize: 13)),
                        )
                      else
                        ..._comments.map((c) => _CommentBubble(
                              content: c['content'] as String,
                              authorName: (c['user'] is Map)
                                  ? (c['user']['full_name'] as String?) ??
                                      'ไม่ทราบ'
                                  : 'ไม่ทราบ',
                              createdAt: DateTime.parse(
                                  c['created_at'] as String),
                              imageUrl: c['image_url'] as String?,
                              onDelete: () => _showDeleteCommentDialog(c),
                            )),
                      const SizedBox(height: 12),
                      // Add comment input
                      if (_commentImage != null) ...[
                        Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.image,
                                  color: Colors.blue.shade700, size: 16),
                              const SizedBox(width: 6),
                              Text('รูปที่เลือก 1 รูป',
                                  style: TextStyle(
                                      color: Colors.blue.shade700,
                                      fontSize: 12)),
                              const Spacer(),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _commentImage = null),
                                child: Icon(Icons.close,
                                    color: Colors.red.shade400, size: 16),
                              ),
                            ],
                          ),
                        ),
                      ],
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          IconButton(
                            onPressed: _commentLoading
                                ? null
                                : () async {
                                    final picked = await pickUploadImage(
                                        _imagePicker, ImageSource.gallery);
                                    if (picked != null) {
                                      setState(() => _commentImage = picked);
                                    }
                                  },
                            icon: Icon(
                              Icons.photo_library_outlined,
                              color: _commentImage != null
                                  ? Colors.blue
                                  : Colors.grey,
                              size: 20,
                            ),
                            tooltip: 'แนบรูป',
                          ),
                          IconButton(
                            onPressed: _commentLoading
                                ? null
                                : () async {
                                    final picked = await pickUploadImage(
                                        _imagePicker, ImageSource.camera);
                                    if (picked != null) {
                                      setState(() => _commentImage = picked);
                                    }
                                  },
                            icon: const Icon(Icons.camera_alt_outlined,
                                color: Colors.grey, size: 20),
                            tooltip: 'ถ่ายรูป',
                          ),
                          Expanded(
                            child: TextField(
                              controller: _commentCtrl,
                              decoration: const InputDecoration(
                                hintText: 'เพิ่มความเห็น...',
                                isDense: true,
                              ),
                              maxLines: null,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _addComment(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _commentLoading
                              ? const SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))
                              : IconButton(
                                  onPressed: _addComment,
                                  icon: const Icon(Icons.send),
                                  color: theme.colorScheme.primary,
                                ),
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────

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

class _Badge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _Badge(
      {required this.label, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11)),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _InfoRow({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.grey;
    return Row(
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 4),
        Expanded(
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color ?? Theme.of(context).colorScheme.outline)),
        ),
      ],
    );
  }
}

/// Timeline แสดงผู้ทำ + วันที่ ของแต่ละสเต็ป (เปิด PR / สร้าง PO / รับของ)
class _StateTimeline extends StatelessWidget {
  final PurchaseOrder order;
  const _StateTimeline(this.order);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget row(
        IconData icon, Color color, String label, String? who, DateTime when) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: RichText(
                text: TextSpan(
                  style: theme.textTheme.bodySmall,
                  children: [
                    TextSpan(
                        text: '$label: ',
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.w600)),
                    TextSpan(
                        text: (who == null || who.isEmpty) ? 'ไม่ทราบ' : who,
                        style: TextStyle(color: theme.colorScheme.onSurface)),
                    TextSpan(
                        text: '  •  ${formatThaiDate(when)}',
                        style: TextStyle(color: theme.colorScheme.outline)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row(Icons.edit_note, Colors.orange.shade700, 'เปิด PR',
            order.createdByName, order.createdAt),
        if (order.poCreatedAt != null)
          row(Icons.assignment_turned_in, Colors.blue.shade700, 'สร้าง PO',
              order.poCreatedByName, order.poCreatedAt!),
        if (order.orderedAt != null)
          row(Icons.local_shipping, Colors.indigo.shade700, 'ดำเนินการซื้อ',
              order.orderedByName, order.orderedAt!),
        if (order.receivedAt != null)
          row(Icons.inventory_2, Colors.green.shade700, 'รับของ',
              order.receivedByName, order.receivedAt!),
      ],
    );
  }
}

class _CommentBubble extends StatelessWidget {
  final String content;
  final String authorName;
  final DateTime createdAt;
  final String? imageUrl;
  final VoidCallback? onDelete;
  const _CommentBubble(
      {required this.content,
      required this.authorName,
      required this.createdAt,
      this.imageUrl,
      this.onDelete});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor:
                theme.colorScheme.primary.withValues(alpha: 0.15),
            child: Text(
              authorName.isNotEmpty ? authorName[0].toUpperCase() : '?',
              style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(authorName,
                        style: theme.textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Text(formatThaiDate(createdAt),
                        style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.outline)),
                    if (onDelete != null) ...[
                      const Spacer(),
                      InkWell(
                        onTap: onDelete,
                        borderRadius: BorderRadius.circular(16),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(Icons.delete_outline,
                              size: 16, color: Colors.grey),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (content != '📷')
                        Text(content, style: theme.textTheme.bodyMedium),
                      if (imageUrl != null) ...[
                        if (content != '📷') const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              child: Image.network(imageUrl!,
                                  fit: BoxFit.contain),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: Image.network(
                              imageUrl!,
                              height: 160,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
