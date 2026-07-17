import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/pm_schedule.dart';
import '../../models/user.dart';
import '../../services/auth_state_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/thai_datetime.dart';
import '../../utils/page_wrapper.dart';
import '../../utils/error_message.dart';
import '../../widgets/cc_picker_field.dart';

/// สถานะ PM บนแดชบอร์ด — เรียงจากต้องรีบสุดไปปกติ
/// ทุกสถานะมี icon + ข้อความกำกับเสมอ ไม่ได้สื่อด้วยสีอย่างเดียว
enum _PmStatus {
  overdue,
  dueSoon,
  hasWorkOrder,
  awaitingSchedule,
  onTrack;

  String get label {
    switch (this) {
      case _PmStatus.overdue:
        return 'เกินกำหนด';
      case _PmStatus.dueSoon:
        return 'ใกล้ถึงกำหนด';
      case _PmStatus.hasWorkOrder:
        return 'เปิดใบงานแล้ว';
      case _PmStatus.awaitingSchedule:
        return 'รอนัดวัน';
      case _PmStatus.onTrack:
        return 'ตามกำหนด';
    }
  }

  /// คำอธิบายว่าสถานะนี้แปลว่าอะไร กันเข้าใจผิด
  String get hint {
    switch (this) {
      case _PmStatus.overdue:
        return 'เลยกำหนดแล้วและยังไม่มีใบงาน — ต้องรีบจัดการ';
      case _PmStatus.dueSoon:
        return 'ครบกำหนดภายใน 7 วัน';
      case _PmStatus.hasWorkOrder:
        return 'มีใบงานรอดำเนินการอยู่แล้ว';
      case _PmStatus.awaitingSchedule:
        return 'ทำครั้งล่าสุดเสร็จแล้ว รอนัดวันครั้งถัดไป';
      case _PmStatus.onTrack:
        return 'ยังไม่ถึงกำหนด เกิน 7 วันขึ้นไป';
    }
  }

  IconData get icon {
    switch (this) {
      case _PmStatus.overdue:
        return Icons.error;
      case _PmStatus.dueSoon:
        return Icons.warning_amber_rounded;
      case _PmStatus.hasWorkOrder:
        return Icons.assignment_turned_in;
      case _PmStatus.awaitingSchedule:
        return Icons.event_repeat;
      case _PmStatus.onTrack:
        return Icons.check_circle;
    }
  }

  Color get color {
    switch (this) {
      case _PmStatus.overdue:
        return const Color(0xFFD32F2F); // critical
      case _PmStatus.dueSoon:
        return const Color(0xFFE65100); // warning
      case _PmStatus.hasWorkOrder:
        return const Color(0xFF1565C0); // info
      case _PmStatus.awaitingSchedule:
        return const Color(0xFF6A1B9A); // waiting
      case _PmStatus.onTrack:
        return const Color(0xFF2E7D32); // good
    }
  }
}

class PmScheduleScreen extends StatefulWidget {
  final String? initialPropertyId;

  const PmScheduleScreen({super.key, this.initialPropertyId});

  @override
  State<PmScheduleScreen> createState() => _PmScheduleScreenState();
}

class _PmScheduleScreenState extends State<PmScheduleScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  List<PmSchedule> _schedules = [];
  Map<String, String> _propertyNames = {}; // property_id → name
  Map<String, String> _assetNames = {}; // asset_id → name
  Map<String, String> _pendingWorkOrderIds = {}; // pmScheduleId → workOrderId
  bool _loading = true;
  String? _selectedPropertyGroup; // null = ทุกกลุ่ม
  String? _selectedPropertyId; // null = ทั้งหมด
  _PmStatus? _selectedStatus; // null = ทุกสถานะ

  /// PM หลังกรองตามบ้านแล้ว — เป็นฐานของตัวเลขบนแดชบอร์ด
  List<PmSchedule> get _propertyFiltered {
    if (_selectedPropertyId != null) {
      return _schedules
          .where((s) => s.propertyId == _selectedPropertyId)
          .toList();
    }
    if (_selectedPropertyGroup == null) return _schedules;
    return _schedules.where((schedule) {
      final propertyName =
          schedule.propertyName ?? _propertyNames[schedule.propertyId];
      if (propertyName == null) return false;
      return _getPropertyGroup(propertyName) == _selectedPropertyGroup;
    }).toList();
  }

  /// PM ที่แสดงจริง = กรองบ้าน + กรองสถานะที่กดบนแดชบอร์ด
  List<PmSchedule> get _filteredSchedules {
    final base = _propertyFiltered;
    if (_selectedStatus == null) return base;
    return base.where((s) => _statusOf(s) == _selectedStatus).toList();
  }

  /// สถานะของ PM — เรียงตามความสำคัญ ตัวที่ match ก่อนชนะ
  /// จงใจให้ "เปิดใบงานแล้ว" มาก่อน "เกินกำหนด" เพราะถ้ามีใบงานรออยู่แล้ว
  /// = มีคนกำลังจัดการ ไม่ใช่งานที่ตกค้างรอคนทำ
  _PmStatus _statusOf(PmSchedule s) {
    if (s.awaitingSchedule) return _PmStatus.awaitingSchedule;
    if (_pendingWorkOrderIds.containsKey(s.id)) return _PmStatus.hasWorkOrder;
    final days = s.nextDueDate.difference(thaiNow()).inDays;
    if (days < 0) return _PmStatus.overdue;
    if (days <= 7) return _PmStatus.dueSoon;
    return _PmStatus.onTrack;
  }

  String _getPropertyGroup(String propertyName) {
    final match = RegExp(r'^([A-Za-z]+-[A-Za-z]+)').firstMatch(propertyName);
    if (match != null) return match.group(1)!.toUpperCase();

    final fallback = RegExp(r'^(.+?)\d+$').firstMatch(propertyName);
    if (fallback != null) return fallback.group(1)!.toUpperCase();

    return propertyName.toUpperCase();
  }

  void _resetPropertyFilters() {
    setState(() {
      _selectedPropertyGroup = null;
      _selectedPropertyId = null;
    });
  }


  void _togglePropertyGroup(String group) {
    setState(() {
      if (_selectedPropertyGroup == group) {
        _selectedPropertyGroup = null;
        _selectedPropertyId = null;
        return;
      }

      _selectedPropertyGroup = group;
      if (_selectedPropertyId != null) {
        final selectedName = _propertyNames[_selectedPropertyId!];
        if (selectedName == null || _getPropertyGroup(selectedName) != group) {
          _selectedPropertyId = null;
        }
      }
    });
  }

  void _toggleProperty(String propertyId) {
    setState(() {
      if (_selectedPropertyId == propertyId) {
        _selectedPropertyId = null;
        return;
      }

      _selectedPropertyId = propertyId;
      final selectedName = _propertyNames[propertyId];
      if (selectedName != null) {
        _selectedPropertyGroup = _getPropertyGroup(selectedName);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _selectedPropertyId = widget.initialPropertyId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getPmSchedules(),
        _service.getPropertyNamesOnly(),
      ]);
      final data = results[0] as List<Map<String, dynamic>>;
      final props = results[1] as List<Map<String, dynamic>>;

      _propertyNames = {
        for (final p in props) p['id'] as String: p['name'] as String,
      };
      if (_selectedPropertyId != null) {
        final selectedName = _propertyNames[_selectedPropertyId!];
        if (selectedName != null) {
          _selectedPropertyGroup = _getPropertyGroup(selectedName);
        }
      }

      _schedules = data.map((e) => PmSchedule.fromJson(e)).toList();

      // Load asset names for all unique asset_ids
      final assetIds = _schedules
          .where((s) => s.assetId != null)
          .map((s) => s.assetId!)
          .toSet()
          .toList();
      if (assetIds.isNotEmpty) {
        try {
          final assetData = await Supabase.instance.client
              .from('assets')
              .select('id, name')
              .inFilter('id', assetIds);
          _assetNames = {
            for (final a in assetData) a['id'] as String: a['name'] as String,
          };
        } catch (_) {}
      }

      // Load pending work orders linked to PM schedules
      final pmIds = _schedules.map((s) => s.id).toList();
      _pendingWorkOrderIds =
          await _service.getPendingWorkOrderIdsByPmSchedule(pmIds);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: ${friendlyError(e)}')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _createWorkOrderFromPm(PmSchedule s) async {
    final dateStr =
        '${s.nextDueDate.day}/${s.nextDueDate.month}/${s.nextDueDate.year}';
    final description =
        'PM: ${s.title}\nกำหนด: $dateStr\nความถี่: ${s.frequency.displayName}'
        '${s.description != null ? "\nรายละเอียด: ${s.description}" : ""}';

    final queryParams = <String, String>{
      'title': s.title,
      'propertyId': s.propertyId,
      'description': description,
      'pmScheduleId': s.id,
    };
    if (s.assetId != null) {
      queryParams['assetId'] = s.assetId!;
    }

    // Allow caretaker to assign to self
    final authState = AuthStateService();
    if (s.assignedTo != null) {
      queryParams['technicianId'] = s.assignedTo!;
    } else if (authState.currentRole == UserRole.caretaker) {
      queryParams['technicianId'] = authState.currentAppUser!.id;
    }

    final uri = Uri(path: '/work-orders/new', queryParameters: queryParams);
    await context.push(uri.toString());
    _load();
  }

  Future<void> _showCreatePmDialog() async {
    // Load properties, assets, and technicians in parallel
    List<Map<String, dynamic>> properties = [];
    List<Map<String, dynamic>> allAssets = [];
    List<Map<String, dynamic>> technicians = [];

    try {
      final results = await Future.wait([
        _service.getProperties(),
        _service.getUsers(),
      ]);
      properties = results[0];
      final allUsers = results[1];
      final currentRole = AuthStateService().currentRole;
      if (currentRole == UserRole.caretaker) {
        // Caretaker can assign to technicians + all caretakers (including themselves)
        technicians = allUsers
            .where((u) => u['role'] == 'technician' || u['role'] == 'caretaker')
            .toList();
      } else {
        technicians = allUsers;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: ${friendlyError(e)}')));
      }
      return;
    }

    if (!mounted) return;

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    PmFrequency selectedFreq = PmFrequency.month1;
    PmMode selectedMode = PmMode.continuous;
    int? selectedRounds; // รอบต่อปี (โหมด yearlyRounds)
    int totalRounds = 6; // จำนวนครั้งทั้งหมด (โหมด limitedCount)
    DateTime nextDue = DateTime.now().add(const Duration(days: 30));
    String? selectedTechId;
    final ccUserIds = <String>{};
    Set<String> selectedPropertyIds = {};
    Set<String> selectedAssetIds = {};
    Map<String, List<Map<String, dynamic>>> propertyAssetsMap = {};
    bool loadingAssets = false;
    bool propertySectionExpanded = true;
    bool assetSectionExpanded = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          Future<void> loadAssetsForProperties() async {
            if (selectedPropertyIds.isEmpty) {
              setDialogState(() {
                allAssets = [];
                propertyAssetsMap = {};
                selectedAssetIds.clear();
              });
              return;
            }
            setDialogState(() => loadingAssets = true);
            try {
              final Map<String, List<Map<String, dynamic>>> newMap = {};
              final futures = selectedPropertyIds.map(
                (pid) => _service.getAssets(propertyId: pid),
              );
              final results = await Future.wait(futures);
              int i = 0;
              final List<Map<String, dynamic>> combined = [];
              for (final pid in selectedPropertyIds) {
                newMap[pid] = results.elementAt(i);
                combined.addAll(results.elementAt(i));
                i++;
              }
              // Remove asset selections that are no longer valid
              final validAssetIds = combined
                  .map((a) => a['id'] as String)
                  .toSet();
              selectedAssetIds.removeWhere((id) => !validAssetIds.contains(id));
              setDialogState(() {
                allAssets = combined;
                propertyAssetsMap = newMap;
                loadingAssets = false;
                propertySectionExpanded = false;
                assetSectionExpanded = true;
              });
            } catch (e) {
              setDialogState(() => loadingAssets = false);
            }
          }

          // Group asset display by property
          List<Widget> buildAssetCheckboxes() {
            final widgets = <Widget>[];
            for (final pid in selectedPropertyIds) {
              final propAssets = propertyAssetsMap[pid] ?? [];
              if (propAssets.isEmpty) continue;
              final propName =
                  properties.firstWhere(
                        (p) => p['id'] == pid,
                        orElse: () => {'name': pid},
                      )['name']
                      as String;

              widgets.add(
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    propName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              );

              // Select all for this property
              final allIds = propAssets.map((a) => a['id'] as String).toSet();
              final allSelected = allIds.every(
                (id) => selectedAssetIds.contains(id),
              );
              widgets.add(
                CheckboxListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    'เลือกทั้งหมด (${propAssets.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  value: allSelected,
                  onChanged: (v) {
                    setDialogState(() {
                      if (v == true) {
                        selectedAssetIds.addAll(allIds);
                      } else {
                        selectedAssetIds.removeAll(allIds);
                      }
                    });
                  },
                ),
              );

              for (final asset in propAssets) {
                final aid = asset['id'] as String;
                final aName = asset['name'] as String;
                widgets.add(
                  CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(aName, style: const TextStyle(fontSize: 13)),
                    value: selectedAssetIds.contains(aid),
                    onChanged: (v) {
                      setDialogState(() {
                        if (v == true) {
                          selectedAssetIds.add(aid);
                        } else {
                          selectedAssetIds.remove(aid);
                        }
                      });
                    },
                  ),
                );
              }
            }
            return widgets;
          }

          return AlertDialog(
            title: const Text('สร้าง PM Schedule'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(
                        labelText: 'ชื่องาน PM *',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'รายละเอียด',
                      ),
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
                        decoration:
                            const InputDecoration(labelText: 'ความถี่'),
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
                              // รอบสูงสุดเปลี่ยนตามความถี่ → เลือกใหม่
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
                            for (var i = 1;
                                i < selectedFreq.maxRoundsPerYear;
                                i++)
                              DropdownMenuItem(
                                value: i,
                                child: Text('$i รอบ'),
                              ),
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
                    if (selectedMode == PmMode.limitedCount) ...[
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
                            DropdownMenuItem(
                              value: i,
                              child: Text('$i ครั้ง'),
                            ),
                        ],
                        onChanged: (v) => setDialogState(
                          () => totalRounds = v ?? 6,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String?>(
                      value: selectedTechId,
                      decoration: const InputDecoration(
                        labelText: 'มอบหมายช่าง',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('ไม่ระบุ'),
                        ),
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
                    // ─── CC (แจ้งสำเนา) ───────────────────────
                    CcPickerField(
                      allUsers: technicians,
                      selected: ccUserIds,
                      excludeUserId: selectedTechId,
                      onChanged: () => setDialogState(() {}),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    ExpansionTile(
                      initiallyExpanded: propertySectionExpanded,
                      tilePadding: EdgeInsets.zero,
                      title: Text(
                        'เลือกบ้าน${selectedPropertyIds.isNotEmpty ? ' (${selectedPropertyIds.length})' : ''}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onExpansionChanged: (v) {
                        setDialogState(() => propertySectionExpanded = v);
                      },
                      children: properties.map((p) {
                        final pid = p['id'] as String;
                        final pName = p['name'] as String;
                        return RadioListTile<String>(
                          dense: true,
                          visualDensity: VisualDensity.compact,
                          title: Text(
                            pName,
                            style: const TextStyle(fontSize: 13),
                          ),
                          value: pid,
                          groupValue: selectedPropertyIds.isNotEmpty
                              ? selectedPropertyIds.first
                              : null,
                          onChanged: (v) {
                            setDialogState(() {
                              selectedPropertyIds.clear();
                              if (v != null) {
                                selectedPropertyIds.add(v);
                              }
                              propertySectionExpanded = false;
                            });
                            loadAssetsForProperties();
                          },
                        );
                      }).toList(),
                    ),
                    if (selectedPropertyIds.isNotEmpty) ...[
                      ExpansionTile(
                        initiallyExpanded: assetSectionExpanded,
                        tilePadding: EdgeInsets.zero,
                        title: Text(
                          'เลือกอุปกรณ์${selectedAssetIds.isNotEmpty ? ' (${selectedAssetIds.length})' : ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        onExpansionChanged: (v) {
                          setDialogState(() => assetSectionExpanded = v);
                        },
                        children: [
                          if (loadingAssets)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (allAssets.isEmpty)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: Text(
                                'ไม่พบอุปกรณ์ในบ้านที่เลือก',
                                style: TextStyle(fontSize: 13),
                              ),
                            )
                          else
                            ...buildAssetCheckboxes(),
                        ],
                      ),
                    ],
                  ],
                ),
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
                  if (selectedPropertyIds.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('กรุณาเลือกบ้านอย่างน้อย 1 หลัง'),
                      ),
                    );
                    return;
                  }
                  if (selectedAssetIds.isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                        content: Text('กรุณาเลือกอุปกรณ์อย่างน้อย 1 รายการ'),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('สร้าง PM'),
              ),
            ],
          );
        },
      ),
    );

    if (result != true) return;

    try {
      // Build batch data: one PM schedule per selected asset
      final batchData = <Map<String, dynamic>>[];
      for (final assetId in selectedAssetIds) {
        // Find the propertyId for this asset
        final asset = allAssets.firstWhere((a) => a['id'] == assetId);
        final propertyId = asset['property_id'] as String;

        batchData.add({
          'property_id': propertyId,
          'asset_id': assetId,
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
      }

      await _service.createPmSchedulesBatch(batchData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'สร้าง PM Schedule สำเร็จ ${batchData.length} รายการ',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('สร้าง PM Schedule ล้มเหลว: ${friendlyError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Properties that have at least 1 PM schedule
    final usedPropertyIds = _schedules.map((s) => s.propertyId).toSet();
    final filterProperties = _propertyNames.entries
        .where((e) => usedPropertyIds.contains(e.key))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final groupedFilterProperties = <String, List<MapEntry<String, String>>>{};
    for (final entry in filterProperties) {
      final group = _getPropertyGroup(entry.value);
      groupedFilterProperties.putIfAbsent(group, () => []).add(entry);
    }
    final filterGroups = groupedFilterProperties.keys.toList()..sort();
    final visiblePropertyOptions = _selectedPropertyGroup == null
        ? <MapEntry<String, String>>[]
        : ([...(groupedFilterProperties[_selectedPropertyGroup] ?? [])]
          ..sort((a, b) => a.value.compareTo(b.value)));

    final displayed = _filteredSchedules;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedPropertyId != null
              ? 'PM: ${_propertyNames[_selectedPropertyId] ?? _selectedPropertyId}'
              : _selectedPropertyGroup != null
              ? 'PM: $_selectedPropertyGroup'
              : 'Preventive Maintenance',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.view_list_rounded),
            tooltip: 'สรุปอุปกรณ์ทุกหลัง',
            onPressed: () => context.push('/equipment-overview'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // แดชบอร์ด: สรุปตามสถานะ กดเพื่อกรอง
                _buildStatBar(theme),
                // Property filter chips
                if (filterGroups.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Column(
                      children: [
                        SizedBox(
                          height: 44,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: const Text('ทั้งหมด'),
                                  selected: _selectedPropertyGroup == null &&
                                      _selectedPropertyId == null,
                                  onSelected: (_) => _resetPropertyFilters(),
                                ),
                              ),
                              ...filterGroups.map(
                                (group) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(group),
                                    selected: _selectedPropertyGroup == group,
                                    onSelected: (_) => _togglePropertyGroup(group),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_selectedPropertyGroup != null &&
                            visiblePropertyOptions.isNotEmpty)
                          SizedBox(
                            height: 44,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: const Text('ทุกหลังในกลุ่ม'),
                                    selected: _selectedPropertyId == null,
                                    onSelected: (_) {
                                      setState(() => _selectedPropertyId = null);
                                    },
                                  ),
                                ),
                                ...visiblePropertyOptions.map(
                                  (entry) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: FilterChip(
                                      label: Text(entry.value),
                                      selected: _selectedPropertyId == entry.key,
                                      onSelected: (_) => _toggleProperty(entry.key),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),

                // Schedule list
                Expanded(
                  child: displayed.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _selectedStatus?.icon ?? Icons.schedule,
                                size: 64,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              // แยกให้ชัดว่า "ไม่มีเลย" กับ "ไม่มีในตัวกรองนี้" ต่างกัน
                              Text(
                                _selectedStatus != null
                                    ? 'ไม่มี PM ที่${_selectedStatus!.label}'
                                    : _schedules.isEmpty
                                    ? 'ยังไม่มี PM Schedule'
                                    : 'ไม่มี PM ในบ้านที่เลือก',
                              ),
                              if (_selectedStatus != null) ...[
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _selectedStatus = null),
                                  child: const Text('ดูทั้งหมด'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: PageWrapper(
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 80),
                              itemCount: displayed.length,
                              itemBuilder: (context, index) {
                                final s = displayed[index];
                                return _buildScheduleCard(s);
                              },
                            ),
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: 'batch_wo',
            onPressed: _showBatchWorkOrderDialog,
            tooltip: 'สร้างใบงานรวมจาก PM',
            child: const Icon(Icons.playlist_add_check),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'create_pm',
            onPressed: _showCreatePmDialog,
            icon: const Icon(Icons.add),
            label: const Text('สร้าง PM'),
          ),
        ],
      ),
    );
  }

  Future<void> _showBatchWorkOrderDialog() async {
    // Use ALL schedules as candidates so the dialog can filter by group internally
    final candidates = _schedules
        .where((s) => !_pendingWorkOrderIds.containsKey(s.id))
        .toList();

    if (candidates.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ไม่มี PM ที่สามารถรวมใบงานได้')),
        );
      }
      return;
    }

    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) => _BatchPmDialog(
        candidates: candidates,
        propertyNames: _propertyNames,
        assetNames: _assetNames,
        initialGroup: _selectedPropertyGroup,
      ),
    );

    if (selected == null || selected.isEmpty || !mounted) return;

    final selectedPms = candidates.where((s) => selected.contains(s.id)).toList();
    final first = selectedPms.first;

    // Build description listing all houses sorted by property name
    final sortedPms = [...selectedPms]
      ..sort((a, b) {
        final na = a.propertyName ?? _propertyNames[a.propertyId] ?? a.propertyId;
        final nb = b.propertyName ?? _propertyNames[b.propertyId] ?? b.propertyId;
        return na.compareTo(nb);
      });
    final houseLines = sortedPms.map((s) {
      final name = s.propertyName ?? _propertyNames[s.propertyId] ?? s.propertyId;
      final d = s.nextDueDate;
      return '- $name (ครบกำหนด: ${d.day}/${d.month}/${d.year})';
    }).join('\n');
    final description =
        'PM: ${first.title}\nรวม ${selectedPms.length} หลัง:\n$houseLines'
        '\nความถี่: ${first.frequency.displayName}'
        '${first.description != null ? "\nรายละเอียด: ${first.description}" : ""}';

    // Primary property = first sorted PM, additional = the rest
    final additionalPropertyIds = sortedPms.skip(1).map((s) => s.propertyId).toList();

    final queryParams = <String, String>{
      'title': first.title,
      'propertyId': sortedPms.first.propertyId,
      'description': description,
      'pmScheduleIds': selected.join(','),
      if (additionalPropertyIds.isNotEmpty)
        'additionalPropertyIds': additionalPropertyIds.join(','),
    };

    // Use shared technician if all PMs have the same one
    final techIds = selectedPms.map((s) => s.assignedTo).toSet();
    if (techIds.length == 1 && techIds.first != null) {
      queryParams['technicianId'] = techIds.first!;
    } else {
      final authState = AuthStateService();
      if (authState.currentRole == UserRole.caretaker) {
        queryParams['technicianId'] = authState.currentAppUser!.id;
      }
    }

    final uri = Uri(path: '/work-orders/new', queryParameters: queryParams);
    await context.push(uri.toString());
    _load();
  }

  Widget _buildScheduleCard(PmSchedule s) {
    final theme = Theme.of(context);
    final daysUntilDue = s.nextDueDate.difference(thaiNow()).inDays;
    final isOverdue = daysUntilDue < 0;
    final isDueSoon = daysUntilDue <= 7 && daysUntilDue >= 0;

    Color statusColor = theme.colorScheme.primary;
    String statusText = 'อีก $daysUntilDue วัน';
    if (s.awaitingSchedule) {
      // ยังไม่มีวันกำหนด — วันในฐานข้อมูลเป็นของครั้งที่แล้ว นับวันไม่ได้
      statusColor = Colors.blue;
      statusText = 'รอนัดวัน';
    } else if (isOverdue) {
      statusColor = Colors.red;
      statusText = 'เกินกำหนด ${-daysUntilDue} วัน';
    } else if (isDueSoon) {
      statusColor = Colors.orange;
      statusText = 'อีก $daysUntilDue วัน';
    }

    // Use local maps as fallback when join doesn't return data
    final propertyName = s.propertyName ?? _propertyNames[s.propertyId];
    final assetName =
        s.assetName ?? (s.assetId != null ? _assetNames[s.assetId!] : null);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: s.assetId != null
            ? () async {
                await context.push('/assets/${s.assetId}');
                _load(); // Reload when returning from asset detail
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.title, style: theme.textTheme.titleSmall),
                        if (propertyName != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.home,
                                  size: 14,
                                  color: theme.colorScheme.outline,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    propertyName,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.outline,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: theme.colorScheme.outline,
                          ),
                          tooltip: 'แก้ไข PM',
                          onPressed: () => _showEditPmDialog(s),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // รอนัดวันครั้งถัดไป (PM แบบจำกัดจำนวนครั้ง) — ยังไม่มีวันกำหนด
              if (s.awaitingSchedule) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.tonalIcon(
                    onPressed: () => _scheduleNextVisit(s),
                    icon: const Icon(Icons.event_available, size: 18),
                    label: Text('นัดวันครั้งที่ ${s.roundsDone + 1}'),
                  ),
                ),
              ] else if (s.isDueSoon || isOverdue) ...[
                const SizedBox(height: 8),
                _buildWorkOrderButton(s, statusColor),
              ],
              if (s.description != null) ...[
                const SizedBox(height: 4),
                Text(s.description!, style: theme.textTheme.bodySmall),
              ],
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                children: [
                  // แบบจำกัดจำนวนครั้งไม่มีความถี่ → โชว์ความคืบหน้าแทน
                  if (s.mode == PmMode.limitedCount)
                    _chip(
                      Icons.pin,
                      'ครั้งที่ ${s.roundsDone}/${s.totalRounds}',
                    )
                  else
                    _chip(Icons.repeat, s.frequency.displayName),
                  if (!s.awaitingSchedule)
                    _chip(
                      Icons.calendar_today,
                      formatThaiDate(s.nextDueDate),
                    ),
                  _chip(Icons.schedule, 'สร้างเมื่อ ${formatThaiDateTime(s.createdAt)}'),
                  if (s.createdByName != null)
                    _chip(Icons.person_add_alt_1, 'สร้างโดย ${s.createdByName!}'),
                  if (s.assignedToName != null)
                    _chip(Icons.person, s.assignedToName!),
                  if (assetName != null) _chip(Icons.build, assetName),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// แดชบอร์ด: แถวตัวเลขสรุปตามสถานะ — กดเพื่อกรองรายการด้านล่าง
  /// นับจาก _propertyFiltered เพื่อให้ตัวเลขทุกช่องยังเห็นครบ
  /// แม้กำลังกรองสถานะใดสถานะหนึ่งอยู่
  Widget _buildStatBar(ThemeData theme) {
    final base = _propertyFiltered;
    if (base.isEmpty) return const SizedBox.shrink();

    final counts = <_PmStatus, int>{for (final s in _PmStatus.values) s: 0};
    for (final s in base) {
      counts[_statusOf(s)] = (counts[_statusOf(s)] ?? 0) + 1;
    }

    // ซ่อนช่องที่เป็น 0 เพื่อไม่ให้แถวรก ยกเว้นช่องที่กำลังเลือกอยู่
    final visible = _PmStatus.values
        .where((s) => counts[s]! > 0 || _selectedStatus == s)
        .toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        children: [
          for (final st in visible)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _statTile(theme, st, counts[st]!),
            ),
        ],
      ),
    );
  }

  Widget _statTile(ThemeData theme, _PmStatus st, int count) {
    final selected = _selectedStatus == st;
    return Tooltip(
      message: st.hint,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(
          () => _selectedStatus = selected ? null : st,
        ),
        child: Container(
          width: 132,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? st.color.withValues(alpha: 0.12)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? st.color : theme.colorScheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(st.icon, size: 15, color: st.color),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      st.label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '$count',
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: st.color,
                  fontWeight: FontWeight.bold,
                  height: 1.1,
                ),
              ),
              Text(
                'รายการ',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// นัดวันครั้งถัดไปของ PM แบบจำกัดจำนวนครั้ง (เช่น ฉีดปลวก)
  Future<void> _scheduleNextVisit(PmSchedule s) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
      helpText: 'นัดวันครั้งที่ ${s.roundsDone + 1} จาก ${s.totalRounds}',
    );
    if (picked == null) return;
    try {
      await _service.schedulePmNextVisit(s.id, picked);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'นัดครั้งที่ ${s.roundsDone + 1} วันที่ ${formatThaiDate(picked)} แล้ว',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('นัดวันไม่สำเร็จ: ${friendlyError(e)}')),
        );
      }
    }
  }

  Future<void> _showEditPmDialog(PmSchedule s) async {
    final titleCtrl = TextEditingController(text: s.title);
    final descCtrl = TextEditingController(text: s.description ?? '');
    DateTime nextDue = s.nextDueDate;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('แก้ไข PM Schedule'),
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
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('วันครบกำหนดถัดไป'),
                  subtitle: Text(
                    '${nextDue.day}/${nextDue.month}/${nextDue.year}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: nextDue,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    );
                    if (picked != null) setDialogState(() => nextDue = picked);
                  },
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
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );

    if (saved != true) return;

    try {
      await _service.updatePmSchedule(s.id, {
        'title': titleCtrl.text.trim(),
        'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
        'next_due_date': nextDue.toIso8601String().split('T').first,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('แก้ไข PM สำเร็จ'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('แก้ไข PM ล้มเหลว: ${friendlyError(e)}')),
        );
      }
    }
  }

  Widget _buildWorkOrderButton(PmSchedule s, Color statusColor) {
    final pendingId = _pendingWorkOrderIds[s.id];
    if (pendingId != null) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () async {
            await context.push('/work-orders/$pendingId');
            _load();
          },
          icon: const Icon(Icons.hourglass_top, size: 18),
          label: const Text('สร้างใบงานแล้วรอดำเนินการ'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.orange,
            side: const BorderSide(color: Colors.orange),
          ),
        ),
      );
    }
    return SizedBox(
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
                    ? '↻ ${dates[i].day}/${dates[i].month}/${dates[i].year}  (วนกลับรอบแรก ปีถัดไป)'
                    : '${i + 1}. ${dates[i].day}/${dates[i].month}/${dates[i].year}',
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
}

/// Dialog for selecting multiple PM schedules to batch into one work order.
/// After the first selection, only PMs with the same title and asset NAME are shown.
class _BatchPmDialog extends StatefulWidget {
  final List<PmSchedule> candidates;
  final Map<String, String> propertyNames;
  final Map<String, String> assetNames;
  final String? initialGroup;

  const _BatchPmDialog({
    required this.candidates,
    required this.propertyNames,
    required this.assetNames,
    this.initialGroup,
  });

  @override
  State<_BatchPmDialog> createState() => _BatchPmDialogState();
}

class _BatchPmDialogState extends State<_BatchPmDialog> {
  final Set<String> _selected = {};
  String? _lockedTitle;
  String? _lockedAssetName; // compare by name, not ID (each house has its own asset ID)
  String? _selectedGroup;

  @override
  void initState() {
    super.initState();
    _selectedGroup = widget.initialGroup;
  }

  String? _assetName(PmSchedule s) =>
      s.assetName ?? (s.assetId != null ? widget.assetNames[s.assetId!] : null);

  String _propertyGroup(String name) {
    final m = RegExp(r'^([A-Za-z]+-[A-Za-z]+)').firstMatch(name);
    if (m != null) return m.group(1)!.toUpperCase();
    final fb = RegExp(r'^(.+?)\d+$').firstMatch(name);
    if (fb != null) return fb.group(1)!.toUpperCase();
    return name.toUpperCase();
  }

  List<PmSchedule> get _visible {
    return widget.candidates.where((s) {
      // Group filter
      if (_selectedGroup != null) {
        final name = s.propertyName ?? widget.propertyNames[s.propertyId];
        if (name == null || _propertyGroup(name) != _selectedGroup) return false;
      }
      // Lock: same title + same asset name after first selection
      if (_lockedTitle != null) {
        if (s.title != _lockedTitle) return false;
        if (_assetName(s) != _lockedAssetName) return false;
      }
      return true;
    }).toList();
  }

  void _toggle(PmSchedule s) {
    setState(() {
      if (_selected.contains(s.id)) {
        _selected.remove(s.id);
        if (_selected.isEmpty) {
          _lockedTitle = null;
          _lockedAssetName = null;
        }
      } else {
        if (_selected.isEmpty) {
          _lockedTitle = s.title;
          _lockedAssetName = _assetName(s);
        }
        _selected.add(s.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final theme = Theme.of(context);

    final allGroups = widget.candidates
        .map((s) {
          final n = s.propertyName ?? widget.propertyNames[s.propertyId] ?? '';
          return _propertyGroup(n);
        })
        .toSet()
        .toList()
      ..sort();

    return AlertDialog(
      title: const Text('สร้างใบงานรวมจาก PM'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Property group dropdown
            if (allGroups.length > 1) ...[
              DropdownButtonFormField<String?>(
                value: _selectedGroup,
                decoration: const InputDecoration(
                  labelText: 'หมวดบ้าน',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('ทั้งหมด')),
                  ...allGroups.map(
                    (g) => DropdownMenuItem(value: g, child: Text(g)),
                  ),
                ],
                onChanged: (v) => setState(() => _selectedGroup = v),
              ),
              const SizedBox(height: 8),
            ],
            // Lock indicator or hint
            if (_lockedTitle != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Chip(
                  avatar: const Icon(Icons.lock, size: 14),
                  label: Text(
                    '${_lockedTitle!}${_lockedAssetName != null ? " · $_lockedAssetName" : ""}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'เลือก PM แรกเพื่อกรองงานชื่อและอุปกรณ์เดียวกัน',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            // PM list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 380),
              child: visible.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'ไม่มี PM ในกลุ่มนี้',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: visible.length,
                      itemBuilder: (ctx, i) {
                        final s = visible[i];
                        final propName =
                            s.propertyName ?? widget.propertyNames[s.propertyId] ?? s.propertyId;
                        final asset = _assetName(s);
                        final d = s.nextDueDate;
                        final daysUntilDue = d.difference(DateTime.now()).inDays;
                        final isOverdue = daysUntilDue < 0;
                        final dueDateColor = isOverdue
                            ? Colors.red
                            : daysUntilDue <= 7
                            ? Colors.orange
                            : theme.colorScheme.outline;

                        return CheckboxListTile(
                          dense: true,
                          value: _selected.contains(s.id),
                          onChanged: (_) => _toggle(s),
                          title: Text(
                            propName,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.title),
                              if (asset != null)
                                Text(
                                  asset,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              Text(
                                isOverdue
                                    ? 'เกินกำหนด ${-daysUntilDue} วัน (${d.day}/${d.month}/${d.year})'
                                    : 'ครบกำหนด: ${d.day}/${d.month}/${d.year}',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: dueDateColor,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton.icon(
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.pop(context, Set<String>.from(_selected)),
          icon: const Icon(Icons.assignment_add),
          label: Text(
            _selected.isEmpty
                ? 'สร้างใบงาน'
                : 'สร้างใบงาน (${_selected.length} บ้าน)',
          ),
        ),
      ],
    );
  }
}
