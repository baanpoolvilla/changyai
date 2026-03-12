import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/pm_schedule.dart';
import '../../models/user.dart';
import '../../services/auth_state_service.dart';
import '../../services/supabase_service.dart';

class PmScheduleScreen extends StatefulWidget {
  const PmScheduleScreen({super.key});

  @override
  State<PmScheduleScreen> createState() => _PmScheduleScreenState();
}

class _PmScheduleScreenState extends State<PmScheduleScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  List<PmSchedule> _schedules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getPmSchedules();
      _schedules = data.map((e) => PmSchedule.fromJson(e)).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _loading = false);
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
    context.push(uri.toString());
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
        technicians = allUsers.where((u) => u['role'] == 'technician').toList();
      } else {
        technicians = allUsers;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: $e')));
      }
      return;
    }

    if (!mounted) return;

    final titleCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    PmFrequency selectedFreq = PmFrequency.monthly;
    DateTime nextDue = DateTime.now().add(const Duration(days: 30));
    String? selectedTechId;
    Set<String> selectedPropertyIds = {};
    Set<String> selectedAssetIds = {};
    Map<String, List<Map<String, dynamic>>> propertyAssetsMap = {};
    bool loadingAssets = false;

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
                        if (v != null) setDialogState(() => selectedFreq = v);
                      },
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('วันครบกำหนดถัดไป'),
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
                        if (picked != null)
                          setDialogState(() => nextDue = picked);
                      },
                    ),
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
                      onChanged: (v) =>
                          setDialogState(() => selectedTechId = v),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    const Text(
                      'เลือกบ้าน',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    ...properties.map((p) {
                      final pid = p['id'] as String;
                      final pName = p['name'] as String;
                      return CheckboxListTile(
                        dense: true,
                        visualDensity: VisualDensity.compact,
                        title: Text(
                          pName,
                          style: const TextStyle(fontSize: 13),
                        ),
                        value: selectedPropertyIds.contains(pid),
                        onChanged: (v) {
                          setDialogState(() {
                            if (v == true) {
                              selectedPropertyIds.add(pid);
                            } else {
                              selectedPropertyIds.remove(pid);
                            }
                          });
                          loadAssetsForProperties();
                        },
                      );
                    }),
                    if (selectedPropertyIds.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const Text(
                        'เลือกอุปกรณ์',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
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
          'frequency': selectedFreq.name,
          'next_due_date': nextDue.toIso8601String().split('T').first,
          'assigned_to': selectedTechId,
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
          SnackBar(content: Text('สร้าง PM Schedule ล้มเหลว: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Preventive Maintenance')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _schedules.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.schedule,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  const Text('ยังไม่มี PM Schedule'),
                  const SizedBox(height: 8),
                  const Text(
                    'กดปุ่ม + เพื่อสร้าง PM Schedule ใหม่',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _schedules.length,
                itemBuilder: (context, index) {
                  final s = _schedules[index];
                  return _buildScheduleCard(s);
                },
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showCreatePmDialog,
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
    String statusText = 'อีก $daysUntilDue วัน';
    if (isOverdue) {
      statusColor = Colors.red;
      statusText = 'เกินกำหนด ${-daysUntilDue} วัน';
    } else if (isDueSoon) {
      statusColor = Colors.orange;
      statusText = 'อีก $daysUntilDue วัน';
    }

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: s.assetId != null
            ? () => context.push('/assets/${s.assetId}')
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
                        if (s.propertyName != null)
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
                                Text(
                                  s.propertyName!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
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
                ],
              ),
              if (s.isDueSoon || isOverdue) ...[
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
                  if (s.assetName != null) _chip(Icons.build, s.assetName!),
                ],
              ),
            ],
          ),
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
}
