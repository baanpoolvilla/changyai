import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/asset.dart';
import '../../models/pm_schedule.dart';
import '../../models/user.dart';
import '../../services/auth_state_service.dart';
import '../../services/supabase_service.dart';
import '../../services/notification_service.dart';
import '../../utils/error_message.dart';
import '../../widgets/cc_picker_field.dart';

class AssetDetailScreen extends StatefulWidget {
  final String assetId;

  const AssetDetailScreen({super.key, required this.assetId});

  @override
  State<AssetDetailScreen> createState() => _AssetDetailScreenState();
}

class _AssetDetailScreenState extends State<AssetDetailScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  Asset? _asset;
  List<PmSchedule> _schedules = [];
  DateTime? _lastMaintenanceDate;
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
        _service.getAsset(widget.assetId),
        _service.getPmSchedules(assetId: widget.assetId),
        _service.getLastMaintenanceDate(widget.assetId),
      ]);
      _asset = Asset.fromJson(results[0] as Map<String, dynamic>);
      _schedules = (results[1] as List<Map<String, dynamic>>)
          .map((e) => PmSchedule.fromJson(e))
          .toList();
      _lastMaintenanceDate = results[2] as DateTime?;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: ${friendlyError(e)}')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _deleteAsset() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันลบอุปกรณ์'),
        content: const Text(
          'ลบอุปกรณ์นี้จะลบ PM Schedule ที่เกี่ยวข้องทั้งหมด',
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
      // ลบ PM Schedule ที่ผูกกับอุปกรณ์ก่อน (FK เป็น SET NULL จึงไม่ cascade เอง)
      for (final s in _schedules) {
        await _service.deletePmSchedule(s.id);
      }
      await _service.deleteAsset(widget.assetId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('ลบอุปกรณ์สำเร็จ')));
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

  Future<void> _showEditAssetDialog() async {
    if (_asset == null) return;
    final a = _asset!;
    final nameCtrl = TextEditingController(text: a.name);
    final notesCtrl = TextEditingController(text: a.notes ?? '');
    Uint8List? imageBytes;
    String? imageName;
    String? currentImageUrl = a.imageUrl;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('แก้ไขอุปกรณ์'),
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
                        currentImageUrl = null; // replaced by new image
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
                        : currentImageUrl != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              currentImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  _imagePlaceholder(ctx),
                            ),
                          )
                        : _imagePlaceholder(ctx),
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
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
    if (result != true) return;
    try {
      // Upload new image if selected (graceful — continue even if upload fails)
      String? imageUrl = a.imageUrl;
      if (imageBytes != null) {
        try {
          final ext = imageName?.split('.').last ?? 'jpg';
          final path =
              'assets/${a.propertyId}/${DateTime.now().millisecondsSinceEpoch}.$ext';
          imageUrl = await _service.uploadFile(
            'asset-images',
            path,
            imageBytes!,
          );
        } catch (uploadErr) {
          debugPrint('Image upload failed: $uploadErr');
          // Keep existing imageUrl
        }
      }

      await _service.updateAsset(widget.assetId, {
        'name': nameCtrl.text.trim(),
        'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
        'image_url': imageUrl,
      });
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('แก้ไขล้มเหลว: ${friendlyError(e)}')));
      }
    }
  }

  /// แสดงตัวอย่างวันที่ของ 1 รอบปี + วันแรกของปีถัดไป
  /// ใช้ SupabaseService.nextDueSlot ตัวจริง — ที่โชว์จึงตรงกับที่ระบบคำนวณเสมอ
  Widget _cyclePreview(
    BuildContext ctx, {
    required DateTime anchor,
    required PmFrequency frequency,
    required int rounds,
  }) {
    final dates = <DateTime>[anchor];
    var cursor = anchor;
    for (var i = 0; i < rounds; i++) {
      cursor = SupabaseService.nextDueSlot(
        anchor: anchor,
        frequency: frequency,
        roundsPerYear: rounds,
        after: cursor,
      );
      dates.add(cursor);
    }
    final theme = Theme.of(ctx);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'รอบที่จะเกิดขึ้น',
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          for (var i = 0; i < dates.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                i == dates.length - 1
                    ? '↻ ${_fmt(dates[i])}  (วนกลับรอบแรก ปีถัดไป)'
                    : '${i + 1}. ${_fmt(dates[i])}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: i == dates.length - 1
                      ? theme.colorScheme.primary
                      : null,
                  fontWeight: i == dates.length - 1 ? FontWeight.bold : null,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  Widget _imagePlaceholder(BuildContext ctx) {
    return Column(
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
          style: TextStyle(color: Theme.of(ctx).colorScheme.outline),
        ),
      ],
    );
  }

  Future<void> _showAddScheduleDialog() async {
    if (_asset == null) return;

    final titleCtrl = TextEditingController(text: _asset!.name);
    final descCtrl = TextEditingController();
    PmFrequency selectedFreq = PmFrequency.month1;
    PmMode selectedMode = PmMode.continuous;
    int? selectedRounds; // รอบต่อปี (โหมด yearlyRounds)
    int totalRounds = 6; // จำนวนครั้งทั้งหมด (โหมด limitedCount)
    DateTime nextDue = DateTime.now().add(const Duration(days: 30));
    String? selectedTechId;
    final ccUserIds = <String>{};

    // Load technicians
    List<Map<String, dynamic>> technicians = [];
    try {
      technicians = await _service.getTechnicians();
    } catch (_) {}

    // Also load all users as potential assignees
    if (technicians.isEmpty) {
      try {
        technicians = await _service.getUsers();
      } catch (_) {}
    }

    if (!mounted) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('เพิ่ม PM Schedule'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'ชื่องาน PM *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'รายละเอียด'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                // ─── ประเภท PM: เลือกอันเดียว แล้วค่อยโชว์ช่องที่เกี่ยว ───
                DropdownButtonFormField<PmMode>(
                  value: selectedMode,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'ประเภท PM'),
                  items: PmMode.values
                      .map(
                        (m) => DropdownMenuItem(
                          value: m,
                          child: Text(m.displayName),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) {
                      setDialogState(() {
                        selectedMode = v;
                        selectedRounds = v == PmMode.yearlyRounds
                            ? selectedFreq.maxRoundsPerYear - 1
                            : null;
                      });
                    }
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    selectedMode.description,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(ctx).colorScheme.outline,
                    ),
                  ),
                ),
                // ความถี่ — ไม่ใช้กับแบบจำกัดจำนวนครั้ง (นัดวันเองทีละครั้ง)
                if (selectedMode != PmMode.limitedCount) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<PmFrequency>(
                    value: selectedFreq,
                    decoration: const InputDecoration(labelText: 'ความถี่'),
                    items: PmFrequency.values
                        .map(
                          (f) => DropdownMenuItem(
                            value: f,
                            child: Text(f.displayName),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        setDialogState(() {
                          selectedFreq = v;
                          if (selectedMode == PmMode.yearlyRounds) {
                            selectedRounds = v.maxRoundsPerYear > 1
                                ? v.maxRoundsPerYear - 1
                                : 1;
                          }
                        });
                      }
                    },
                  ),
                ],
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    selectedMode == PmMode.limitedCount
                        ? 'นัดวันครั้งแรก'
                        : 'วันครบกำหนดรอบแรก',
                  ),
                  subtitle: Text(
                    '${nextDue.day}/${nextDue.month}/${nextDue.year}',
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: nextDue,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(
                        const Duration(days: 365 * 5),
                      ),
                    );
                    if (picked != null) {
                      setDialogState(() => nextDue = picked);
                    }
                  },
                ),
                // ─── โหมด: ทำเป็นรอบต่อปี ───
                if (selectedMode == PmMode.yearlyRounds) ...[
                  if (selectedFreq.maxRoundsPerYear > 1) ...[
                    DropdownButtonFormField<int>(
                      value: selectedRounds,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'ทำกี่รอบต่อปี',
                      ),
                      items: [
                        for (var i = 1; i < selectedFreq.maxRoundsPerYear; i++)
                          DropdownMenuItem(value: i, child: Text('$i รอบ')),
                      ],
                      onChanged: (v) =>
                          setDialogState(() => selectedRounds = v),
                    ),
                    if (selectedRounds != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: _cyclePreview(
                          ctx,
                          anchor: nextDue,
                          frequency: selectedFreq,
                          rounds: selectedRounds!,
                        ),
                      ),
                  ] else
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        selectedFreq.weekDays != null
                            ? 'ความถี่แบบสัปดาห์ยังไม่รองรับการกำหนดรอบต่อปี '
                                '— ระบบจะทำต่อเนื่องให้'
                            : 'ความถี่ ${selectedFreq.displayName} '
                                'ทำปีละครั้งอยู่แล้ว จึงไม่ต้องกำหนดรอบ',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
                // ─── โหมด: จำกัดจำนวนครั้ง ───
                if (selectedMode == PmMode.limitedCount)
                  DropdownButtonFormField<int>(
                    value: totalRounds,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'ทำทั้งหมดกี่ครั้ง',
                      helperText: 'จบครั้งหนึ่งแล้วค่อยนัดวันครั้งถัดไป '
                          'ครบแล้วระบบปิด PM ให้เอง',
                      helperMaxLines: 2,
                    ),
                    items: [
                      for (var i = 2; i <= 24; i++)
                        DropdownMenuItem(value: i, child: Text('$i ครั้ง')),
                    ],
                    onChanged: (v) =>
                        setDialogState(() => totalRounds = v ?? 6),
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: selectedTechId,
                  decoration: const InputDecoration(labelText: 'มอบหมายช่าง'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('ไม่ระบุ')),
                    ...technicians.map(
                      (t) => DropdownMenuItem(
                        value: t['id'] as String,
                        child: Text(
                          t['full_name'] as String? ?? t['email'] as String,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setDialogState(() {
                    selectedTechId = v;
                    // ผู้รับผิดชอบไม่ต้องอยู่ใน CC จะได้ไม่แจ้งซ้ำ
                    if (v != null) ccUserIds.remove(v);
                  }),
                ),
                const SizedBox(height: 12),
                CcPickerField(
                  allUsers: technicians,
                  selected: ccUserIds,
                  excludeUserId: selectedTechId,
                  onChanged: () => setDialogState(() {}),
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
                if (titleCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('กรุณากรอกชื่องาน PM')),
                  );
                  return;
                }
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
      await _service.createPmSchedule({
        'property_id': _asset!.propertyId,
        'asset_id': widget.assetId,
        'title': titleCtrl.text.trim(),
        'description': descCtrl.text.trim().isEmpty
            ? null
            : descCtrl.text.trim(),
        'frequency': selectedFreq.toDbValue,
        'next_due_date': nextDue.toIso8601String().split('T').first,
        // anchor = วันกำหนดรอบแรก — ยึดไว้ไม่ให้วันดริฟต์ตามวันจบงาน
        'anchor_date': nextDue.toIso8601String().split('T').first,
        // ประเภท PM แยกจากข้อมูล — ต้องมีได้แค่อย่างใดอย่างหนึ่ง (DB มี CHECK คุมอยู่)
        // ความถี่ที่กำหนดรอบไม่ได้ (สัปดาห์ / 12 เดือน) → null = ต่อเนื่อง
        // กัน 0 หรือ -1 หลุดไปชน CHECK (rounds_per_year BETWEEN 1 AND 12)
        'rounds_per_year': selectedMode == PmMode.yearlyRounds &&
                selectedFreq.maxRoundsPerYear > 1
            ? selectedRounds
            : null,
        'total_rounds':
            selectedMode == PmMode.limitedCount ? totalRounds : null,
        'assigned_to': selectedTechId,
        'cc_user_ids': ccUserIds.toList(),
      });

      // When no technician is assigned, notify the property manager (caretaker)
      if (selectedTechId == null) {
        await _notifyManagerForUnassignedPm(
          pmTitle: titleCtrl.text.trim(),
          nextDueDate: nextDue,
          frequency: selectedFreq,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('เพิ่ม PM Schedule สำเร็จ')),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เพิ่ม PM Schedule ล้มเหลว: ${friendlyError(e)}')),
        );
      }
    }
  }

  /// สร้าง in-app notification สำหรับผู้ดูแลบ้าน เมื่อสร้าง PM ใหม่
  /// (LINE จะแจ้งเฉพาะวันครบกำหนดผ่าน check_pm_due_schedules RPC)
  Future<void> _notifyManagerForUnassignedPm({
    required String pmTitle,
    required DateTime nextDueDate,
    required PmFrequency frequency,
  }) async {
    if (_asset == null) return;
    final propertyId = _asset!.propertyId;
    final assetName = _asset!.name;

    try {
      final propData = await _service.getProperty(propertyId);
      final propertyName = propData['name'] as String? ?? 'ไม่ทราบ';
      final caretakerId = propData['caretaker_id'] as String?;

      final dateStr =
          '${nextDueDate.day}/${nextDueDate.month}/${nextDueDate.year}';

      // In-app notification เฉพาะผู้ดูแลบ้าน — LINE จะแจ้งเมื่อถึงกำหนด
      if (caretakerId != null && caretakerId.isNotEmpty) {
        try {
          final client = Supabase.instance.client;
          await client.from('notifications').insert({
            'user_id': caretakerId,
            'title': '📋 PM ใหม่: $pmTitle',
            'body':
                '🔧 $pmTitle\n🏠 บ้าน: $propertyName\n⚙️ อุปกรณ์: $assetName\n📅 กำหนด: $dateStr',
            'type': 'pm',
          });
        } catch (_) {}
      }

      await NotificationService().refresh();
    } catch (e) {
      debugPrint('Notify caretaker for PM error: $e');
    }
  }

  void _createWorkOrderFromPm(PmSchedule s) {
    final dateStr =
        '${s.nextDueDate.day}/${s.nextDueDate.month}/${s.nextDueDate.year}';
    final description =
        'PM: ${s.title}\nกำหนด: $dateStr\nความถี่: ${s.frequency.displayName}'
        '${s.description != null ? "\nรายละเอียด: ${s.description}" : ""}';

    final queryParams = <String, String>{
      'title': s.title,
      'propertyId': s.propertyId,
      'description': description,
      'assetId': widget.assetId,
    };
    if (s.assignedTo != null) {
      queryParams['technicianId'] = s.assignedTo!;
    } else {
      // Allow caretaker to assign work order to self
      final authState = AuthStateService();
      if (authState.currentRole == UserRole.caretaker &&
          authState.currentAppUser != null) {
        queryParams['technicianId'] = authState.currentAppUser!.id;
      }
    }

    final uri = Uri(path: '/work-orders/new', queryParameters: queryParams);
    context.push(uri.toString());
  }

  Future<void> _deleteSchedule(PmSchedule s) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันลบ PM Schedule'),
        content: Text('ลบ "${s.title}" ?'),
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
      await _service.deletePmSchedule(s.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ลบล้มเหลว: ${friendlyError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('รายละเอียดอุปกรณ์')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_asset == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('รายละเอียดอุปกรณ์')),
        body: const Center(child: Text('ไม่พบข้อมูลอุปกรณ์')),
      );
    }

    final a = _asset!;

    return Scaffold(
      appBar: AppBar(
        title: Text(a.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: _showEditAssetDialog,
          ),
          IconButton(icon: const Icon(Icons.delete), onPressed: _deleteAsset),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Asset image
            if (a.imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  a.imageUrl!,
                  width: double.infinity,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Asset info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ข้อมูลอุปกรณ์', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 12),
                    if (a.installDate != null)
                      _infoRow(
                        Icons.calendar_today,
                        'วันติดตั้ง',
                        '${a.installDate!.day}/${a.installDate!.month}/${a.installDate!.year}',
                      ),
                    if (a.warrantyExpiry != null)
                      _infoRow(
                        a.isWarrantyExpired
                            ? Icons.warning
                            : Icons.verified_user,
                        'ประกัน',
                        '${a.warrantyExpiry!.day}/${a.warrantyExpiry!.month}/${a.warrantyExpiry!.year}'
                            '${a.isWarrantyExpired ? " (หมดแล้ว)" : ""}',
                      ),
                    if (a.notes != null)
                      _infoRow(Icons.notes, 'หมายเหตุ', a.notes!),
                    // Last maintenance date
                    _infoRow(
                      Icons.build_circle,
                      'Maintenance ล่าสุด',
                      _lastMaintenanceDate != null
                          ? '${_lastMaintenanceDate!.day}/${_lastMaintenanceDate!.month}/${_lastMaintenanceDate!.year}'
                          : 'ยังไม่เคย',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // PM Schedules section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'PM Schedule (${_schedules.length})',
                  style: theme.textTheme.titleMedium,
                ),
                FilledButton.tonalIcon(
                  onPressed: _showAddScheduleDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('เพิ่ม Schedule'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_schedules.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.schedule,
                          size: 48,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(height: 8),
                        const Text('ยังไม่มี PM Schedule'),
                      ],
                    ),
                  ),
                ),
              )
            else
              ..._schedules.map((s) => _buildScheduleCard(s)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddScheduleDialog,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildScheduleCard(PmSchedule s) {
    final theme = Theme.of(context);
    final daysUntilDue = s.nextDueDate.difference(DateTime.now()).inDays;
    final isOverdue = daysUntilDue < 0;
    final isDueSoon = daysUntilDue <= 7 && daysUntilDue >= 0;

    Color statusColor = theme.colorScheme.primary;
    String statusText = '$daysUntilDue วัน';
    if (isOverdue) {
      statusColor = Colors.red;
      statusText = 'เกินกำหนด ${-daysUntilDue} วัน';
    } else if (isDueSoon) {
      statusColor = Colors.orange;
      statusText = 'อีก $daysUntilDue วัน';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.title, style: theme.textTheme.titleSmall),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: () => _deleteSchedule(s),
                ),
              ],
            ),
            if (s.isDueSoon || daysUntilDue < 0) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _createWorkOrderFromPm(s),
                  icon: const Icon(Icons.assignment_add, size: 18),
                  label: const Text('สร้างใบงาน'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: statusColor,
                    side: BorderSide(color: statusColor),
                  ),
                ),
              ),
            ],
            if (s.description != null) ...[
              const SizedBox(height: 4),
              Text(s.description!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              children: [
                _chip(Icons.repeat, s.frequency.displayName),
                _chip(
                  Icons.calendar_today,
                  '${s.nextDueDate.day}/${s.nextDueDate.month}/${s.nextDueDate.year}',
                ),
                if (s.assignedToName != null)
                  _chip(Icons.person, s.assignedToName!),
                if (s.assignedTo != null && s.assignedToName == null)
                  _chip(Icons.person, 'มอบหมายแล้ว'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
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
