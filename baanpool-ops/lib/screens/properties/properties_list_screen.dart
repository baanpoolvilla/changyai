import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/property.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_state_service.dart';
import '../../utils/page_wrapper.dart';

class PropertiesListScreen extends StatefulWidget {
  const PropertiesListScreen({super.key});

  @override
  State<PropertiesListScreen> createState() => _PropertiesListScreenState();
}

class _PropertiesListScreenState extends State<PropertiesListScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  final _authState = AuthStateService();
  List<Property> _properties = [];
  Map<String, String> _categoryNames = {};
  Map<String, Map<String, int>> _workOrderStatusCounts = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getProperties();
      _properties = data.map((e) => Property.fromJson(e)).toList();
      _categoryNames = await _service.getPropertyCategories();

      // Load work order status counts for all properties
      if (_properties.isNotEmpty) {
        final propIds = _properties.map((p) => p.id).toList();
        _workOrderStatusCounts =
            await _service.getWorkOrderStatusCountsForProperties(propIds);
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

  /// Extract category prefix from property name (e.g. "BS-A1" → "BS-A")
  String _getCategoryPrefix(String name) {
    // Match pattern like "XX-YY" where YY starts with letters then numbers
    final match = RegExp(r'^([A-Za-z]+-[A-Za-z]+)').firstMatch(name);
    if (match != null) return match.group(1)!;
    // Fallback: take everything before the last digit sequence
    final fallback = RegExp(r'^(.+?)\d+$').firstMatch(name);
    if (fallback != null) return fallback.group(1)!;
    return 'อื่นๆ';
  }

  /// Get a display name for the category (from DB or fallback)
  String _getCategoryDisplayName(String prefix) {
    // Use saved name from DB if available
    final saved = _categoryNames[prefix.toUpperCase()];
    if (saved != null && saved.isNotEmpty) return saved;
    // Fallback defaults
    switch (prefix.toUpperCase()) {
      case 'BS-A':
        return 'BS-A (บ้านเดี่ยว A)';
      case 'BS-HS':
        return 'BS-HS (โฮมสเตย์)';
      case 'BS-M':
        return 'BS-M (บ้านเดี่ยว M)';
      case 'BS-T':
        return 'BS-T (ทาวน์เฮาส์)';
      case 'PT-BT':
        return 'PT-BT (พูลวิลล่า)';
      default:
        return prefix;
    }
  }

  /// Show dialog to edit category display name (admin only)
  Future<void> _editCategoryName(String prefix) async {
    final ctrl = TextEditingController(text: _getCategoryDisplayName(prefix));
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('แก้ไขชื่อหมวดหมู่'),
        content: TextField(
          controller: ctrl,
          decoration: InputDecoration(
            labelText: 'ชื่อหมวดหมู่',
            hintText: prefix,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    try {
      await _service.upsertPropertyCategory(prefix.toUpperCase(), result);
      _categoryNames[prefix.toUpperCase()] = result;
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('บันทึกชื่อหมวดหมู่สำเร็จ')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('บันทึกล้มเหลว: $e')));
      }
    }
  }

  /// Group properties by category prefix
  Map<String, List<Property>> _groupProperties() {
    final grouped = <String, List<Property>>{};
    for (final p in _properties) {
      final prefix = _getCategoryPrefix(p.name);
      grouped.putIfAbsent(prefix, () => []).add(p);
    }
    // Sort keys
    final sortedKeys = grouped.keys.toList()..sort();
    return {for (final k in sortedKeys) k: grouped[k]!};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('รายชื่อบ้าน')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _properties.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.home_outlined,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  const Text('ยังไม่มีข้อมูลบ้าน'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.push('/properties/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มบ้าน'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(onRefresh: _load, child: PageWrapper(child: _buildGroupedList(theme))),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await context.push('/properties/new');
          _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  /// Build a colored status dot for a property based on its work order statuses
  /// 🟢 Green = no active work orders
  /// 🟡 Yellow = has in_progress work orders
  /// 🔴 Red = has open (not started) work orders
  Widget _buildStatusDot(String propertyId) {
    final counts = _workOrderStatusCounts[propertyId];
    final inProgressCount = counts?['in_progress'] ?? 0;
    final openCount = counts?['open'] ?? 0;

    Color color;
    String tooltip;
    int count;

    if (inProgressCount > 0) {
      color = Colors.amber.shade600;
      tooltip = 'กำลังดำเนินการ $inProgressCount ใบงาน';
      count = inProgressCount;
    } else if (openCount > 0) {
      color = Colors.red;
      tooltip = 'รอดำเนินการ $openCount ใบงาน';
      count = openCount;
    } else {
      color = Colors.green;
      tooltip = 'ไม่มีใบงานค้าง';
      count = 0;
    }

    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGroupedList(ThemeData theme) {
    final grouped = _groupProperties();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final entry in grouped.entries) ...[
          // Category header
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _authState.isAdmin
                      ? () => _editCategoryName(entry.key)
                      : null,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.villa,
                          size: 16,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${_getCategoryDisplayName(entry.key)} (${entry.value.length})',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (_authState.isAdmin) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.edit,
                            size: 14,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const Expanded(child: Divider(indent: 8)),
              ],
            ),
          ),
          // Property cards in this category
          ...entry.value.map(
            (p) => Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.home)),
                title: Text(p.name),
                subtitle: Text(
                  p.caretakerName != null
                      ? 'ผู้จัดการ: ${p.caretakerName}'
                      : 'ไม่มีผู้จัดการ',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        final counts = _workOrderStatusCounts[p.id];
                        final hasOrders = (counts?['open'] ?? 0) > 0 ||
                            (counts?['in_progress'] ?? 0) > 0;
                        if (hasOrders) {
                          context.push(
                            Uri(
                              path: '/work-orders',
                              queryParameters: {'propertyId': p.id},
                            ).toString(),
                          );
                        }
                      },
                      child: _buildStatusDot(p.id),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right),
                  ],
                ),
                onTap: () async {
                  await context.push('/properties/${p.id}');
                  _load();
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}
