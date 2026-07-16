import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/purchase_order.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_state_service.dart';
import '../../utils/thai_datetime.dart';
import '../../utils/page_wrapper.dart';
import '../../utils/error_message.dart';

class PurchaseOrdersListScreen extends StatefulWidget {
  const PurchaseOrdersListScreen({super.key});

  @override
  State<PurchaseOrdersListScreen> createState() =>
      _PurchaseOrdersListScreenState();
}

class _PurchaseOrdersListScreenState extends State<PurchaseOrdersListScreen>
    with SingleTickerProviderStateMixin {
  final _service = SupabaseService(Supabase.instance.client);
  final _authState = AuthStateService();
  List<PurchaseOrder> _orders = [];
  bool _loading = true;
  Map<String, String> _propertyNames = {};

  late TabController _tabController;

  // PR: รอ CEO อนุมัติ
  List<PurchaseOrder> get _prOrders =>
      _orders.where((o) => o.status == POStatus.pending).toList();

  // PO ที่ได้รับ: CEO อนุมัติแล้ว รอดำเนินการ
  List<PurchaseOrder> get _poReceivedOrders =>
      _orders.where((o) => o.status == POStatus.approved).toList();

  // กำลังดำเนินการ: กำลังซื้อของ
  List<PurchaseOrder> get _activeOrders =>
      _orders.where((o) => o.status == POStatus.ordered).toList();

  // เสร็จสิ้น: รับของแล้ว + ยกเลิก
  List<PurchaseOrder> get _doneOrders => _orders
      .where(
        (o) =>
            o.status == POStatus.received || o.status == POStatus.cancelled,
      )
      .toList();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getPurchaseOrders(),
        _service.getPropertyNamesOnly(),
      ]);
      final data = results[0] as List<Map<String, dynamic>>;
      _orders = data.map((e) => PurchaseOrder.fromJson(e)).toList();
      final props = results[1] as List<Map<String, dynamic>>;
      _propertyNames = {
        for (final p in props) p['id'] as String: p['name'] as String,
      };
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: ${friendlyError(e)}')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 720;

    return Scaffold(
      appBar: AppBar(
        title: const Text('สั่งอุปกรณ์ (PR/PO)'),
        bottom: !isDesktop
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(
                    child: _TabBadge('PR', _prOrders.length, Colors.orange),
                  ),
                  Tab(
                    child: _TabBadge(
                        'PO ที่ได้รับ', _poReceivedOrders.length, Colors.blue),
                  ),
                  Tab(
                    child: _TabBadge(
                        'ดำเนินการ', _activeOrders.length, Colors.indigo),
                  ),
                  Tab(
                    child:
                        _TabBadge('เสร็จสิ้น', _doneOrders.length, Colors.grey),
                  ),
                ],
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isDesktop
              ? _buildDesktopKanban()
              : _buildMobileTabs(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/purchase-orders/new');
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('เปิด PR'),
      ),
    );
  }

  Widget _buildDesktopKanban() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _PoColumn(
            title: 'PR',
            subtitle: 'รอ CEO อนุมัติ',
            color: Colors.orange,
            icon: Icons.receipt_long_outlined,
            orders: _prOrders,
            propertyNames: _propertyNames,
            authState: _authState,
            onRefresh: _load,
            onTap: _openDetail,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _PoColumn(
            title: 'PO ที่ได้รับ',
            subtitle: 'CEO อนุมัติแล้ว',
            color: Colors.blue,
            icon: Icons.assignment_turned_in_outlined,
            orders: _poReceivedOrders,
            propertyNames: _propertyNames,
            authState: _authState,
            onRefresh: _load,
            onTap: _openDetail,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _PoColumn(
            title: 'กำลังดำเนินการ',
            subtitle: 'กำลังซื้อของ',
            color: Colors.indigo,
            icon: Icons.local_shipping_outlined,
            orders: _activeOrders,
            propertyNames: _propertyNames,
            authState: _authState,
            onRefresh: _load,
            onTap: _openDetail,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: _PoColumn(
            title: 'เสร็จสิ้น',
            subtitle: 'รับของแล้ว / ยกเลิก',
            color: Colors.grey,
            icon: Icons.check_circle_outline,
            orders: _doneOrders,
            propertyNames: _propertyNames,
            authState: _authState,
            onRefresh: _load,
            onTap: _openDetail,
          ),
        ),
      ],
    );
  }

  Widget _buildMobileTabs() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildList(_prOrders),
        _buildList(_poReceivedOrders),
        _buildList(_activeOrders),
        _buildList(_doneOrders),
      ],
    );
  }

  Widget _buildList(List<PurchaseOrder> orders) {
    if (orders.isEmpty) {
      return const Center(child: Text('ไม่มีรายการ'));
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: orders.length,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PoCard(
            order: orders[i],
            propertyName: _propertyNames[orders[i].propertyId] ?? '',
            authState: _authState,
            onTap: () => _openDetail(orders[i]),
          ),
        ),
      ),
    );
  }

  void _openDetail(PurchaseOrder order) async {
    await context.push('/purchase-orders/${order.id}');
    _load();
  }
}

// ─── Column Widget ─────────────────────────────────────
class _PoColumn extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color color;
  final IconData icon;
  final List<PurchaseOrder> orders;
  final Map<String, String> propertyNames;
  final AuthStateService authState;
  final Future<void> Function() onRefresh;
  final void Function(PurchaseOrder) onTap;

  const _PoColumn({
    required this.title,
    required this.subtitle,
    required this.color,
    required this.icon,
    required this.orders,
    required this.propertyNames,
    required this.authState,
    required this.onRefresh,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            border: Border(
                bottom: BorderSide(color: color.withValues(alpha: 0.2))),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: color.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
        Expanded(
          child: orders.isEmpty
              ? Center(
                  child: Text('ไม่มีรายการ',
                      style: TextStyle(color: Colors.grey.shade400)))
              : RefreshIndicator(
                  onRefresh: onRefresh,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: orders.length,
                    itemBuilder: (ctx, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _PoCard(
                        order: orders[i],
                        propertyName:
                            propertyNames[orders[i].propertyId] ?? '',
                        authState: authState,
                        onTap: () => onTap(orders[i]),
                      ),
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

// ─── Card Widget ───────────────────────────────────────
class _PoCard extends StatelessWidget {
  final PurchaseOrder order;
  final String propertyName;
  final AuthStateService authState;
  final VoidCallback onTap;

  const _PoCard({
    required this.order,
    required this.propertyName,
    required this.authState,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = _statusColor(order.status);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      order.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (order.isEmergencyPurchase) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warning_amber,
                              size: 10, color: Colors.red.shade700),
                          const SizedBox(width: 3),
                          Text('ฉุกเฉิน',
                              style: TextStyle(
                                  color: Colors.red.shade700,
                                  fontSize: 10)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: statusColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      order.status.displayName,
                      style: TextStyle(color: statusColor, fontSize: 11),
                    ),
                  ),
                ],
              ),
              if (propertyName.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.home_outlined,
                        size: 13, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      propertyName,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.outline),
                    ),
                  ],
                ),
              ],
              if (order.items.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '${order.items.length} รายการ  •  ฿${order.totalPrice.toStringAsFixed(0)}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline),
                ),
              ],
              // แสดงผู้รับ PO (ถ้ามี)
              if (order.poAssignedToName != null &&
                  order.poAssignedToName!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.assignment_ind_outlined,
                        size: 13, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text(
                      'มอบหมาย: ${order.poAssignedToName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.blue.shade700),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.person_outline, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    order.createdByName ?? 'ไม่ทราบ',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.calendar_today_outlined, size: 13, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    formatThaiDate(order.createdAt),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(POStatus s) {
    switch (s) {
      case POStatus.pending:
        return Colors.orange;
      case POStatus.approved:
        return Colors.blue;
      case POStatus.ordered:
        return Colors.indigo;
      case POStatus.received:
        return Colors.green;
      case POStatus.cancelled:
        return Colors.grey;
    }
  }
}

// ─── Tab Badge ─────────────────────────────────────────
class _TabBadge extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  const _TabBadge(this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12)),
        if (count > 0) ...[
          const SizedBox(width: 4),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ],
    );
  }
}
