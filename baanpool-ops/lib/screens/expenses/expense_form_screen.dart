import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/expense.dart';
import '../../services/supabase_service.dart';
import '../../utils/thai_datetime.dart';

class ExpenseFormScreen extends StatefulWidget {
  final String? workOrderId;
  final String? pmScheduleId;

  const ExpenseFormScreen({super.key, this.workOrderId, this.pmScheduleId});

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = SupabaseService(Supabase.instance.client);
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  ExpenseCostType _costType = ExpenseCostType.workOrder;
  ExpensePaidBy _paidBy = ExpensePaidBy.company;
  bool _saving = false;
  bool _loading = true;

  String? _selectedWorkOrderId;
  String? _selectedPmScheduleId;
  List<Map<String, dynamic>> _workOrders = [];
  List<Map<String, dynamic>> _pmSchedules = [];

  // Receipt image
  final ImagePicker _picker = ImagePicker();
  XFile? _receiptImage;
  Uint8List? _receiptBytes;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getWorkOrders(),
        _service.getPmSchedules(),
      ]);
      _workOrders = results[0];
      _pmSchedules = results[1];
      // Pre-select work order if passed via query param
      if (widget.workOrderId != null) {
        _selectedWorkOrderId = widget.workOrderId;
        _costType = ExpenseCostType.workOrder;
      }
      if (widget.pmScheduleId != null) {
        _selectedPmScheduleId = widget.pmScheduleId;
        _costType = ExpenseCostType.pm;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickReceipt() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 70,
      );
      if (image == null) return;
      final bytes = await image.readAsBytes();
      setState(() {
        _receiptImage = image;
        _receiptBytes = bytes;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เลือกรูปภาพล้มเหลว: $e')));
      }
    }
  }

  Future<void> _save() async {
    await _saveExpense();
  }

  Future<void> _saveExpense({bool isNoExpense = false}) async {
    if (!isNoExpense && !_formKey.currentState!.validate()) return;

    // Validate that we have a reference (work order or PM)
    if (_costType == ExpenseCostType.workOrder &&
        _selectedWorkOrderId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณาเลือกใบงาน')));
      return;
    }
    if (_costType == ExpenseCostType.pm && _selectedPmScheduleId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('กรุณาเลือกรายการ PM')));
      return;
    }

    setState(() => _saving = true);
    try {
      // Upload receipt image if selected
      String? receiptUrl;
      if (!isNoExpense && _receiptBytes != null && _receiptImage != null) {
        final ext = _receiptImage!.name.split('.').last;
        final path = 'receipts/${thaiNow().millisecondsSinceEpoch}.$ext';
        try {
          receiptUrl = await _service.uploadFile(
            'photos',
            path,
            _receiptBytes!,
          );
        } catch (e) {
          debugPrint('Upload receipt failed: $e');
        }
      }

      // Get property_id from the selected source
      String? propertyId;
      if (_selectedWorkOrderId != null) {
        final selectedWO = _workOrders.firstWhere(
          (wo) => wo['id'] == _selectedWorkOrderId,
        );
        propertyId = selectedWO['property_id'] as String?;
      } else if (_costType == ExpenseCostType.pm &&
          _selectedPmScheduleId != null) {
        final selectedPM = _pmSchedules.firstWhere(
          (pm) => pm['id'] == _selectedPmScheduleId,
        );
        propertyId = selectedPM['property_id'] as String?;
      }

      await _service.createExpense({
        if (_selectedWorkOrderId != null) 'work_order_id': _selectedWorkOrderId,
        if (_selectedPmScheduleId != null)
          'pm_schedule_id': _selectedPmScheduleId,
        'property_id': propertyId,
        'amount': isNoExpense ? 0 : double.parse(_amountController.text.trim()),
        'description': _descriptionController.text.trim().isEmpty
            ? (isNoExpense ? 'ไม่มีค่าใช้จ่าย' : null)
            : _descriptionController.text.trim(),
        'cost_type': _costType.value,
        'paid_by': _paidBy.value,
        'expense_date': thaiDateForDb(),
        'is_no_expense': isNoExpense,
        if (receiptUrl != null) 'receipt_url': receiptUrl,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isNoExpense ? 'บันทึกว่าไม่มีค่าใช้จ่ายสำเร็จ' : 'บันทึกค่าใช้จ่ายสำเร็จ',
            ),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เพิ่มค่าใช้จ่าย')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Cost Type selector (Work Order vs PM)
                    DropdownButtonFormField<ExpenseCostType>(
                      value: _costType,
                      decoration: InputDecoration(
                        labelText: 'ประเภทค่าใช้จ่าย *',
                        prefixIcon: const Icon(Icons.account_tree),
                        filled:
                            widget.workOrderId != null ||
                            widget.pmScheduleId != null,
                      ),
                      items: ExpenseCostType.values.map((t) {
                        return DropdownMenuItem(
                          value: t,
                          child: Text(t.displayName),
                        );
                      }).toList(),
                      onChanged:
                          (widget.workOrderId != null ||
                              widget.pmScheduleId != null)
                          ? null
                          : (v) {
                              if (v != null) {
                                setState(() {
                                  _costType = v;
                                  _selectedWorkOrderId = null;
                                  _selectedPmScheduleId = null;
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 16),

                    // Work Order selection (shown when cost_type = work_order)
                    if (_costType == ExpenseCostType.workOrder)
                      DropdownButtonFormField<String>(
                        value: _selectedWorkOrderId,
                        decoration: InputDecoration(
                          labelText: 'ใบงาน *',
                          prefixIcon: const Icon(Icons.assignment),
                          filled: widget.workOrderId != null,
                        ),
                        items: _workOrders.map((wo) {
                          return DropdownMenuItem(
                            value: wo['id'] as String,
                            child: Text(
                              wo['title'] as String? ?? 'ไม่มีชื่อ',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: widget.workOrderId != null
                            ? null
                            : (v) => setState(() => _selectedWorkOrderId = v),
                        validator: (v) =>
                            _costType == ExpenseCostType.workOrder && v == null
                            ? 'กรุณาเลือกใบงาน'
                            : null,
                      ),

                    // PM Schedule selection (shown when cost_type = pm)
                    if (_costType == ExpenseCostType.pm)
                      DropdownButtonFormField<String>(
                        value: _selectedPmScheduleId,
                        decoration: InputDecoration(
                          labelText: 'รายการ PM *',
                          prefixIcon: const Icon(Icons.schedule),
                          filled: widget.pmScheduleId != null,
                        ),
                        items: _pmSchedules.map((pm) {
                          return DropdownMenuItem(
                            value: pm['id'] as String,
                            child: Text(
                              pm['title'] as String? ?? 'ไม่มีชื่อ',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: widget.pmScheduleId != null
                            ? null
                            : (v) => setState(() => _selectedPmScheduleId = v),
                        validator: (v) =>
                            _costType == ExpenseCostType.pm && v == null
                            ? 'กรุณาเลือกรายการ PM'
                            : null,
                      ),
                    const SizedBox(height: 16),

                    // Paid By selector (Company vs Owner)
                    DropdownButtonFormField<ExpensePaidBy>(
                      value: _paidBy,
                      decoration: const InputDecoration(
                        labelText: 'รับผิดชอบโดย *',
                        prefixIcon: Icon(Icons.business),
                      ),
                      items: ExpensePaidBy.values.map((p) {
                        return DropdownMenuItem(
                          value: p,
                          child: Text(p.displayName),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) setState(() => _paidBy = v);
                      },
                    ),
                    const SizedBox(height: 16),

                    // Amount
                    TextFormField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'จำนวนเงิน (บาท) *',
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'กรุณากรอกจำนวนเงิน';
                        if (double.tryParse(v) == null)
                          return 'กรุณากรอกตัวเลข';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'รายละเอียด',
                        prefixIcon: Icon(Icons.notes),
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),

                    // Receipt image
                    if (_receiptBytes != null) ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          children: [
                            Image.memory(
                              _receiptBytes!,
                              width: double.infinity,
                              height: 180,
                              fit: BoxFit.cover,
                            ),
                            Positioned(
                              top: 4,
                              right: 4,
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _receiptImage = null;
                                  _receiptBytes = null;
                                }),
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _saving ? null : _pickReceipt,
                      icon: const Icon(Icons.receipt),
                      label: Text(
                        _receiptBytes == null
                            ? 'แนบรูปใบเสร็จ'
                            : 'เปลี่ยนรูปใบเสร็จ',
                      ),
                    ),
                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving
                                ? null
                                : () => _saveExpense(isNoExpense: true),
                            icon: const Icon(Icons.remove_circle_outline),
                            label: const Text('ไม่มีค่าใช้จ่าย'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: _saving ? null : _save,
                            child: _saving
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('บันทึกค่าใช้จ่าย'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
