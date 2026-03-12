import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user.dart';
import '../../services/auth_state_service.dart';
import '../../services/supabase_service.dart';

class WorkOrderFormScreen extends StatefulWidget {
  final String? prefillTitle;
  final String? prefillPropertyId;
  final String? prefillTechnicianId;
  final String? prefillDescription;
  final String? prefillAssetId;
  final String? prefillPriority;

  const WorkOrderFormScreen({
    super.key,
    this.prefillTitle,
    this.prefillPropertyId,
    this.prefillTechnicianId,
    this.prefillDescription,
    this.prefillAssetId,
    this.prefillPriority,
  });

  @override
  State<WorkOrderFormScreen> createState() => _WorkOrderFormScreenState();
}

class _WorkOrderFormScreenState extends State<WorkOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = SupabaseService(Supabase.instance.client);
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _priority = 'medium';
  String? _selectedPropertyId;
  String? _selectedTechnicianId;
  bool _saving = false;
  bool _loading = true;

  List<Map<String, dynamic>> _properties = [];
  List<Map<String, dynamic>> _technicians = [];

  // Image picker
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _pickedImages = [];
  final List<Uint8List> _imageBytes = [];

  @override
  void initState() {
    super.initState();
    // Pre-fill from PM schedule or other sources
    if (widget.prefillTitle != null) {
      _titleController.text = widget.prefillTitle!;
    }
    if (widget.prefillDescription != null) {
      _descriptionController.text = widget.prefillDescription!;
    }
    if (widget.prefillPropertyId != null) {
      _selectedPropertyId = widget.prefillPropertyId;
    }
    if (widget.prefillTechnicianId != null) {
      _selectedTechnicianId = widget.prefillTechnicianId;
    }
    if (widget.prefillPriority != null) {
      _priority = widget.prefillPriority!;
    }
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getProperties(),
        _service.getUsers(), // Get all users for assignment
      ]);
      _properties = results[0];
      // Caretaker role can only assign technicians + themselves
      final allUsers = results[1];
      final currentRole = AuthStateService().currentRole;
      if (currentRole == UserRole.caretaker) {
        final currentUserId = AuthStateService().currentAppUser?.id;
        _technicians = allUsers
            .where((u) => u['role'] == 'technician' || u['id'] == currentUserId)
            .toList();
      } else {
        _technicians = allUsers;
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
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      // Upload images in parallel
      final photoUrls = <String>[];
      final uploadFutures = <Future<String?>>[];
      for (int i = 0; i < _imageBytes.length; i++) {
        final bytes = _imageBytes[i];
        final ext = _pickedImages[i].name.split('.').last;
        final path =
            'work-orders/${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        uploadFutures.add(
          _service
              .uploadFile('photos', path, bytes)
              .then<String?>((url) => url)
              .catchError((_) {
                debugPrint('Upload image $i failed');
                return null;
              }),
        );
      }
      final uploadResults = await Future.wait(uploadFutures);
      for (final url in uploadResults) {
        if (url != null) photoUrls.add(url);
      }

      final data = {
        'title': _titleController.text.trim(),
        'property_id': _selectedPropertyId,
        'priority': _priority,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'assigned_to': _selectedTechnicianId,
        'status': 'open',
        if (widget.prefillAssetId != null) 'asset_id': widget.prefillAssetId,
        if (photoUrls.isNotEmpty) 'photo_urls': photoUrls,
      };

      await _service.createWorkOrder(data);

      // LINE notification is sent automatically via database trigger
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('สร้างใบงานสำเร็จ ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }

      if (mounted) {
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('สร้างใบงานล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _pickImages() async {
    try {
      final images = await _picker.pickMultiImage(imageQuality: 70);
      if (images.isEmpty) return;
      final newImages = <XFile>[];
      final newBytes = <Uint8List>[];
      for (final img in images) {
        final bytes = await img.readAsBytes();
        newImages.add(img);
        newBytes.add(bytes);
      }
      setState(() {
        _pickedImages.addAll(newImages);
        _imageBytes.addAll(newBytes);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เลือกรูปภาพล้มเหลว: $e')));
      }
    }
  }

  String _getRoleLabel(String? role) {
    switch (role) {
      case 'admin':
        return 'ผู้ดูแลระบบ';
      case 'owner':
        return 'เจ้าของ';
      case 'manager':
        return 'ผู้จัดการ';
      case 'caretaker':
        return 'ผู้ดูแลบ้าน';
      case 'technician':
        return 'ช่าง';
      default:
        return role ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('สร้างใบงานใหม่')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Title
                    TextFormField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'หัวข้องาน *',
                        prefixIcon: Icon(Icons.assignment),
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'กรุณากรอกหัวข้องาน' : null,
                    ),
                    const SizedBox(height: 16),

                    // Property dropdown
                    DropdownButtonFormField<String>(
                      value: _selectedPropertyId,
                      decoration: const InputDecoration(
                        labelText: 'บ้าน *',
                        prefixIcon: Icon(Icons.home),
                      ),
                      items: _properties
                          .map(
                            (p) => DropdownMenuItem(
                              value: p['id'] as String,
                              child: Text(p['name'] as String),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedPropertyId = v),
                      validator: (v) => v == null ? 'กรุณาเลือกบ้าน' : null,
                    ),
                    const SizedBox(height: 16),

                    // Technician dropdown
                    DropdownButtonFormField<String?>(
                      value: _selectedTechnicianId,
                      decoration: const InputDecoration(
                        labelText: 'รับผิดชอบโดย',
                        prefixIcon: Icon(Icons.person),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('ยังไม่ระบุ'),
                        ),
                        ..._technicians.map(
                          (t) => DropdownMenuItem(
                            value: t['id'] as String,
                            child: Text(
                              '${t['full_name']} (${_getRoleLabel(t['role'] as String?)})',
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _selectedTechnicianId = v),
                    ),
                    const SizedBox(height: 16),

                    // Priority
                    DropdownButtonFormField<String>(
                      value: _priority,
                      decoration: const InputDecoration(
                        labelText: 'ความสำคัญ',
                        prefixIcon: Icon(Icons.flag),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'low', child: Text('ต่ำ')),
                        DropdownMenuItem(
                          value: 'medium',
                          child: Text('ปานกลาง'),
                        ),
                        DropdownMenuItem(value: 'high', child: Text('สูง')),
                        DropdownMenuItem(value: 'urgent', child: Text('ด่วน')),
                      ],
                      onChanged: (v) =>
                          setState(() => _priority = v ?? 'medium'),
                    ),
                    const SizedBox(height: 16),

                    // Description
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'รายละเอียด',
                        prefixIcon: Icon(Icons.description),
                      ),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 16),

                    // Photo attachment
                    if (_imageBytes.isNotEmpty) ...[
                      SizedBox(
                        height: 100,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _imageBytes.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            return Stack(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    _imageBytes[index],
                                    width: 100,
                                    height: 100,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                Positioned(
                                  top: 2,
                                  right: 2,
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        _pickedImages.removeAt(index);
                                        _imageBytes.removeAt(index);
                                      });
                                    },
                                    child: Container(
                                      decoration: const BoxDecoration(
                                        color: Colors.red,
                                        shape: BoxShape.circle,
                                      ),
                                      padding: const EdgeInsets.all(4),
                                      child: const Icon(
                                        Icons.close,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      onPressed: _pickImages,
                      icon: const Icon(Icons.camera_alt),
                      label: Text(
                        _imageBytes.isEmpty
                            ? 'แนบรูปภาพ'
                            : 'เพิ่มรูปภาพ (${_imageBytes.length})',
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Submit
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('บันทึกใบงาน'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
