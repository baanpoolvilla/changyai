import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/work_order.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_state_service.dart';
import '../../utils/thai_datetime.dart';
import '../../utils/page_wrapper.dart';

class WorkOrdersListScreen extends StatefulWidget {
  /// Optional initial filter: 'today' | 'urgent' | 'no-expense' | null
  final String? initialFilter;

  /// Optional filter: show only work orders for this property
  final String? propertyId;

  const WorkOrdersListScreen({super.key, this.initialFilter, this.propertyId});

  @override
  State<WorkOrdersListScreen> createState() => _WorkOrdersListScreenState();
}

class _WorkOrdersListScreenState extends State<WorkOrdersListScreen>
    with SingleTickerProviderStateMixin {
  final _service = SupabaseService(Supabase.instance.client);
  List<WorkOrder> _workOrders = [];
  bool _loading = true;
  String? _filterMode; // 'today' | 'urgent' | 'no-expense' | null
  String? _propertyId;
  Map<String, String> _propertyNames = {};
  Map<String, String> _creatorNames = {};
  Set<String> _workOrderIdsWithExpense = {};

  late TabController _tabController;

  bool get _isFilterMode => _filterMode != null;

  List<WorkOrder> get _openOrders =>
      _workOrders.where((w) => w.status == WorkOrderStatus.open).toList();
  List<WorkOrder> get _inProgressOrders =>
      _workOrders.where((w) => w.status == WorkOrderStatus.inProgress).toList();
  List<WorkOrder> get _completedOrders =>
      _workOrders
          .where(
            (w) =>
                w.status == WorkOrderStatus.completed ||
                w.status == WorkOrderStatus.cancelled,
          )
          .toList();

  @override
  void initState() {
    super.initState();
    _filterMode = widget.initialFilter;
    _propertyId = widget.propertyId;
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(WorkOrdersListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialFilter != widget.initialFilter ||
        oldWidget.propertyId != widget.propertyId) {
      _filterMode = widget.initialFilter;
      _propertyId = widget.propertyId;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getWorkOrders(
          priority: _filterMode == 'urgent' ? 'urgent' : null,
          createdToday: _filterMode == 'today' ? true : null,
          noExpense: _filterMode == 'no-expense' ? true : null,
          propertyId: _propertyId,
        ),
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

      final creatorIds = _workOrders
          .map((wo) => wo.createdBy)
          .where((id) => id != null)
          .cast<String>()
          .toSet()
          .toList();
      _creatorNames = await _service.getUserNamesByIds(creatorIds);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('โหลดข้อมูลล้มเหลว: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      appBar: AppBar(
        title: Text(_buildTitle()),
        bottom: (!_isFilterMode && !isDesktop)
            ? TabBar(
                controller: _tabController,
                tabs: [
                  Tab(
                    child: _TabLabel(
                      '🔴 ยังไม่ทำ',
                      _openOrders.length,
                      Colors.red,
                    ),
                  ),
                  Tab(
                    child: _TabLabel(
                      '🟡 กำลังทำ',
                      _inProgressOrders.length,
                      Colors.orange,
                    ),
                  ),
                  Tab(
                    child: _TabLabel(
                      '✅ เสร็จแล้ว',
                      _completedOrders.length,
                      Colors.green,
                    ),
                  ),
                ],
              )
            : null,
        actions: [
          if (_isFilterMode)
            TextButton.icon(
              onPressed: () {
                setState(() => _filterMode = null);
                _load();
              },
              icon: const Icon(Icons.close, size: 16),
              label: const Text('ล้างตัวกรอง'),
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
          : _isFilterMode
          ? _buildFilteredList(theme)
          : isDesktop
          ? _buildKanbanDesktop(theme)
          : _buildKanbanMobile(theme),
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

  // ─── Filtered list (for today / urgent / no-expense modes) ────
  Widget _buildFilteredList(ThemeData theme) {
    if (_workOrders.isEmpty) {
      return const Center(child: Text('ไม่พบใบงาน'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: PageWrapper(
        child: ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: _workOrders.length,
          itemBuilder: (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _buildWorkOrderCard(_workOrders[index], theme),
          ),
        ),
      ),
    );
  }

  // ─── Desktop Kanban: 3 columns side by side ─────────────
  Widget _buildKanbanDesktop(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _load,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _KanbanColumn(
              title: 'ยังไม่ทำ',
              color: Colors.red,
              icon: Icons.fiber_new,
              orders: _openOrders,
              onRefresh: _load,
              cardBuilder: (wo) => _buildWorkOrderCard(wo, theme),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _KanbanColumn(
              title: 'กำลังทำ',
              color: Colors.orange,
              icon: Icons.autorenew,
              orders: _inProgressOrders,
              onRefresh: _load,
              cardBuilder: (wo) => _buildWorkOrderCard(wo, theme),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _KanbanColumn(
              title: 'เสร็จแล้ว',
              color: Colors.green,
              icon: Icons.check_circle,
              orders: _completedOrders,
              onRefresh: _load,
              cardBuilder: (wo) => _buildWorkOrderCard(wo, theme),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Mobile Kanban: TabBar + TabBarView ──────────────────
  Widget _buildKanbanMobile(ThemeData theme) {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildStatusList(_openOrders, theme),
        _buildStatusList(_inProgressOrders, theme),
        _buildStatusList(_completedOrders, theme),
      ],
    );
  }

  Widget _buildStatusList(List<WorkOrder> orders, ThemeData theme) {
    if (orders.isEmpty) {
      return const Center(child: Text('ไม่มีใบงาน'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: orders.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildWorkOrderCard(orders[index], theme),
        ),
      ),
    );
  }

  Widget _buildWorkOrderCard(WorkOrder wo, ThemeData theme) {
    final propertyName = _propertyNames[wo.propertyId] ?? '';
    final creatorName =
        wo.createdBy != null ? _creatorNames[wo.createdBy] : null;
    final isNew = wo.status == WorkOrderStatus.open;
    final hasExpense = _workOrderIdsWithExpense.contains(wo.id);

    return Card(
      margin: const EdgeInsets.only(bottom: 0),
      color: isNew ? Colors.red.shade50 : null,
      shape: isNew
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.red.withValues(alpha: 0.3)),
            )
          : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await context.push('/work-orders/${wo.id}');
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      wo.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isNew ? Colors.red.shade800 : null,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _priorityBadge(wo.priority),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.home_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      propertyName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (creatorName != null) ...[
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.person_outline,
                      size: 13,
                      color: Colors.grey,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      creatorName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
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
                                color:
                                    hasExpense ? Colors.green : Colors.orange,
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

  String _buildTitle() {
    if (_filterMode == 'today') return 'งานใหม่วันนี้';
    if (_filterMode == 'urgent') return 'งานด่วน';
    if (_filterMode == 'no-expense') return 'ยังไม่บันทึกค่าใช้จ่าย';
    if (_propertyId != null) {
      final name = _propertyNames[_propertyId];
      return name != null ? 'ใบงาน: $name' : 'ใบงานของบ้าน';
    }
    return 'ใบงานทั้งหมด';
  }
}

// ─── Kanban Column Widget ────────────────────────────────
class _KanbanColumn extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final List<WorkOrder> orders;
  final Future<void> Function() onRefresh;
  final Widget Function(WorkOrder) cardBuilder;

  const _KanbanColumn({
    required this.title,
    required this.color,
    required this.icon,
    required this.orders,
    required this.onRefresh,
    required this.cardBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Column header
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            border: Border(bottom: BorderSide(color: color.withValues(alpha: 0.2))),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${orders.length}',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Scrollable card list
        Expanded(
          child: orders.isEmpty
              ? Center(
                  child: Text(
                    'ไม่มีใบงาน',
                    style: TextStyle(color: Colors.grey.shade400),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: onRefresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: orders.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: cardBuilder(orders[index]),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// ─── Tab label with count badge ────────────────────────
class _TabLabel extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _TabLabel(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

