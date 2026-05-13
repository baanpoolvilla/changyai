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

  // true = ซื้อเอง, false = ให้ CEO อนุมัติ
  bool _isSelfPurchase = false;

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
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'status': _isSelfPurchase ? 'ordered' : 'pending',
        'is_self_purchase': _isSelfPurchase,
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
    final colorScheme = theme.colorScheme;

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
                    // Type Selector
                    Text('ประเภทการสั่งซื้อ',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _TypeCard(
                            selected: !_isSelfPurchase,
                            icon: Icons.approval_outlined,
                            selectedIcon: Icons.approval,
                            title: 'ให้ CEO อนุมัติ',
                            subtitle: 'CEO ตรวจสอบและกรอกราคาก่อนซื้อ',
                            color: colorScheme.primary,
                            onTap: () => setState(() => _isSelfPurchase = false),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _TypeCard(
                            selected: _isSelfPurchase,
                            icon: Icons.shopping_bag_outlined,
                            selectedIcon: Icons.shopping_bag,
                            title: 'ซื้อเอง',
                            subtitle: 'ไม่ต้องรอ CEO\nกรอกราคาตอนรับของ',
                            color: Colors.green.shade700,
                            onTap: () => setState(() => _isSelfPurchase = true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

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
                      _isSelfPurchase
                          ? 'ใส่ชื่ออุปกรณ์ — กรอกราคาตอนรับของ'
                          : 'ใส่ชื่ออุปกรณ์ — CEO จะใส่จำนวนและราคาตอนอนุมัติ',
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
                            : Icon(_isSelfPurchase
                                ? Icons.shopping_bag
                                : Icons.send_outlined),
                        label: Text(_isSelfPurchase
                            ? 'สร้างคำสั่งซื้อ (ซื้อเอง)'
                            : 'ส่งให้ CEO อนุมัติ'),
                        style: _isSelfPurchase
                            ? FilledButton.styleFrom(
                                backgroundColor: Colors.green.shade700)
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

// Type selector card
class _TypeCard extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final IconData selectedIcon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _TypeCard({
    required this.selected,
    required this.icon,
    required this.selectedIcon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.1) : Colors.transparent,
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(selected ? selectedIcon : icon,
                color: selected ? color : Colors.grey, size: 28),
            const SizedBox(height: 8),
            Text(title,
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: selected ? color : null,
                    fontSize: 14)),
            const SizedBox(height: 4),
            Text(subtitle,
                style: TextStyle(
                    fontSize: 11,
                    color: selected
                        ? color.withValues(alpha: 0.8)
                        : Colors.grey.shade600)),
          ],
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