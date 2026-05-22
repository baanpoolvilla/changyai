import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/purchase_order.dart';
import '../../services/supabase_service.dart';

class PurchaseOrderFormScreen extends StatefulWidget {
  const PurchaseOrderFormScreen({super.key});

  @override
  State<PurchaseOrderFormScreen> createState() =>
      _PurchaseOrderFormScreenState();
}

class _PurchaseOrderFormScreenState extends State<PurchaseOrderFormScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _emergencyReasonCtrl = TextEditingController();

  bool _loading = false;
  bool _loadingProps = true;
  String? _selectedPropertyId;
  List<Map<String, dynamic>> _properties = [];

  bool _isEmergency = false;
  final List<XFile> _pickedImages = [];
  final _picker = ImagePicker();

  final List<_ItemRow> _itemRows = [];

  @override
  void initState() {
    super.initState();
    _loadProperties();
    _addItemRow();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    _emergencyReasonCtrl.dispose();
    for (final r in _itemRows) r.dispose();
    super.dispose();
  }

  Future<void> _loadProperties() async {
    try {
      final data = await _service.getPropertyNamesOnly();
      if (mounted) {
        setState(() {
          _properties = data;
          _loadingProps = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingProps = false);
    }
  }

  void _addItemRow() {
    setState(() => _itemRows.add(_ItemRow()));
  }

  void _removeItemRow(int index) {
    setState(() {
      _itemRows[index].dispose();
      _itemRows.removeAt(index);
    });
  }

  Future<void> _pickImages(ImageSource source) async {
    if (source == ImageSource.camera) {
      final xFile = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (xFile != null) setState(() => _pickedImages.add(xFile));
    } else {
      final xFiles = await _picker.pickMultiImage(imageQuality: 80);
      if (xFiles.isNotEmpty) setState(() => _pickedImages.addAll(xFiles));
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final items = _itemRows
        .map((r) => r.nameCtrl.text.trim())
        .where((name) => name.isNotEmpty)
        .map((name) => {'name': name, 'qty': 0, 'unit_price': 0.0})
        .toList();

    setState(() => _loading = true);
    try {
      // อัปโหลดรูปประกอบ PR
      final prImageUrls = <String>[];
      final now = DateTime.now();
      for (int i = 0; i < _pickedImages.length; i++) {
        final bytes = await _pickedImages[i].readAsBytes();
        final ext = _pickedImages[i].path.split('.').last.toLowerCase();
        final fileName = 'pr_${now.millisecondsSinceEpoch}_$i.$ext';
        final url = await _service.uploadFile('po-receipts', fileName, bytes);
        prImageUrls.add(url);
      }

      await _service.createPurchaseOrder({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'property_id': _selectedPropertyId,
        'items': items,
        'total_price': 0,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'status': 'pending',
        'is_emergency_purchase': _isEmergency,
        'emergency_reason': _isEmergency && _emergencyReasonCtrl.text.trim().isNotEmpty
            ? _emergencyReasonCtrl.text.trim()
            : null,
        'pr_image_urls': prImageUrls,
      });
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('บันทึกล้มเหลว: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('เปิด PR (คำขอซื้ออุปกรณ์)')),
      body: _loadingProps
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ชื่อ PR *',
                        hintText: 'เช่น สั่งซื้ออุปกรณ์ซ่อมแอร์',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'กรุณากรอก' : null,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedPropertyId,
                      decoration:
                          const InputDecoration(labelText: 'บ้าน / ทรัพย์สิน'),
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('— ไม่ระบุ —')),
                        ..._properties.map(
                          (p) => DropdownMenuItem(
                            value: p['id'] as String,
                            child: Text(p['name'] as String),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => _selectedPropertyId = v),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'รายละเอียด',
                        hintText: 'รายละเอียดเพิ่มเติม (ถ้ามี)',
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Items section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('รายการอุปกรณ์ที่ต้องการ',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        TextButton.icon(
                          onPressed: _addItemRow,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('เพิ่มรายการ'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'ใส่ชื่ออุปกรณ์ — CEO จะใส่จำนวนและราคาตอนอนุมัติ',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 8),
                    ..._itemRows.asMap().entries.map((entry) {
                      final i = entry.key;
                      final row = entry.value;
                      return _ItemRowWidget(
                        key: ObjectKey(row),
                        row: row,
                        index: i,
                        onRemove: _itemRows.length > 1
                            ? () => _removeItemRow(i)
                            : null,
                      );
                    }),

                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุ',
                        hintText: 'หมายเหตุเพิ่มเติม (ถ้ามี)',
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Image attachment section
                    Row(
                      children: [
                        Text('รูปประกอบ PR (ถ้ามี)',
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
                          tooltip: 'แกลเลอรี่ (หลายรูป)',
                        ),
                      ],
                    ),
                    if (_pickedImages.isNotEmpty) ...[
                      const SizedBox(height: 8),
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
                            Text(
                              '${_pickedImages.length} รูป',
                              style: TextStyle(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.bold),
                            ),
                            const Spacer(),
                            GestureDetector(
                              onTap: () => setState(() => _pickedImages.clear()),
                              child: Text('ล้างทั้งหมด',
                                  style: TextStyle(
                                      color: Colors.red.shade600,
                                      fontSize: 12)),
                            ),
                          ],
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 4),
                      Text(
                        'แนบรูปอ้างอิง เช่น รูปของที่ชำรุด หรืออุปกรณ์ที่ต้องการ',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline),
                      ),
                    ],
                    const SizedBox(height: 20),

                    // Emergency section
                    Container(
                      decoration: BoxDecoration(
                        color: _isEmergency
                            ? Colors.red.shade50
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _isEmergency
                              ? Colors.red.shade300
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          CheckboxListTile(
                            value: _isEmergency,
                            onChanged: (v) =>
                                setState(() => _isEmergency = v ?? false),
                            title: Text(
                              'กรณีฉุกเฉิน — ซื้อของแล้ว / จบงานแล้ว',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: _isEmergency
                                    ? Colors.red.shade700
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              'เมื่อ CEO อนุมัติจะข้ามไปยัง "เสร็จสิ้น" ทันที',
                              style: TextStyle(
                                fontSize: 12,
                                color: _isEmergency
                                    ? Colors.red.shade600
                                    : Colors.grey.shade600,
                              ),
                            ),
                            activeColor: Colors.red.shade700,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                          if (_isEmergency) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                              child: TextFormField(
                                controller: _emergencyReasonCtrl,
                                maxLines: 2,
                                decoration: InputDecoration(
                                  labelText: 'เหตุผลกรณีฉุกเฉิน *',
                                  hintText: 'ระบุเหตุผลที่ต้องซื้อก่อน',
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                validator: (v) {
                                  if (_isEmergency &&
                                      (v == null || v.trim().isEmpty)) {
                                    return 'กรุณาระบุเหตุผล';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _submit,
                        icon: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(_isEmergency
                                ? Icons.warning_amber
                                : Icons.send_outlined),
                        label: Text(_isEmergency
                            ? 'เปิด PR (ฉุกเฉิน)'
                            : 'เปิด PR — ส่งให้ CEO อนุมัติ'),
                        style: _isEmergency
                            ? FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700)
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// Item row model
class _ItemRow {
  final TextEditingController nameCtrl = TextEditingController();

  void dispose() {
    nameCtrl.dispose();
  }
}

// Item row widget
class _ItemRowWidget extends StatelessWidget {
  final _ItemRow row;
  final int index;
  final VoidCallback? onRemove;

  const _ItemRowWidget({
    super.key,
    required this.row,
    required this.index,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: row.nameCtrl,
              decoration: InputDecoration(
                labelText: 'ชื่ออุปกรณ์ ${index + 1}',
                isDense: true,
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'กรอกชื่อ' : null,
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            color: onRemove != null ? Colors.red : Colors.grey.shade300,
            tooltip: 'ลบรายการ',
          ),
        ],
      ),
    );
  }
}
