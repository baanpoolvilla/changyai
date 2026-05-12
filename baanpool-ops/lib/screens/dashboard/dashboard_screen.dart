import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme.dart';
import '../../services/auth_state_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/page_wrapper.dart';

/// Dashboard — งานด่วน, งานวันนี้, PM ใกล้ครบ, ใบงานล่าสุด
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  bool _loading = true;

  int _urgentCount = 0;
  int _todayCount = 0;
  int _pmDueSoonCount = 0;
  int _noExpenseCount = 0;
  List<Map<String, dynamic>> _recentWorkOrders = [];
  Map<String, String> _propertyNames = {};
  List<Map<String, dynamic>> _allProperties = [];
  Map<String, Map<String, int>> _propertyWoStatus = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getUrgentJobsCount(),
        _service.getTodayJobsCount(),
        _service.getRecentWorkOrders(limit: 5),
        _service.getPropertyNamesOnly(),
        _service.getNoExpenseWorkOrdersCount(),
      ]);

      _urgentCount = results[0] as int;
      _todayCount = results[1] as int;
      _recentWorkOrders = results[2] as List<Map<String, dynamic>>;
      final allProperties = results[3] as List<Map<String, dynamic>>;
      _noExpenseCount = results[4] as int;

      _allProperties = allProperties;
      _propertyNames = {
        for (final p in allProperties) p['id'] as String: p['name'] as String,
      };

      // Property work order status (for status board)
      final propIds = allProperties.map((p) => p['id'] as String).toList();
      _propertyWoStatus = await _service
          .getWorkOrderStatusCountsForProperties(propIds);

      // PM due soon — wrapped in try/catch because migration_003 might not be run
      try {
        final pmData = await _service.getPmSchedules(dueSoon: true);
        _pmDueSoonCount = pmData.length;
      } catch (_) {
        _pmDueSoonCount = 0;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('แดชบอร์ด'),
        actions: [
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
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: PageWrapper(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary Cards: 4 in a row on desktop, 2x2 on mobile
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isWide = constraints.maxWidth >= 600;
                          if (isWide) {
                            return Row(
                              children: [
                                Expanded(child: _SummaryCard(
                                  title: 'งานด่วน', value: '$_urgentCount',
                                  icon: Icons.warning_amber_rounded, color: AppTheme.urgentColor,
                                  onTap: () => context.go('/work-orders?filter=urgent'),
                                )),
                                const SizedBox(width: 12),
                                Expanded(child: _SummaryCard(
                                  title: 'งานใหม่วันนี้', value: '$_todayCount',
                                  icon: Icons.today, color: AppTheme.primaryColor,
                                  onTap: () => context.go('/work-orders?filter=today'),
                                )),
                                const SizedBox(width: 12),
                                Expanded(child: _SummaryCard(
                                  title: 'PM ใกล้ครบกำหนด', value: '$_pmDueSoonCount',
                                  icon: Icons.schedule, color: AppTheme.warningColor,
                                  onTap: () => context.go('/pm'),
                                )),
                                const SizedBox(width: 12),
                                Expanded(child: _SummaryCard(
                                  title: 'ยังไม่บันทึกค่าใช้จ่าย', value: '$_noExpenseCount',
                                  icon: Icons.receipt_long, color: Colors.red,
                                  onTap: () => context.go('/work-orders?filter=no-expense'),
                                )),
                              ],
                            );
                          }
                          return Column(
                            children: [
                              Row(children: [
                                Expanded(child: _SummaryCard(
                                  title: 'งานด่วน', value: '$_urgentCount',
                                  icon: Icons.warning_amber_rounded, color: AppTheme.urgentColor,
                                  onTap: () => context.go('/work-orders?filter=urgent'),
                                )),
                                const SizedBox(width: 12),
                                Expanded(child: _SummaryCard(
                                  title: 'งานใหม่วันนี้', value: '$_todayCount',
                                  icon: Icons.today, color: AppTheme.primaryColor,
                                  onTap: () => context.go('/work-orders?filter=today'),
                                )),
                              ]),
                              const SizedBox(height: 12),
                              Row(children: [
                                Expanded(child: _SummaryCard(
                                  title: 'PM ใกล้ครบกำหนด', value: '$_pmDueSoonCount',
                                  icon: Icons.schedule, color: AppTheme.warningColor,
                                  onTap: () => context.go('/pm'),
                                )),
                                const SizedBox(width: 12),
                                Expanded(child: _SummaryCard(
                                  title: 'ยังไม่บันทึกค่าใช้จ่าย', value: '$_noExpenseCount',
                                  icon: Icons.receipt_long, color: Colors.red,
                                  onTap: () => context.go('/work-orders?filter=no-expense'),
                                )),
                              ]),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 24),

                      // Property Status Board
                      _SectionHeader(
                        title: 'สถานะบ้าน',
                        onSeeAll: () => context.go('/work-orders'),
                      ),
                      const SizedBox(height: 8),
                      _buildPropertyStatusBoard(theme),

                      const SizedBox(height: 24),

                      // Recent Work Orders
                      _SectionHeader(
                        title: 'งานล่าสุด',
                        onSeeAll: () => context.go('/work-orders'),
                      ),
                      const SizedBox(height: 8),
                      if (_recentWorkOrders.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                'ยังไม่มีใบงาน',
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyMedium?.copyWith(
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      ),
                    )
                  else
                    ...(_recentWorkOrders.map((wo) {
                      final title = wo['title'] as String? ?? '';
                      final status = wo['status'] as String? ?? 'open';
                      final priority = wo['priority'] as String? ?? 'medium';
                      final propertyId = wo['property_id'] as String? ?? '';
                      final propertyName = _propertyNames[propertyId] ?? '';
                      final id = wo['id'] as String;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: status == 'open' ? Colors.red.shade50 : null,
                        child: ListTile(
                          leading: Icon(
                            _statusIcon(status),
                            color: _statusColor(status),
                          ),
                          title: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: status == 'open'
                                ? TextStyle(
                                    color: Colors.red.shade800,
                                    fontWeight: FontWeight.bold,
                                  )
                                : null,
                          ),
                          subtitle: Text(propertyName),
                          trailing: status == 'open'
                              ? Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : _priorityDot(priority),
                          onTap: () async {
                            await context.push('/work-orders/$id');
                            _load();
                          },
                        ),
                      );
                    })),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildPropertyStatusBoard(ThemeData theme) {
    if (_allProperties.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 600;
        final crossCount = isWide ? 3 : 2;
        final cards = _allProperties.map((p) {
          final id = p['id'] as String;
          final name = p['name'] as String;
          final counts = _propertyWoStatus[id] ?? {};
          final openCount = counts['open'] ?? 0;
          final inProgressCount = counts['in_progress'] ?? 0;
          final total = openCount + inProgressCount;

          Color borderColor;
          Color bgColor;
          IconData statusIcon;
          String statusLabel;
          if (openCount > 0) {
            borderColor = Colors.red;
            bgColor = Colors.red.shade50;
            statusIcon = Icons.warning_amber_rounded;
            statusLabel = '\u0e23\u0e2d\u0e14\u0e33\u0e40\u0e19\u0e34\u0e19\u0e01\u0e32\u0e23';
          } else if (inProgressCount > 0) {
            borderColor = Colors.orange;
            bgColor = Colors.orange.shade50;
            statusIcon = Icons.autorenew;
            statusLabel = '\u0e01\u0e33\u0e25\u0e31\u0e07\u0e17\u0e33';
          } else {
            borderColor = Colors.green;
            bgColor = Colors.green.shade50;
            statusIcon = Icons.check_circle_outline;
            statusLabel = '\u0e40\u0e23\u0e35\u0e22\u0e1a\u0e23\u0e49\u0e2d\u0e22';
          }

          return InkWell(
            onTap: () => context.go('/work-orders'),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: borderColor.withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.home, size: 14, color: borderColor),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: borderColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(statusIcon, size: 14, color: borderColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: TextStyle(fontSize: 11, color: borderColor),
                      ),
                    ],
                  ),
                  if (total > 0) ...[
                    const SizedBox(height: 4),
                    if (openCount > 0)
                      Text(
                        '\u2022 \u0e23\u0e2d: $openCount \u0e43\u0e1a\u0e07\u0e32\u0e19',
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    if (inProgressCount > 0)
                      Text(
                        '\u2022 \u0e17\u0e33\u0e2d\u0e22\u0e39\u0e48: $inProgressCount \u0e43\u0e1a\u0e07\u0e32\u0e19',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.orange),
                      ),
                  ],
                ],
              ),
            ),
          );
        }).toList();

        // Grid layout
        final rows = <Widget>[];
        for (int i = 0; i < cards.length; i += crossCount) {
          final rowCards = <Widget>[...cards.skip(i).take(crossCount)];
          while (rowCards.length < crossCount) {
            rowCards.add(const SizedBox.shrink());
          }
          rows.add(
            Row(
              children: rowCards
                  .map((c) => Expanded(child: c))
                  .expand((w) => [w, const SizedBox(width: 10)])
                  .toList()
                ..removeLast(),
            ),
          );
          if (i + crossCount < cards.length) rows.add(const SizedBox(height: 10));
        }
        return Column(children: rows);
      },
    );
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'open':
        return Icons.fiber_new;
      case 'in_progress':
        return Icons.autorenew;
      case 'completed':
        return Icons.check_circle;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.help_outline;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.red;
      case 'in_progress':
        return Colors.orange;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  Widget _priorityDot(String priority) {
    Color color;
    switch (priority) {
      case 'urgent':
        color = Colors.red;
      case 'high':
        color = Colors.orange;
      case 'medium':
        color = Colors.blue;
      default:
        color = Colors.grey;
    }
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const _SectionHeader({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (onSeeAll != null)
          TextButton(onPressed: onSeeAll, child: const Text('ดูทั้งหมด')),
      ],
    );
  }
}
