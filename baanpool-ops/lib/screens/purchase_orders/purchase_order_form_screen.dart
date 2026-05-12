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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final items = _itemRows
        .map((r) => r.nameCtrl.text.trim())
        .where((name) => name.isNotEmpty)
        .map((name) => {'name': name, 'qty': 0, 'unit_price': 0.0})
        .toList();

    setState(() => _loading = true);
    try {
      await _service.createPurchaseOrder({
        'title': _titleCtrl.text.trim(),
        'description': _descCtrl.text.trim().isEmpty
            ? null
            : _descCtrl.text.trim(),
        'property_id': _selectedPropertyId,
        'items': items,
        'total_price': 0,
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
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
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

  void dispose() {
    nameCtrl.dispose();
  }
}

// ─── Item row widget ───────────────────────────────────
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
              validator: (v) => v == null || v.trim().isEmpty ? 'กรอกชื่อ' : null,
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
