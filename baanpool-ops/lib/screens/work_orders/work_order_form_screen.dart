import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user.dart';
import '../../services/auth_state_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_message.dart';
import '../../utils/image_upload.dart';

class WorkOrderFormScreen extends StatefulWidget {
  final String? prefillTitle;
  final String? prefillPropertyId;
  final String? prefillTechnicianId;
  final String? prefillDescription;
  final String? prefillAssetId;
  final String? prefillPriority;
  final String? prefillPmScheduleId;
  final List<String>? prefillPmScheduleIds;
  final List<String>? prefillAdditionalPropertyIds;

  const WorkOrderFormScreen({
    super.key,
    this.prefillTitle,
    this.prefillPropertyId,
    this.prefillTechnicianId,
    this.prefillDescription,
    this.prefillAssetId,
    this.prefillPriority,
    this.prefillPmScheduleId,
    this.prefillPmScheduleIds,
    this.prefillAdditionalPropertyIds,
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
  List<String> _selectedPropertyIds = [];
  String? _selectedTechnicianId;
  List<String> _ccUserIds = [];
  bool _saving = false;
  bool _loading = true;

  List<Map<String, dynamic>> _properties = [];
  List<Map<String, dynamic>> _technicians = [];
  List<Map<String, dynamic>> _allUsers = [];

  // Image picker
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _pickedImages = [];
  final List<Uint8List> _imageBytes = [];

  @override
  void initState() {
    super.initState();
    if (widget.prefillTitle != null) {
      _titleController.text = widget.prefillTitle!;
    }
    if (widget.prefillDescription != null) {
      _descriptionController.text = widget.prefillDescription!;
    }
    if (widget.prefillPropertyId != null) {
      _selectedPropertyIds = [
        widget.prefillPropertyId!,
        ...?widget.prefillAdditionalPropertyIds,
      ];
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
        _service.getUsers(),
      ]);
      _properties = results[0];
      final allUsers = results[1];
      _allUsers = allUsers;
      final currentRole = AuthStateService().currentRole;
      if (currentRole == UserRole.caretaker) {
        _technicians = allUsers
            .where((u) => u['role'] == 'technician' || u['role'] == 'caretaker')
            .toList();
      } else {
        _technicians = allUsers;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: ${friendlyError(e)}')));
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

    if (_selectedPropertyIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรุณาเลือกอย่างน้อย 1 บ้าน')),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      // Upload images in parallel
      final photoUrls = <String>[];
      final uploadFutures = <Future<String?>>[];
      for (int i = 0; i < _imageBytes.length; i++) {
        final bytes = _imageBytes[i];
        final ext = uploadExtension(_pickedImages[i]);
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

      final data = <String, dynamic>{
        'title': _titleController.text.trim(),
        // primary property (บ้านแรกที่เลือก)
        'property_id': _selectedPropertyIds.first,
        'priority': _priority,
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'assigned_to': _selectedTechnicianId,
        'status': 'open',
        if (widget.prefillAssetId != null) 'asset_id': widget.prefillAssetId,
        if (widget.prefillPmScheduleId != null)
          'pm_schedule_id': widget.prefillPmScheduleId,
        if (widget.prefillPmScheduleIds != null &&
            widget.prefillPmScheduleIds!.isNotEmpty)
          'pm_schedule_ids': widget.prefillPmScheduleIds,
        if (photoUrls.isNotEmpty) 'photo_urls': photoUrls,
        // บ้านเพิ่มเติม (ถ้าเลือกมากกว่า 1)
        if (_selectedPropertyIds.length > 1)
          'additional_property_ids': _selectedPropertyIds.sublist(1),
        // CC users
        if (_ccUserIds.isNotEmpty) 'cc_user_ids': _ccUserIds,
      };

      await _service.createWorkOrder(data);

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
        ).showSnackBar(SnackBar(content: Text('สร้างใบงานล้มเหลว: ${friendlyError(e)}')));
      }
    }
    if (mounted) setState(() => _saving = false);
  }

  Future<void> _pickImages() async {
    final source = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('ถ่ายรูป (กล้อง)'),
              onTap: () => Navigator.pop(ctx, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('เลือกจากคลังภาพ'),
              onTap: () => Navigator.pop(ctx, 'gallery'),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;

    try {
      if (source == 'camera') {
        final image = await pickUploadImage(_picker, ImageSource.camera);
        if (image == null) return;
        final bytes = await image.readAsBytes();
        setState(() {
          _pickedImages.add(image);
          _imageBytes.add(bytes);
        });
      } else {
        final images = await pickUploadImages(_picker);
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('เลือกรูปภาพล้มเหลว: ${friendlyError(e)}')));
      }
    }
  }

  // ─── Property multi-select dialog ────────────────────
  Future<void> _showPropertyPicker() async {
    final tempSelected = Set<String>.from(_selectedPropertyIds);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('เลือกบ้าน'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: _properties.map((prop) {
                final id = prop['id'] as String;
                return CheckboxListTile(
                  title: Text(prop['name'] as String),
                  value: tempSelected.contains(id),
                  onChanged: (checked) {
                    setDialogState(() {
                      if (checked == true) {
                        tempSelected.add(id);
                      } else {
                        tempSelected.remove(id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ตกลง'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      setState(() => _selectedPropertyIds = tempSelected.toList());
    }
  }

  // ─── CC multi-select dialog ───────────────────────────
  Future<void> _showCcPicker() async {
    final tempSelected = Set<String>.from(_ccUserIds);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('เพิ่ม CC (แจ้งสำเนา)'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'เลือกผู้รับสำเนาการแจ้งเตือน (LINE + in-app)',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: _allUsers.map((t) {
                      final id = t['id'] as String;
                      // ไม่แสดงคนที่เป็น assigned_to อยู่แล้ว
                      if (id == _selectedTechnicianId) return const SizedBox.shrink();
                      return CheckboxListTile(
                        title: Text(t['full_name'] as String? ?? '-'),
                        subtitle: Text(_getRoleLabel(t['role'] as String?)),
                        value: tempSelected.contains(id),
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              tempSelected.add(id);
                            } else {
                              tempSelected.remove(id);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ตกลง'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      setState(() {
        // ลบ assigned_to ออกจาก CC ถ้าถูกเลือก
        tempSelected.remove(_selectedTechnicianId);
        _ccUserIds = tempSelected.toList();
      });
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

  String? _getUserName(String userId) {
    try {
      return _allUsers
          .firstWhere((t) => t['id'] == userId)['full_name'] as String?;
    } catch (_) {
      return null;
    }
  }

  String? _getPropertyName(String propertyId) {
    try {
      return _properties
          .firstWhere((p) => p['id'] == propertyId)['name'] as String?;
    } catch (_) {
      return null;
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
                    // ─── หัวข้องาน ────────────────────────────
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

                    // ─── เลือกบ้าน (multi-select) ─────────────
                    _buildPropertySection(),
                    const SizedBox(height: 16),

                    // ─── ผู้รับผิดชอบหลัก (1 คน) ─────────────
                    DropdownButtonFormField<String?>(
                      value: _selectedTechnicianId,
                      decoration: const InputDecoration(
                        labelText: 'รับผิดชอบโดย (หลัก)',
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
                      onChanged: (v) {
                        setState(() {
                          _selectedTechnicianId = v;
                          // ลบออกจาก CC ถ้าเลือกเป็น assigned_to
                          _ccUserIds.remove(v);
                        });
                      },
                    ),
                    const SizedBox(height: 16),

                    // ─── CC (แจ้งสำเนา หลายคน) ───────────────
                    _buildCcSection(),
                    const SizedBox(height: 16),

                    // ─── ความสำคัญ ───────────────────────────
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
                        DropdownMenuItem(
                          value: 'urgent',
                          child: Text('เร่งด่วน'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _priority = v ?? 'medium'),
                    ),
                    const SizedBox(height: 16),

                    // ─── รายละเอียด ───────────────────────────
                    TextFormField(
                      controller: _descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'รายละเอียด',
                        prefixIcon: Icon(Icons.description),
                      ),
                      maxLines: 4,
                    ),
                    const SizedBox(height: 16),

                    // ─── รูปภาพ ───────────────────────────────
                    if (_imageBytes.isNotEmpty) ...[
                      SizedBox(
                        height: 100,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _imageBytes.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
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

                    // ─── บันทึก ───────────────────────────────
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

  // ─── Widget: เลือกบ้าน (multi-select) ─────────────────
  Widget _buildPropertySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.home, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            const Text(
              'บ้าน *',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _showPropertyPicker,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('เลือกบ้าน'),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ],
        ),
        if (_selectedPropertyIds.isEmpty)
          GestureDetector(
            onTap: _showPropertyPicker,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: const Text(
                'กรุณาเลือกอย่างน้อย 1 บ้าน',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          )
        else ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _selectedPropertyIds.map((id) {
              final name = _getPropertyName(id) ?? id;
              return Chip(
                label: Text(name, style: const TextStyle(fontSize: 12)),
                onDeleted: () =>
                    setState(() => _selectedPropertyIds.remove(id)),
                deleteIconColor: Colors.red.shade400,
                backgroundColor: Colors.blue.shade50,
              );
            }).toList(),
          ),
          const SizedBox(height: 4),
          if (_selectedPropertyIds.length > 1)
            Text(
              '${_selectedPropertyIds.length} บ้าน',
              style: TextStyle(
                  color: Colors.blue.shade700,
                  fontSize: 11),
            ),
        ],
        const Divider(height: 16),
      ],
    );
  }

  // ─── Widget: CC users ──────────────────────────────────
  Widget _buildCcSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.people_outline, size: 20, color: Colors.grey),
            const SizedBox(width: 8),
            const Text(
              'CC (แจ้งสำเนา)',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _showCcPicker,
              icon: const Icon(Icons.person_add_alt_1, size: 16),
              label: const Text('เพิ่ม CC'),
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              ),
            ),
          ],
        ),
        if (_ccUserIds.isEmpty)
          GestureDetector(
            onTap: _showCcPicker,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: const Text(
                'ไม่มี (ไม่บังคับ)',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ),
          )
        else ...[
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _ccUserIds.map((id) {
              final name = _getUserName(id) ?? id;
              return Chip(
                avatar: const Icon(Icons.person_outline, size: 14),
                label: Text(name, style: const TextStyle(fontSize: 12)),
                onDeleted: () =>
                    setState(() => _ccUserIds.remove(id)),
                deleteIconColor: Colors.red.shade400,
                backgroundColor: Colors.orange.shade50,
              );
            }).toList(),
          ),
        ],
        const Divider(height: 16),
      ],
    );
  }
}
