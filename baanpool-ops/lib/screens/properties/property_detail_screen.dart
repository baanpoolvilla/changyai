import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/property.dart';
import '../../models/asset.dart';
import '../../models/user.dart';
import '../../services/auth_state_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/error_message.dart';

class PropertyDetailScreen extends StatefulWidget {
  final String propertyId;

  const PropertyDetailScreen({super.key, required this.propertyId});

  @override
  State<PropertyDetailScreen> createState() => _PropertyDetailScreenState();
}

class _PropertyDetailScreenState extends State<PropertyDetailScreen> {
  final _authState = AuthStateService();
  final _service = SupabaseService(Supabase.instance.client);
  Property? _property;
  List<Asset> _assets = [];
  Map<String, DateTime?> _lastMaintenanceDates = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getProperty(widget.propertyId),
        _service.getAssets(propertyId: widget.propertyId),
      ]);
      _property = Property.fromJson(results[0] as Map<String, dynamic>);
      _assets = (results[1] as List<Map<String, dynamic>>)
          .map((e) => Asset.fromJson(e))
          .toList();

      // Load last maintenance dates for all assets
      if (_assets.isNotEmpty) {
        _lastMaintenanceDates = await _service.getLastMaintenanceDates(
          _assets.map((a) => a.id).toList(),
        );
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

  bool _canAddAssetsForProperty() {
    final property = _property;
    if (property == null) return false;

    final role = _authState.currentRole;
    if (role.canManageProperties) return true;

    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    return role == UserRole.caretaker &&
        property.caretakerId != null &&
        property.caretakerId == currentUserId;
  }

  Future<void> _deleteProperty() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันลบบ้าน'),
        content: const Text(
          'ลบบ้านนี้จะลบอุปกรณ์และข้อมูลที่เกี่ยวข้องทั้งหมด',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _service.deleteProperty(widget.propertyId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ลบบ้านสำเร็จ')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ลบล้มเหลว: ${friendlyError(e)}')));
      }
    }
  }

  Future<void> _showAddAssetDialog() async {
    if (!_canAddAssetsForProperty()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ไม่มีสิทธิ์เพิ่มอุปกรณ์ในบ้านนี้'),
          ),
        );
      }
      return;
    }

    final nameCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    Uint8List? imageBytes;
    String? imageName;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('เพิ่มอุปกรณ์'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'ชื่ออุปกรณ์ *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'หมายเหตุ'),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                // Image picker
                InkWell(
                  onTap: () async {
                    final picker = ImagePicker();
                    final picked = await picker.pickImage(
                      source: ImageSource.gallery,
                      maxWidth: 1024,
                      maxHeight: 1024,
                      imageQuality: 80,
                    );
                    if (picked != null) {
                      final bytes = await picked.readAsBytes();
                      setDialogState(() {
                        imageBytes = bytes;
                        imageName = picked.name;
                      });
                    }
                  },
                  child: Container(
                    height: 150,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(ctx).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: imageBytes != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(imageBytes!, fit: BoxFit.cover),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo,
                                size: 40,
                                color: Theme.of(ctx).colorScheme.outline,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'เพิ่มรูปอุปกรณ์',
                                style: TextStyle(
                                  color: Theme.of(ctx).colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
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
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('เพิ่ม'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    try {
      // Upload image if selected (graceful — asset is created even if upload fails)
      String? imageUrl;
      if (imageBytes != null) {
        try {
          final ext = imageName?.split('.').last ?? 'jpg';
          final path =
              'assets/${widget.propertyId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
          imageUrl = await _service.uploadFile(
            'asset-images',
            path,
            imageBytes!,
          );
        } catch (uploadErr) {
          debugPrint('Image upload failed: $uploadErr');
          // Continue without image
        }
      }

      await _service.createAsset({
        'property_id': widget.propertyId,
        'name': nameCtrl.text.trim(),
        'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        'image_url': imageUrl,
      });
      if (mounted) {
        final msg = imageBytes != null && imageUrl == null
            ? 'เพิ่มอุปกรณ์สำเร็จ (อัปโหลดรูปไม่สำเร็จ — กรุณาสร้าง Storage bucket "asset-images" ใน Supabase)'
            : 'เพิ่มอุปกรณ์สำเร็จ';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
      }
      _load();
    } catch (e) {
      if (mounted) {
        final message = e is PostgrestException && e.code == '42501'
            ? 'เพิ่มอุปกรณ์ไม่สำเร็จ: ฐานข้อมูลยังไม่เปิดสิทธิ์ผู้ดูแลบ้านสำหรับบ้านนี้ กรุณารัน migration ล่าสุด'
            : 'เพิ่มอุปกรณ์ล้มเหลว: ${friendlyError(e)}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('รายละเอียดบ้าน')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_property == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('รายละเอียดบ้าน')),
        body: const Center(child: Text('ไม่พบข้อมูลบ้าน')),
      );
    }

    final p = _property!;
    final canAddAssets = _canAddAssetsForProperty();

    return Scaffold(
      appBar: AppBar(
        title: Text(p.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () async {
              await context.push('/properties/${p.id}/edit');
              _load();
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _deleteProperty,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Property info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ข้อมูลบ้าน', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (p.caretakerName != null)
                      _infoRow(
                        Icons.home_work,
                        'ผู้จัดการบ้าน',
                        p.caretakerName!,
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Assets section header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'อุปกรณ์ (${_assets.length})',
                  style: theme.textTheme.titleMedium,
                ),
                if (canAddAssets)
                  FilledButton.tonalIcon(
                    onPressed: _showAddAssetDialog,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('เพิ่มอุปกรณ์'),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (_assets.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.devices_other,
                          size: 48,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 8),
                        const Text('ยังไม่มีอุปกรณ์'),
                      ],
                    ),
                  ),
                ),
              )
            else
              ..._assets.map((a) {
                final lastMaint = _lastMaintenanceDates[a.id];
                final lastMaintText = lastMaint != null
                    ? '🔧 ล่าสุด: ${lastMaint.day}/${lastMaint.month}/${lastMaint.year}'
                    : '🔧 ยังไม่เคย maintenance';
                return Card(
                  child: ListTile(
                    leading: a.imageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              a.imageUrl!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const CircleAvatar(child: Icon(Icons.build)),
                            ),
                          )
                        : const CircleAvatar(child: Icon(Icons.build)),
                    title: Text(a.name),
                    subtitle: Text(
                      [if (a.notes != null) a.notes!, lastMaintText].join('\n'),
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      await context.push('/assets/${a.id}');
                      _load();
                    },
                  ),
                );
              }),
          ],
        ),
      ),
      floatingActionButton: canAddAssets
          ? FloatingActionButton(
              onPressed: _showAddAssetDialog,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.labelSmall),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
