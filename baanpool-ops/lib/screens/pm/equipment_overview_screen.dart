import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/pm_schedule.dart';
import '../../services/supabase_service.dart';
import '../../utils/thai_datetime.dart';
import '../../utils/page_wrapper.dart';

/// สรุปอุปกรณ์ทุกหลัง: แอร์ | ฉีดปลวก | สระว่ายน้ำ
class EquipmentOverviewScreen extends StatefulWidget {
  const EquipmentOverviewScreen({super.key});

  @override
  State<EquipmentOverviewScreen> createState() =>
      _EquipmentOverviewScreenState();
}

class _EquipmentOverviewScreenState extends State<EquipmentOverviewScreen> {
  final _service = SupabaseService(Supabase.instance.client);

  bool _loading = true;
  List<PmSchedule> _schedules = [];
  Map<String, String> _propertyNames = {};

  // 3 equipment types with keywords
  static const List<_EquipType> _types = [
    _EquipType(label: '❄️ แอร์', keywords: ['แอร์', 'air', 'เครื่องปรับอากาศ']),
    _EquipType(label: '🐛 ฉีดปลวก', keywords: ['ปลวก', 'termite']),
    _EquipType(label: '🏊 สระว่ายน้ำ', keywords: ['สระ', 'pool', 'สระว่ายน้ำ']),
  ];

  int _selectedTypeIndex = 0;

  @override
  void initState() {
    super.initState();
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

      _schedules = data.map((e) => PmSchedule.fromJson(e)).toList();

      // Also load asset names for PM schedules that have asset_id
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
          final assetNames = {
            for (final a in assetData) a['id'] as String: a['name'] as String,
          };
          // Enrich schedules with asset name where not already joined
          _schedules = _schedules.map((s) {
            if (s.assetId != null && s.assetName == null) {
              final aName = assetNames[s.assetId];
              if (aName != null) {
                return PmSchedule(
                  id: s.id,
                  propertyId: s.propertyId,
                  assetId: s.assetId,
                  title: s.title,
                  description: s.description,
                  frequency: s.frequency,
                  nextDueDate: s.nextDueDate,
                  lastCompletedDate: s.lastCompletedDate,
                  isActive: s.isActive,
                  assignedTo: s.assignedTo,
                  assignedToName: s.assignedToName,
                  createdByName: s.createdByName,
                  propertyName: s.propertyName,
                  assetName: aName,
                  createdAt: s.createdAt,
                );
              }
            }
            return s;
          }).toList();
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('โหลดข้อมูลล้มเหลว: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  List<PmSchedule> get _filtered {
    final type = _types[_selectedTypeIndex];
    return _schedules.where((s) {
      final title = s.title.toLowerCase();
      final assetName = (s.assetName ?? '').toLowerCase();
      return type.keywords.any(
        (kw) => title.contains(kw.toLowerCase()) || assetName.contains(kw.toLowerCase()),
      );
    }).toList()
      ..sort((a, b) => a.nextDueDate.compareTo(b.nextDueDate));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final filtered = _filtered;

    // Group by property
    final Map<String, List<PmSchedule>> byProperty = {};
    for (final s in filtered) {
      byProperty.putIfAbsent(s.propertyId, () => []).add(s);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('สรุปอุปกรณ์ทุกหลัง')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Equipment type chips
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    children: List.generate(_types.length, (i) {
                      final t = _types[i];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(t.label),
                          selected: _selectedTypeIndex == i,
                          onSelected: (_) =>
                              setState(() => _selectedTypeIndex = i),
                        ),
                      );
                    }),
                  ),
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: filtered.isEmpty
                        ? ListView(
                            children: const [
                              SizedBox(height: 80),
                              Center(
                                child: Text(
                                  'ไม่พบ PM ประเภทนี้',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            ],
                          )
                        : PageWrapper(
                            child: ListView(
                              padding: const EdgeInsets.all(12),
                              children: byProperty.entries.map((entry) {
                                final propName =
                                    _propertyNames[entry.key] ??
                                    entry.value.first.propertyName ??
                                    entry.key;
                                return _PropertyEquipCard(
                                  propertyName: propName,
                                  schedules: entry.value,
                                  now: now,
                                  theme: theme,
                                );
                              }).toList(),
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _PropertyEquipCard extends StatelessWidget {
  final String propertyName;
  final List<PmSchedule> schedules;
  final DateTime now;
  final ThemeData theme;

  const _PropertyEquipCard({
    required this.propertyName,
    required this.schedules,
    required this.now,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              propertyName,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ...schedules.map((s) => _ScheduleRow(s: s, now: now, theme: theme)),
          ],
        ),
      ),
    );
  }
}

class _ScheduleRow extends StatelessWidget {
  final PmSchedule s;
  final DateTime now;
  final ThemeData theme;

  const _ScheduleRow({
    required this.s,
    required this.now,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final daysUntil = s.nextDueDate.difference(now).inDays;
    final isOverdue = daysUntil < 0;
    final isDueSoon = !isOverdue && daysUntil <= 14;

    final Color statusColor = isOverdue
        ? Colors.red
        : isDueSoon
            ? Colors.orange
            : Colors.green;

    final String statusLabel = isOverdue
        ? 'เกินกำหนด ${(-daysUntil)} วัน'
        : isDueSoon
            ? 'อีก $daysUntil วัน'
            : 'อีก $daysUntil วัน';

    final String nextDueText = formatThaiDate(s.nextDueDate);
    final String lastText = s.lastCompletedDate != null
        ? formatThaiDate(s.lastCompletedDate!)
        : 'ยังไม่เคยทำ';

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status indicator
          Container(
            margin: const EdgeInsets.only(top: 3, right: 8),
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title + asset name
                Text(
                  s.assetName != null
                      ? '${s.title} (${s.assetName})'
                      : s.title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                // Date info
                Text(
                  'ครบกำหนด: $nextDueText  |  ทำล่าสุด: $lastText',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey[600]),
                ),
                // Frequency
                Text(
                  'ความถี่: ${s.frequency.displayName}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: Colors.grey[500]),
                ),
              ],
            ),
          ),
          // Status chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: statusColor.withOpacity(0.4)),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(
                color: statusColor,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EquipType {
  final String label;
  final List<String> keywords;
  const _EquipType({required this.label, required this.keywords});
}
