import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_message.dart';

/// หน้าบันทึกค่าใช้จ่ายเล็กน้อย — ผู้ดูแลบ้านซื้อของเองแล้วบันทึก
class QuickExpenseScreen extends StatefulWidget {
  const QuickExpenseScreen({super.key});

  @override
  State<QuickExpenseScreen> createState() => _QuickExpenseScreenState();
}

class _QuickExpenseScreenState extends State<QuickExpenseScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  final _formKey = GlobalKey<FormState>();
  final _descCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _loading = false;
  bool _loadingProps = true;
  String? _selectedPropertyId;
  List<Map<String, dynamic>> _properties = [];

  XFile? _receiptImage;
  Uint8List? _receiptBytes;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadProperties();
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
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

  Future<void> _pickReceipt(ImageSource source) async {
    final xFile = await _picker.pickImage(source: source, imageQuality: 80);
    if (xFile == null) return;
    final bytes = await xFile.readAsBytes();
    setState(() {
      _receiptImage = xFile;
      _receiptBytes = bytes;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      String? receiptUrl;
      if (_receiptBytes != null && _receiptImage != null) {
        final ext = _receiptImage!.path.split('.').last.toLowerCase();
        final fileName =
            'quick_${DateTime.now().millisecondsSinceEpoch}.$ext';
        receiptUrl = await _service.uploadFile(
          'expense-receipts',
          fileName,
          _receiptBytes!,
        );
      }

      final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
      await _service.createExpense({
        'property_id': _selectedPropertyId,
        'amount': amount,
        'description': _descCtrl.text.trim(),
        'category': 'material',
        'cost_type': 'work_order',
        'paid_by': 'company',
        'billable_to_partner': false,
        'is_no_expense': false,
        'expense_date': DateTime.now().toIso8601String(),
        if (_notesCtrl.text.trim().isNotEmpty)
          'notes': _notesCtrl.text.trim(),
        if (receiptUrl != null) 'receipt_url': receiptUrl,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกค่าใช้จ่ายเรียบร้อยแล้ว')),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('บันทึกล้มเหลว: ${friendlyError(e)}')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('บันทึกค่าใช้จ่าย')),
      body: _loadingProps
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // info banner
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer
                            .withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.shopping_bag_outlined,
                              color: theme.colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'บันทึกค่าใช้จ่ายที่ซื้อเองสำหรับงานเล็กๆน้อยๆ เช่น สายไฟ น้ำยา สกรู',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Property
                    DropdownButtonFormField<String>(
                      value: _selectedPropertyId,
                      decoration:
                          const InputDecoration(labelText: 'บ้าน / ทรัพย์สิน *'),
                      items: _properties
                          .map((p) => DropdownMenuItem(
                                value: p['id'] as String,
                                child: Text(p['name'] as String),
                              ))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _selectedPropertyId = v),
                      validator: (v) => v == null ? 'เลือกบ้าน' : null,
                    ),
                    const SizedBox(height: 12),

                    // Description
                    TextFormField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'รายการที่ซื้อ *',
                        hintText: 'เช่น สายไฟ 5 เมตร, กาวซิลิโคน',
                      ),
                      validator: (v) =>
                          v == null || v.trim().isEmpty ? 'กรุณากรอก' : null,
                    ),
                    const SizedBox(height: 12),

                    // Amount
                    TextFormField(
                      controller: _amountCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'จำนวนเงิน (฿) *',
                        hintText: '0.00',
                        prefixText: '฿ ',
                      ),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'กรุณากรอก';
                        if ((double.tryParse(v.trim()) ?? 0) <= 0) {
                          return 'ต้องมากกว่า 0';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

                    // Notes (optional)
                    TextFormField(
                      controller: _notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'หมายเหตุ (ถ้ามี)',
                        hintText: 'รายละเอียดเพิ่มเติม',
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Receipt photo
                    Text('รูปใบเสร็จ (แนะนำ)',
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    if (_receiptBytes != null)
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.memory(
                              _receiptBytes!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _receiptImage = null;
                                _receiptBytes = null;
                              }),
                              child: Container(
                                decoration: const BoxDecoration(
                                    color: Colors.black54,
                                    shape: BoxShape.circle),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(Icons.close,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _pickReceipt(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('ถ่ายรูป'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  _pickReceipt(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library_outlined),
                              label: const Text('เลือกรูป'),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 28),

                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _loading ? null : _submit,
                        icon: _loading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('บันทึกค่าใช้จ่าย'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
