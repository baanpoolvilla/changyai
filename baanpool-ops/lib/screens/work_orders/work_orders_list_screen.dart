import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/work_order.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_state_service.dart';
import '../../utils/thai_datetime.dart';

class WorkOrdersListScreen extends StatefulWidget {
  const WorkOrdersListScreen({super.key});

  @override
  State<WorkOrdersListScreen> createState() => _WorkOrdersListScreenState();
}

class _WorkOrdersListScreenState extends State<WorkOrdersListScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  List<WorkOrder> _workOrders = [];
  bool _loading = true;
  String? _filterStatus;
  Map<String, String> _propertyNames = {};
  Set<String> _workOrderIdsWithExpense = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getWorkOrders(status: _filterStatus),
        _service.getPropertyNamesOnly(),
        _service.getWorkOrderIdsWithExpenses(),
      ]);
      final data = results[0] as List<Map<String, dynamic>>;
      _workOrders = data.map((e) => WorkOrder.fromJson(e)).toList();

      final properties = results[1] as List<Map<String, dynamic>>;
      _propertyNames = {
        for (final p in properties) p['id'] as String: p['name'] as String,
      };

      _workOrderIdsWithExpense = results[2] as Set<String>;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('กรองตามสถานะ'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              setState(() => _filterStatus = null);
              _load();
            },
            child: Text(
              'ทั้งหมด',
              style: TextStyle(
                fontWeight: _filterStatus == null
                    ? FontWeight.bold
                    : FontWeight.normal,
              ),
            ),
          ),
          for (final status in WorkOrderStatus.values)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _filterStatus = status == WorkOrderStatus.inProgress
                      ? 'in_progress'
                      : status.name;
                });
                _load();
              },
              child: Row(
                children: [
                  Icon(_statusIcon(status), color: _statusColor(status)),
                  const SizedBox(width: 8),
                  Text(status.displayName),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _filterStatus != null
              ? 'ใบงาน (${_getFilterLabel()})'
              : 'ใบงานทั้งหมด',
        ),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _filterStatus != null,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'ออกจากระบบ',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('ยืนยันการออกจากระบบ'),
                  content: const Text('คุณต้องการออกจากระบบหรือไม่?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('ยกเลิก'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('ออกจากระบบ'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await AuthStateService().signOut();
                if (context.mounted) context.go('/login');
              }
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _workOrders.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.assignment_outlined,
                    size: 64,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  const Text('ยังไม่มีใบงาน'),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () async {
                      await context.push('/work-orders/new');
                      _load();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('สร้างใบงาน'),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _workOrders.length,
                itemBuilder: (context, index) {
                  final wo = _workOrders[index];
                  return _buildWorkOrderCard(wo, theme);
                },
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/work-orders/new');
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('สร้างใบงาน'),
      ),
    );
  }

  Widget _buildWorkOrderCard(WorkOrder wo, ThemeData theme) {
    final propertyName = _propertyNames[wo.propertyId] ?? '';
    final isNew = wo.status == WorkOrderStatus.open;
    final hasExpense = _workOrderIdsWithExpense.contains(wo.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isNew ? Colors.red.shade50 : null,
      shape: isNew
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.red.shade200, width: 1.5),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await context.push('/work-orders/${wo.id}');
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Red dot for new/open work orders
                  if (isNew) ...[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Text(
                      wo.title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isNew ? Colors.red.shade800 : null,
                      ),
                    ),
                  ),
                  _priorityBadge(wo.priority),
                ],
              ),
              const SizedBox(height: 8),
              if (propertyName.isNotEmpty)
                Row(
                  children: [
                    Icon(
                      Icons.home,
                      size: 16,
                      color: theme.colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      propertyName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              if (wo.description != null && wo.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  wo.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _statusChip(wo.status),
                      const SizedBox(width: 6),
                      if (wo.status == WorkOrderStatus.completed)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: hasExpense
                                ? Colors.green.withValues(alpha: 0.1)
                                : Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: hasExpense
                                  ? Colors.green.withValues(alpha: 0.3)
                                  : Colors.orange.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasExpense
                                    ? Icons.receipt_long
                                    : Icons.receipt_long_outlined,
                                size: 12,
                                color: hasExpense
                                    ? Colors.green
                                    : Colors.orange,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                hasExpense ? 'บันทึกแล้ว' : 'ยังไม่บันทึก',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: hasExpense
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  Text(
                    formatThaiDate(wo.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
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

  Widget _statusChip(WorkOrderStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_statusIcon(status), size: 14, color: _statusColor(status)),
          const SizedBox(width: 4),
          Text(
            status.displayName,
            style: TextStyle(color: _statusColor(status), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _priorityBadge(WorkOrderPriority priority) {
    Color color;
    String label;
    switch (priority) {
      case WorkOrderPriority.urgent:
        color = Colors.red;
        label = 'เร่งด่วน';
      case WorkOrderPriority.high:
        color = Colors.orange;
        label = 'สูง';
      case WorkOrderPriority.medium:
        color = Colors.blue;
        label = 'ปกติ';
      case WorkOrderPriority.low:
        color = Colors.grey;
        label = 'ต่ำ';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11)),
    );
  }

  Color _statusColor(WorkOrderStatus status) {
    switch (status) {
      case WorkOrderStatus.open:
        return Colors.red;
      case WorkOrderStatus.inProgress:
        return Colors.orange;
      case WorkOrderStatus.completed:
        return Colors.green;
      case WorkOrderStatus.cancelled:
        return Colors.grey;
    }
  }

  IconData _statusIcon(WorkOrderStatus status) {
    switch (status) {
      case WorkOrderStatus.open:
        return Icons.fiber_new;
      case WorkOrderStatus.inProgress:
        return Icons.autorenew;
      case WorkOrderStatus.completed:
        return Icons.check_circle;
      case WorkOrderStatus.cancelled:
        return Icons.cancel;
    }
  }

  String _getFilterLabel() {
    if (_filterStatus == null) return 'ทั้งหมด';
    return WorkOrderStatus.fromString(_filterStatus!).displayName;
  }
}
