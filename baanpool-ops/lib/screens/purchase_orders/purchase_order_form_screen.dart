import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
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

  bool _loading = false;
  bool _loadingProps = true;
  String? _selectedPropertyId;
  List<Map<String, dynamic>> _properties = [];

  // Dynamic items list
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

  double get _totalPrice =>
      _itemRows.fold(0, (sum, r) => sum + (r.computedTotal ?? 0));

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final items = <Map<String, dynamic>>[];
    for (final row in _itemRows) {
      final name = row.nameCtrl.text.trim();
      final qty = int.tryParse(row.qtyCtrl.text.trim()) ?? 0;
      final unitPrice = double.tryParse(row.unitPriceCtrl.text.trim()) ?? 0;
      if (name.isNotEmpty && qty > 0) {
        items.add({'name': name, 'qty': qty, 'unit_price': unitPrice});
      }
    }

    setState(() => _loading = true);
    try {
      await _service.createPurchaseOrder({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'property_id': _selectedPropertyId,
        'items': items,
        'total_price': _totalPrice,
        'notes':
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'status': 'pending',
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
      appBar: AppBar(title: const Text('สร้างคำสั่งซื้ออุปกรณ์')),
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
                        labelText: 'ชื่อคำสั่งซื้อ *',
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
                      onChanged: (v) =>
                          setState(() => _selectedPropertyId = v),
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
                        Text('รายการอุปกรณ์',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        TextButton.icon(
                          onPressed: _addItemRow,
                          icon: const Icon(Icons.add, size: 16),
                          label: const Text('เพิ่มรายการ'),
                        ),
                      ],
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
                        onChanged: () => setState(() {}),
                      );
                    }),

                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        'รวมทั้งหมด: ฿${_totalPrice.toStringAsFixed(2)}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุ',
                        hintText: 'หมายเหตุเพิ่มเติม (ถ้ามี)',
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Text('ส่งคำสั่งซื้อ'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ─── Item row model ────────────────────────────────────
class _ItemRow {
  final TextEditingController nameCtrl = TextEditingController();
  final TextEditingController qtyCtrl = TextEditingController(text: '1');
  final TextEditingController unitPriceCtrl = TextEditingController();

  double? get computedTotal {
    final qty = int.tryParse(qtyCtrl.text) ?? 0;
    final price = double.tryParse(unitPriceCtrl.text) ?? 0;
    return qty * price;
  }

  void dispose() {
    nameCtrl.dispose();
    qtyCtrl.dispose();
    unitPriceCtrl.dispose();
  }
}

// ─── Item row widget ───────────────────────────────────
class _ItemRowWidget extends StatelessWidget {
  final _ItemRow row;
  final int index;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  const _ItemRowWidget({
    super.key,
    required this.row,
    required this.index,
    required this.onRemove,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name
          Expanded(
            flex: 4,
            child: TextFormField(
              controller: row.nameCtrl,
              decoration: InputDecoration(
                labelText: 'ชื่อ ${index + 1}',
                isDense: true,
              ),
              onChanged: (_) => onChanged(),
              validator: (v) => v == null || v.trim().isEmpty ? 'กรอกชื่อ' : null,
            ),
          ),
          const SizedBox(width: 8),
          // Qty
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: row.qtyCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'จำนวน',
                isDense: true,
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 8),
          // Unit price
          Expanded(
            flex: 3,
            child: TextFormField(
              controller: row.unitPriceCtrl,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'ราคา/หน่วย',
                isDense: true,
              ),
              onChanged: (_) => onChanged(),
            ),
          ),
          const SizedBox(width: 4),
          // Remove button
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline, size: 20),
            color: onRemove != null ? Colors.red : Colors.grey.shade300,
            tooltip: 'ลบรายการ',
            padding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ],
      ),
    );
  }
}
