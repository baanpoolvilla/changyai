import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/work_order.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_state_service.dart';
import '../../utils/thai_datetime.dart';
import '../../utils/page_wrapper.dart';
import '../../utils/error_message.dart';
import '../../widgets/notification_bell.dart';

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

  // ─── ตัวกรองตามบ้าน (รูปแบบเดียวกับหน้า PM) ───────────
  String? _selectedPropertyGroup; // null = ทุกหมวด
  String? _selectedHouseId; // null = ทุกหลังในหมวด

  /// ดึงหมวดบ้านจากชื่อ เช่น "BS-M4" → "BS-M", "PT-BT1" → "PT-BT"
  String _getPropertyGroup(String propertyName) {
    final match = RegExp(r'^([A-Za-z]+-[A-Za-z]+)').firstMatch(propertyName);
    if (match != null) return match.group(1)!.toUpperCase();
    final fallback = RegExp(r'^(.+?)\d+$').firstMatch(propertyName);
    if (fallback != null) return fallback.group(1)!.toUpperCase();
    return propertyName.toUpperCase();
  }

  /// ใบงานหลังผ่านตัวกรองบ้านแล้ว — ทุกแท็บนับจากชุดนี้
  List<WorkOrder> get _visibleOrders {
    if (_selectedHouseId != null) {
      return _workOrders
          .where(
            (w) =>
                w.propertyId == _selectedHouseId ||
                w.additionalPropertyIds.contains(_selectedHouseId),
          )
          .toList();
    }
    if (_selectedPropertyGroup == null) return _workOrders;
    return _workOrders.where((w) {
      // ใบงานหลายบ้าน — เข้าเกณฑ์ถ้าบ้านใดบ้านหนึ่งอยู่ในหมวดนี้
      final ids = [w.propertyId, ...w.additionalPropertyIds];
      return ids.any((id) {
        final name = _propertyNames[id];
        if (name == null) return false;
        return _getPropertyGroup(name) == _selectedPropertyGroup;
      });
    }).toList();
  }

  List<WorkOrder> get _openOrders =>
      _visibleOrders.where((w) => w.status == WorkOrderStatus.open).toList();
  List<WorkOrder> get _inProgressOrders => _visibleOrders
      .where((w) => w.status == WorkOrderStatus.inProgress)
      .toList();
  /// ใบงานที่ "ไม่มีค่าใช้จ่าย" (ตั้งไว้ที่ PM) ปิดงานแล้วถือว่าเสร็จสมบูรณ์เลย
  bool _isSettled(WorkOrder w) =>
      !w.requiresExpense || _workOrderIdsWithExpense.contains(w.id);

  List<WorkOrder> get _noExpenseOrders =>
      _visibleOrders
          .where(
            (w) => w.status == WorkOrderStatus.completed && !_isSettled(w),
          )
          .toList();
  List<WorkOrder> get _completedOrders =>
      _visibleOrders
          .where(
            (w) =>
                w.status == WorkOrderStatus.cancelled ||
                (w.status == WorkOrderStatus.completed && _isSettled(w)),
          )
          .toList();

  @override
  void initState() {
    super.initState();
    _filterMode = widget.initialFilter;
    _propertyId = widget.propertyId;
    _tabController = TabController(length: 4, vsync: this);
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
          statuses: _filterMode == 'urgent'
              ? ['open', 'in_progress']
              : null,
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
          SnackBar(content: Text('โหลดข้อมูลล้มเหลว: ${friendlyError(e)}')),
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
                // ป้ายยาวขึ้นแล้ว — เลื่อนได้จะได้ไม่ตัดคำ
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(
                    child: _TabLabel(
                      '🔴 รอดำเนินการ',
                      _openOrders.length,
                      Colors.red,
                    ),
                  ),
                  Tab(
                    child: _TabLabel(
                      '🟡 กำลังดำเนินการ',
                      _inProgressOrders.length,
                      Colors.orange,
                    ),
                  ),
                  Tab(
                    child: _TabLabel(
                      '🟠 เสร็จสิ้น/ยังไม่บันทึกค่าใช้จ่าย',
                      _noExpenseOrders.length,
                      Colors.deepOrange,
                    ),
                  ),
                  Tab(
                    child: _TabLabel(
                      '✅ เสร็จสมบูรณ์',
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
          const NotificationBell(),
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
          : Column(
              children: [
                if (!_isFilterMode) _buildPropertyFilter(theme),
                Expanded(
                  child: _isFilterMode
                      ? _buildFilteredList(theme)
                      : isDesktop
                      ? _buildKanbanDesktop(theme)
                      : _buildKanbanMobile(theme),
                ),
              ],
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

  // ─── Desktop Kanban: 4 columns side by side ─────────────
  Widget _buildKanbanDesktop(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _load,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _KanbanColumn(
              title: 'รอดำเนินการ',
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
              title: 'กำลังดำเนินการ',
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
              title: 'ดำเนินงานเสร็จสิ้น/ยังไม่บันทึกค่าใช้จ่าย',
              color: Colors.deepOrange,
              icon: Icons.receipt_long,
              orders: _noExpenseOrders,
              onRefresh: _load,
              cardBuilder: (wo) => _buildWorkOrderCard(wo, theme),
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: _KanbanColumn(
              title: 'เสร็จสมบูรณ์',
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
        _buildStatusList(_noExpenseOrders, theme),
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

  /// แถบกรองตามบ้าน: แถวบน = หมวด, แถวล่าง = บ้านในหมวดที่เลือก
  Widget _buildPropertyFilter(ThemeData theme) {
    // เอาเฉพาะบ้านที่มีใบงานจริง
    final usedIds = <String>{};
    for (final w in _workOrders) {
      usedIds.add(w.propertyId);
      usedIds.addAll(w.additionalPropertyIds);
    }
    final entries = _propertyNames.entries
        .where((e) => usedIds.contains(e.key))
        .toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    if (entries.isEmpty) return const SizedBox.shrink();

    final grouped = <String, List<MapEntry<String, String>>>{};
    for (final e in entries) {
      grouped.putIfAbsent(_getPropertyGroup(e.value), () => []).add(e);
    }
    final groups = grouped.keys.toList()..sort();
    if (groups.length < 2 && _selectedPropertyGroup == null) {
      return const SizedBox.shrink();
    }

    final housesInGroup = _selectedPropertyGroup == null
        ? <MapEntry<String, String>>[]
        : (grouped[_selectedPropertyGroup] ?? []);

    return Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: const Text('ทุกบ้าน'),
                  selected:
                      _selectedPropertyGroup == null && _selectedHouseId == null,
                  onSelected: (_) => setState(() {
                    _selectedPropertyGroup = null;
                    _selectedHouseId = null;
                  }),
                ),
              ),
              ...groups.map(
                (g) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(g),
                    selected: _selectedPropertyGroup == g,
                    onSelected: (_) => setState(() {
                      if (_selectedPropertyGroup == g) {
                        _selectedPropertyGroup = null;
                      } else {
                        _selectedPropertyGroup = g;
                      }
                      _selectedHouseId = null;
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (housesInGroup.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: const Text('ทุกหลังในหมวด'),
                    selected: _selectedHouseId == null,
                    onSelected: (_) => setState(() => _selectedHouseId = null),
                  ),
                ),
                ...housesInGroup.map(
                  (e) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(e.value),
                      selected: _selectedHouseId == e.key,
                      onSelected: (_) => setState(() {
                        _selectedHouseId =
                            _selectedHouseId == e.key ? null : e.key;
                      }),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// แท็กบอกว่าใบงานนี้ระบบสร้างให้อัตโนมัติจาก PM ไม่ใช่คนกดสร้าง
  Widget _autoCreatedBadge(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.autorenew, size: 11, color: theme.colorScheme.primary),
          const SizedBox(width: 3),
          Text(
            'อัตโนมัติ',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkOrderCard(WorkOrder wo, ThemeData theme) {
    final propertyName = _propertyNames[wo.propertyId] ?? '';
    final creatorName =
        wo.createdBy != null ? _creatorNames[wo.createdBy] : null;
    final isNew = wo.status == WorkOrderStatus.open;
    final hasExpense = _workOrderIdsWithExpense.contains(wo.id);
    // PM ที่ตั้งว่า "ไม่มีค่าใช้จ่าย" — ไม่ต้องทวงให้บันทึก
    final noExpenseNeeded = !wo.requiresExpense;

    return Card(
      margin: const EdgeInsets.only(bottom: 0),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await context.push('/work-orders/${wo.id}');
          _load();
        },
        child: Container(
          // แถบสถานะด้านซ้าย — บอกว่ายังไม่ทำโดยไม่ต้องย้อมการ์ดทั้งใบ
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: isNew ? Colors.red.shade400 : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(11, 12, 12, 12),
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
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (wo.autoCreated) ...[
                    _autoCreatedBadge(theme),
                    const SizedBox(width: 4),
                  ],
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
                        Builder(
                          builder: (_) {
                            final settled = noExpenseNeeded || hasExpense;
                            final color =
                                settled ? Colors.green : Colors.orange;
                            final label = noExpenseNeeded
                                ? 'ไม่มีค่าใช้จ่าย'
                                : hasExpense
                                ? 'บันทึกค่าใช้จ่ายแล้ว'
                                : 'ยังไม่บันทึกค่าใช้จ่าย';
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: color.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    noExpenseNeeded
                                        ? Icons.money_off
                                        : hasExpense
                                        ? Icons.receipt_long
                                        : Icons.receipt_long_outlined,
                                    size: 12,
                                    color: color,
                                  ),
                                  const SizedBox(width: 3),
                                  Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: color,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
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
        label = 'ปานกลาง';
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
    if (_filterMode == 'no-expense') {
      return 'ดำเนินงานเสร็จสิ้น/ยังไม่บันทึกค่าใช้จ่าย';
    }
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
              // ชื่อคอลัมน์ยาวได้ (เช่น "ดำเนินงานเสร็จสิ้น/ยังไม่บันทึกค่าใช้จ่าย")
              // ให้ตัดบรรทัดแทนที่จะล้นออกนอกหัวคอลัมน์
              Flexible(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
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

