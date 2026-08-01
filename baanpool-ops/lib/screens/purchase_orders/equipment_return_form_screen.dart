import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/purchase_order.dart';
import '../../models/equipment_return.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_message.dart';
import '../../utils/image_upload.dart';

/// ฟอร์มแจ้ง "คืนของ / ของมีปัญหา" — ผูกกับ PO เดิม
class EquipmentReturnFormScreen extends StatefulWidget {
  final String? initialPoId;
  const EquipmentReturnFormScreen({super.key, this.initialPoId});

  @override
  State<EquipmentReturnFormScreen> createState() =>
      _EquipmentReturnFormScreenState();
}

class _EquipmentReturnFormScreenState extends State<EquipmentReturnFormScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  final _formKey = GlobalKey<FormState>();
  final _reasonCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _picker = ImagePicker();

  bool _loadingPos = true;
  bool _saving = false;

  List<PurchaseOrder> _pos = [];
  String? _selectedPoId;
  String? _selectedItemName;
  ReturnProblemType _problemType = ReturnProblemType.defective;
  final List<XFile> _pickedImages = [];

  @override
  void initState() {
    super.initState();
    _selectedPoId = widget.initialPoId;
    _loadPos();
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPos() async {
    try {
      final data = await _service.getPurchaseOrders();
      final all = data.map((e) => PurchaseOrder.fromJson(e)).toList();
      // เลือกได้เฉพาะรายการที่ผ่านการอนุมัติ/ซื้อ/รับของแล้ว
      final usable = all
          .where((o) =>
              o.status == POStatus.approved ||
              o.status == POStatus.ordered ||
              o.status == POStatus.received)
          .toList();
      if (mounted) {
        setState(() {
          _pos = usable;
          if (_selectedPoId != null &&
              !usable.any((o) => o.id == _selectedPoId)) {
            _selectedPoId = null;
          }
          _loadingPos = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingPos = false);
    }
  }

  PurchaseOrder? get _selectedPo {
    if (_selectedPoId == null) return null;
    for (final o in _pos) {
      if (o.id == _selectedPoId) return o;
    }
    return null;
  }

  Future<void> _pickImages(ImageSource source) async {
    if (source == ImageSource.camera) {
      final x = await pickUploadImage(_picker, ImageSource.camera);
      if (x != null) setState(() => _pickedImages.add(x));
    } else {
      final xs = await pickUploadImages(_picker);
      if (xs.isNotEmpty) setState(() => _pickedImages.addAll(xs));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedPoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรุณาเลือกรายการสั่งซื้อ (PO)')));
      return;
    }

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final imageUrls = <String>[];
      for (int i = 0; i < _pickedImages.length; i++) {
        final bytes = await _pickedImages[i].readAsBytes();
        final ext = uploadExtension(_pickedImages[i]);
        final fileName = 'return_${now.millisecondsSinceEpoch}_$i.$ext';
        final url = await _service.uploadFile('po-receipts', fileName, bytes);
        imageUrls.add(url);
      }

      await _service.createEquipmentReturn({
        'purchase_order_id': _selectedPoId,
        'property_id': _selectedPo?.propertyId,
        'item_name': _selectedItemName,
        'qty': int.tryParse(_qtyCtrl.text) ?? 1,
        'problem_type': _problemType.name,
        'reason': _reasonCtrl.text.trim(),
        'status': 'pending',
        'image_urls': imageUrls,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('แจ้งคืน/ปัญหาเรียบร้อยแล้ว')));
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('บันทึกล้มเหลว: ${friendlyError(e)}')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _selectedPo?.items ?? [];

    return Scaffold(
      appBar: AppBar(title: const Text('แจ้งคืนของ / ของมีปัญหา')),
      body: _loadingPos
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── เลือก PO ───
                    DropdownButtonFormField<String>(
                      value: _selectedPoId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'รายการสั่งซื้อ (PO) *',
                        prefixIcon: Icon(Icons.shopping_cart_outlined),
                      ),
                      items: _pos
                          .map((o) => DropdownMenuItem(
                                value: o.id,
                                child: Text(o.title,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      validator: (v) =>
                          v == null ? 'กรุณาเลือกรายการสั่งซื้อ' : null,
                      onChanged: (v) => setState(() {
                        _selectedPoId = v;
                        _selectedItemName = null;
                      }),
                    ),
                    if (_pos.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'ยังไม่มี PO ที่อนุมัติ/รับของแล้วให้เลือก',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.red.shade600),
                        ),
                      ),
                    const SizedBox(height: 12),

                    // ─── เลือกรายการอุปกรณ์ใน PO ───
                    if (items.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        value: _selectedItemName,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'อุปกรณ์ที่มีปัญหา',
                          prefixIcon: Icon(Icons.inventory_2_outlined),
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('— ทั้งรายการ / ไม่ระบุ —')),
                          ...items.map((it) => DropdownMenuItem(
                                value: it.name,
                                child: Text(it.name,
                                    overflow: TextOverflow.ellipsis),
                              )),
                        ],
                        onChanged: (v) =>
                            setState(() => _selectedItemName = v),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ─── ชนิดปัญหา + จำนวน ───
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<ReturnProblemType>(
                            value: _problemType,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'ชนิดปัญหา *',
                            ),
                            items: ReturnProblemType.values
                                .map((t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(t.displayName,
                                          overflow: TextOverflow.ellipsis),
                                    ))
                                .toList(),
                            onChanged: (v) => setState(
                                () => _problemType = v ?? ReturnProblemType.other),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 90,
                          child: TextFormField(
                            controller: _qtyCtrl,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'จำนวน'),
                            validator: (v) =>
                                (int.tryParse(v ?? '') ?? 0) <= 0
                                    ? 'จำนวน'
                                    : null,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // ─── รายละเอียดปัญหา ───
                    TextFormField(
                      controller: _reasonCtrl,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'รายละเอียดปัญหา *',
                        hintText: 'อธิบายว่าของมีปัญหาอย่างไร / ต้องการคืนเพราะอะไร',
                        alignLabelWithHint: true,
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'กรุณากรอก' : null,
                    ),
                    const SizedBox(height: 20),

                    // ─── รูปประกอบ ───
                    Row(
                      children: [
                        Text('รูปของที่มีปัญหา (ถ้ามี)',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          onPressed: () => _pickImages(ImageSource.camera),
                          icon: const Icon(Icons.camera_alt_outlined, size: 20),
                          tooltip: 'ถ่ายรูป',
                        ),
                        IconButton(
                          onPressed: () => _pickImages(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined, size: 20),
                          tooltip: 'แกลเลอรี่',
                        ),
                      ],
                    ),
                    if (_pickedImages.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.photo_library,
                                color: Colors.blue.shade700, size: 18),
                            const SizedBox(width: 8),
                            Text('${_pickedImages.length} รูป',
                                style: TextStyle(
                                    color: Colors.blue.shade700,
                                    fontWeight: FontWeight.bold)),
                            const Spacer(),
                            GestureDetector(
                              onTap: () =>
                                  setState(() => _pickedImages.clear()),
                              child: Text('ล้างทั้งหมด',
                                  style: TextStyle(
                                      color: Colors.red.shade600,
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _submit,
                        icon: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.assignment_return_outlined),
                        label: const Text('แจ้งคืน / ปัญหา'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
