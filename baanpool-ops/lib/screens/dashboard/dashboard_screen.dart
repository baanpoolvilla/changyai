import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../app/theme.dart';
import '../../services/auth_state_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/page_wrapper.dart';
import '../../utils/error_message.dart';
import '../../widgets/notification_bell.dart';

/// Dashboard — PR รอ CEO, งานวันนี้, PM ใกล้ครบ, ใบงานล่าสุด
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  bool _loading = true;

  int _pendingPRCount = 0;
  int _todayCount = 0;
  int _pmDueSoonCount = 0;
  int _noExpenseCount = 0;
  List<Map<String, dynamic>> _recentWorkOrders = [];
  Map<String, String> _propertyNames = {};
  Map<String, double> _expenseByProperty = {};
  double _totalExpense = 0;
  Map<String, String> _categoryNames = {}; // prefix → display_name
  String? _selectedCategory; // null = group by category; non-null = drill into category

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getPendingPRCount(),
        _service.getTodayJobsCount(),
        _service.getRecentWorkOrders(limit: 5),
        _service.getPropertyNamesOnly(),
        _service.getNoExpenseWorkOrdersCount(),
        _service.getExpenses(),
      ]);

      _pendingPRCount = results[0] as int;
      _todayCount = results[1] as int;
      _recentWorkOrders = results[2] as List<Map<String, dynamic>>;
      final allProperties = results[3] as List<Map<String, dynamic>>;
      _noExpenseCount = results[4] as int;
      final allExpenses = results[5] as List<Map<String, dynamic>>;

      _propertyNames = {
        for (final p in allProperties) p['id'] as String: p['name'] as String,
      };

      // Compute expense by property for current month
      final now = DateTime.now();
      _expenseByProperty = {};
      _totalExpense = 0;
      for (final e in allExpenses) {
        final isNoExpense = e['is_no_expense'] as bool? ?? false;
        if (isNoExpense) continue;
        final dateStr = e['expense_date'] as String?;
        if (dateStr == null) continue;
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        if (date.year != now.year || date.month != now.month) continue;
        final pid = e['property_id'] as String? ?? 'unknown';
        final amount = (e['amount'] as num?)?.toDouble() ?? 0;
        _expenseByProperty[pid] = (_expenseByProperty[pid] ?? 0) + amount;
        _totalExpense += amount;
      }

      // PM due soon — wrapped in try/catch because migration_003 might not be run
      try {
        final pmData = await _service.getPmSchedules(dueSoon: true);
        _pmDueSoonCount = pmData.length;
      } catch (_) {
        _pmDueSoonCount = 0;
      }

      // Property categories — optional (table may not exist)
      try {
        _categoryNames = await _service.getPropertyCategories();
      } catch (_) {}
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: ${friendlyError(e)}')));
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
                                  title: 'PR รอ CEO อนุมัติ', value: '$_pendingPRCount',
                                  icon: Icons.shopping_cart_outlined, color: Colors.orange,
                                  onTap: () => context.go('/purchase-orders'),
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
                                  title: 'PR รอ CEO อนุมัติ', value: '$_pendingPRCount',
                                  icon: Icons.shopping_cart_outlined, color: Colors.orange,
                                  onTap: () => context.go('/purchase-orders'),
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

                      // Expense Chart for current month
                      _SectionHeader(
                        title: 'ค่าใช้จ่ายเดือนนี้',
                        onSeeAll: () => context.go('/expenses'),
                      ),
                      const SizedBox(height: 8),
                      _buildExpenseChart(theme),

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

  // Derive category prefix for a property name
  String _getCategoryPrefix(String propertyName) {
    // Match longest prefix first (e.g. BS-HS before BS-H)
    final prefixes = _categoryNames.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final prefix in prefixes) {
      if (propertyName.startsWith(prefix)) return prefix;
    }
    // Fallback: strip trailing digits
    final match = RegExp(r'^(.*\D)(\d+)$').firstMatch(propertyName);
    return match?.group(1) ?? propertyName;
  }

  Widget _buildExpenseChart(ThemeData theme) {
    if (_expenseByProperty.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Text(
              'ยังไม่มีค่าใช้จ่ายในเดือนนี้',
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey),
            ),
          ),
        ),
      );
    }

    const colors = [
      Color(0xFF4CAF50),
      Color(0xFF2196F3),
      Color(0xFFF44336),
      Color(0xFFFF9800),
      Color(0xFF9C27B0),
      Color(0xFF00BCD4),
      Color(0xFFFF5722),
      Color(0xFF607D8B),
      Color(0xFFE91E63),
      Color(0xFF795548),
    ];

    String formatAmount(double amount) {
      final s = amount.toStringAsFixed(0);
      final formatted = s.replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'),
        (m) => '${m[1]},',
      );
      return '฿$formatted';
    }

    // ── Find all categories that have expenses ─────────────────
    final Map<String, List<String>> catToPropertyIds = {};
    for (final pid in _expenseByProperty.keys) {
      final name = _propertyNames[pid] ?? pid;
      final prefix = _getCategoryPrefix(name);
      catToPropertyIds.putIfAbsent(prefix, () => []).add(pid);
    }
    // Sorted category prefixes by total amount descending
    final allCategories = catToPropertyIds.keys.toList()
      ..sort((a, b) {
        final sumA = catToPropertyIds[a]!
            .fold(0.0, (s, pid) => s + (_expenseByProperty[pid] ?? 0));
        final sumB = catToPropertyIds[b]!
            .fold(0.0, (s, pid) => s + (_expenseByProperty[pid] ?? 0));
        return sumB.compareTo(sumA);
      });

    // ── Build chart data based on selected category ────────────
    final Map<String, double> displayData;
    final Map<String, String> displayLabels;

    if (_selectedCategory == null) {
      // Group by category
      displayData = {
        for (final cat in allCategories)
          cat: catToPropertyIds[cat]!
              .fold(0.0, (s, pid) => s + (_expenseByProperty[pid] ?? 0)),
      };
      displayLabels = {
        for (final cat in allCategories)
          cat: _categoryNames[cat] ?? cat,
      };
    } else {
      // Drill into a specific category → show individual properties
      final pids = catToPropertyIds[_selectedCategory] ?? [];
      displayData = {
        for (final pid in pids) pid: _expenseByProperty[pid] ?? 0,
      };
      displayLabels = {
        for (final pid in pids) pid: _propertyNames[pid] ?? pid,
      };
    }

    final sorted = displayData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final values = sorted.map((e) => e.value).toList();
    final labels = sorted.map((e) => displayLabels[e.key] ?? e.key).toList();
    final entryColors = List.generate(
      sorted.length,
      (i) => colors[i % colors.length],
    );
    final viewTotal = values.fold(0.0, (s, v) => s + v);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Category filter chips ────────────────────────
            if (allCategories.length > 1)
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    FilterChip(
                      label: const Text('ทั้งหมด'),
                      selected: _selectedCategory == null,
                      onSelected: (_) =>
                          setState(() => _selectedCategory = null),
                    ),
                    ...allCategories.map(
                      (cat) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: FilterChip(
                          label: Text(_categoryNames[cat] ?? cat),
                          selected: _selectedCategory == cat,
                          onSelected: (_) => setState(() {
                            _selectedCategory =
                                _selectedCategory == cat ? null : cat;
                          }),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (allCategories.length > 1) const SizedBox(height: 12),

            // ── Donut chart ──────────────────────────────────
            SizedBox(
              height: 200,
              child: CustomPaint(
                painter: _DonutChartPainter(
                  values: values,
                  colors: entryColors,
                  centerText: formatAmount(viewTotal),
                  centerSubText: _selectedCategory == null
                      ? 'รวม'
                      : (_categoryNames[_selectedCategory] ??
                          _selectedCategory!),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 16),

            // ── Legend ───────────────────────────────────────
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: List.generate(sorted.length, (i) {
                final pct = viewTotal > 0
                    ? (sorted[i].value / viewTotal * 100)
                    : 0.0;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: entryColors[i],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          labels[i],
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${formatAmount(sorted[i].value)}  (${pct.toStringAsFixed(0)}%)',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }),
            ),
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

// ─── Donut Chart Painter ─────────────────────────────────
class _DonutChartPainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final String centerText;
  final String centerSubText;

  const _DonutChartPainter({
    required this.values,
    required this.colors,
    required this.centerText,
    this.centerSubText = '',
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<double>(0, (s, v) => s + v);
    if (total == 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 8;
    const strokeWidth = 44.0;
    const gapAngle = 0.03; // small gap between segments

    double startAngle = -math.pi / 2;
    for (int i = 0; i < values.length; i++) {
      final sweep = (values[i] / total) * 2 * math.pi - gapAngle;
      if (sweep <= 0) continue;

      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );
      startAngle += sweep + gapAngle;
    }

    // Center sub text
    if (centerSubText.isNotEmpty) {
      final subPainter = TextPainter(
        text: TextSpan(
          text: centerSubText,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 12,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      subPainter.paint(
        canvas,
        center - Offset(subPainter.width / 2, subPainter.height + 14),
      );
    }

    // Center main text
    final textPainter = TextPainter(
      text: TextSpan(
        text: centerText,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      center - Offset(textPainter.width / 2, textPainter.height / 2 - 4),
    );
  }

  @override
  bool shouldRepaint(_DonutChartPainter old) =>
      old.values != values || old.colors != colors;
}
