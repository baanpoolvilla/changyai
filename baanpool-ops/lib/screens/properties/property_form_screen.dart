import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_message.dart';

/// Screen for creating / editing a property
class PropertyFormScreen extends StatefulWidget {
  final String? propertyId; // null = create mode

  const PropertyFormScreen({super.key, this.propertyId});

  @override
  State<PropertyFormScreen> createState() => _PropertyFormScreenState();
}

class _PropertyFormScreenState extends State<PropertyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = SupabaseService(Supabase.instance.client);
  bool _saving = false;
  bool _loading = false;

  final _nameCtrl = TextEditingController();

  String? _selectedCaretakerId;
  List<Map<String, dynamic>> _caretakers = [];

  bool get _isEdit => widget.propertyId != null;

  @override
  void initState() {
    super.initState();
    _loadCaretakers();
    if (_isEdit) _loadProperty();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCaretakers() async {
    try {
      // Load caretakers + all users (so admin can assign anyone as caretaker)
      final users = await _service.getUsers();
      setState(() => _caretakers = users);
    } catch (_) {}
  }

  Future<void> _loadProperty() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getProperty(widget.propertyId!);
      _nameCtrl.text = data['name'] ?? '';
      _selectedCaretakerId = data['caretaker_id'] as String?;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: ${friendlyError(e)}')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final data = {
      'name': _nameCtrl.text.trim(),
      'caretaker_id': _selectedCaretakerId,
    };

    try {
      if (_isEdit) {
        await _service.updateProperty(widget.propertyId!, data);
      } else {
        await _service.createProperty(data);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isEdit ? 'อัพเดทบ้านสำเร็จ' : 'เพิ่มบ้านสำเร็จ'),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกล้มเหลว: ${friendlyError(e)}')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'แก้ไขบ้าน' : 'เพิ่มบ้านใหม่')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextFormField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ชื่อบ้าน *',
                        prefixIcon: Icon(Icons.home),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'กรุณากรอกชื่อบ้าน'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    // Caretaker dropdown
                    DropdownButtonFormField<String?>(
                      value: _selectedCaretakerId,
                      decoration: const InputDecoration(
                        labelText: 'ผู้จัดการบ้าน',
                        prefixIcon: Icon(Icons.home_work),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('ไม่ระบุ'),
                        ),
                        ..._caretakers.map(
                          (u) => DropdownMenuItem(
                            value: u['id'] as String,
                            child: Text('${u['full_name']} (${u['role']})'),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedCaretakerId = v),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_isEdit ? 'บันทึก' : 'เพิ่มบ้าน'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
