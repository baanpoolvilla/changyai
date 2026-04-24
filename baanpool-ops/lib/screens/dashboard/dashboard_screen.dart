import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme.dart';
import '../../services/auth_state_service.dart';
import '../../services/line_notify_service.dart';
import '../../services/supabase_service.dart';

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
  int _totalProperties = 0;
  List<Map<String, dynamic>> _recentWorkOrders = [];
  Map<String, String> _propertyNames = {};

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
      ]);

      _urgentCount = results[0] as int;
      _todayCount = results[1] as int;
      _recentWorkOrders = results[2] as List<Map<String, dynamic>>;
      final allProperties = results[3] as List<Map<String, dynamic>>;

      _totalProperties = allProperties.length;
      _propertyNames = {
        for (final p in allProperties) p['id'] as String: p['name'] as String,
      };

      // PM due soon — wrapped in try/catch because migration_003 might not be run
      try {
        final pmData = await _service.getPmSchedules(dueSoon: true);
        _pmDueSoonCount = pmData.length;

        // Trigger PM notifications check (LINE + in-app) in background
        if (_pmDueSoonCount > 0) {
          LineNotifyService().checkAndNotifyPmDueSchedules();
        }
      } catch (_) {
        _pmDueSoonCount = 0;
      }

      // Check for completed work orders missing expenses → LINE reminder
      try {
        final now = DateTime.now();
        if (now.hour >= 17) {
          LineNotifyService().checkAndNotifyMissingExpenses();
        }
      } catch (_) {
        // Ignore errors from expense reminder check
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
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Summary Cards Row 1
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          title: 'งานด่วน',
                          value: '$_urgentCount',
                          icon: Icons.warning_amber_rounded,
                          color: AppTheme.urgentColor,
                          onTap: () => context.go('/work-orders'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          title: 'งานวันนี้',
                          value: '$_todayCount',
                          icon: Icons.today,
                          color: AppTheme.primaryColor,
                          onTap: () => context.go('/work-orders'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _SummaryCard(
                          title: 'PM ใกล้ครบ',
                          value: '$_pmDueSoonCount',
                          icon: Icons.schedule,
                          color: AppTheme.warningColor,
                          onTap: () => context.go('/pm'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryCard(
                          title: 'จำนวนบ้าน',
                          value: '$_totalProperties',
                          icon: Icons.home,
                          color: AppTheme.secondaryColor,
                          onTap: () => context.go('/properties'),
                        ),
                      ),
                    ],
                  ),

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
