import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/expense.dart';
import '../../services/supabase_service.dart';

class ExpenseReportScreen extends StatefulWidget {
  const ExpenseReportScreen({super.key});

  @override
  State<ExpenseReportScreen> createState() => _ExpenseReportScreenState();
}

class _ExpenseReportScreenState extends State<ExpenseReportScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  bool _loading = true;

  // Current selected month
  late int _selectedYear;
  late int _selectedMonth;

  // Data
  List<Expense> _allExpenses = [];
  List<Map<String, dynamic>> _properties = [];

  // Computed report data
  final Map<String, List<Expense>> _expensesByProperty = {};
  final Map<String, double> _totalByProperty = {};
  double _grandTotal = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedYear = now.year;
    _selectedMonth = now.month;
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getExpenses(),
        _service.getProperties(),
      ]);

      _allExpenses = results[0].map((e) => Expense.fromJson(e)).toList();
      _properties = results[1];

      _computeReport();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _computeReport() {
    _expensesByProperty.clear();
    _totalByProperty.clear();
    _grandTotal = 0;

    // Filter expenses for selected month
    final filtered = _allExpenses.where((e) {
      return e.expenseDate.year == _selectedYear &&
          e.expenseDate.month == _selectedMonth;
    }).toList();

    // Group by property_id
    for (final expense in filtered) {
      final pid = expense.propertyId ?? 'unknown';
      _expensesByProperty.putIfAbsent(pid, () => []).add(expense);
      _totalByProperty[pid] = (_totalByProperty[pid] ?? 0) + expense.amount;
      _grandTotal += expense.amount;
    }
  }

  String _getPropertyName(String propertyId) {
    if (propertyId == 'unknown') return 'ไม่ระบุบ้าน';
    final property = _properties.cast<Map<String, dynamic>?>().firstWhere(
      (p) => p?['id'] == propertyId,
      orElse: () => null,
    );
    return property?['name'] as String? ?? 'ไม่ทราบชื่อ';
  }

  String _formatAmount(double amount) {
    final formatted = amount
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return '฿$formatted';
  }

  String _categoryLabel(String? category) {
    switch (category) {
      case 'material':
        return 'วัสดุ';
      case 'labor':
        return 'ค่าแรง';
      case 'contractor':
        return 'ผู้รับเหมา';
      default:
        return category ?? 'อื่น ๆ';
    }
  }

  String _monthName(int month) {
    const months = [
      '',
      'มกราคม',
      'กุมภาพันธ์',
      'มีนาคม',
      'เมษายน',
      'พฤษภาคม',
      'มิถุนายน',
      'กรกฎาคม',
      'สิงหาคม',
      'กันยายน',
      'ตุลาคม',
      'พฤศจิกายน',
      'ธันวาคม',
    ];
    return months[month];
  }

  void _changeMonth(int delta) {
    setState(() {
      _selectedMonth += delta;
      if (_selectedMonth > 12) {
        _selectedMonth = 1;
        _selectedYear++;
      } else if (_selectedMonth < 1) {
        _selectedMonth = 12;
        _selectedYear--;
      }
      _computeReport();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('รายงานค่าใช้จ่ายรายเดือน')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Month selector
                _buildMonthSelector(theme),

                // Grand total card
                _buildGrandTotal(theme),

                // Property breakdown
                Expanded(
                  child: _expensesByProperty.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.receipt_long,
                                size: 64,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'ไม่มีค่าใช้จ่ายในเดือนนี้',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemCount: _expensesByProperty.length,
                            itemBuilder: (context, index) {
                              final entry = _expensesByProperty.entries
                                  .elementAt(index);
                              return _buildPropertyCard(
                                theme,
                                entry.key,
                                entry.value,
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildMonthSelector(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => _changeMonth(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Text(
            '${_monthName(_selectedMonth)} $_selectedYear',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          IconButton(
            onPressed: () => _changeMonth(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildGrandTotal(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        color: theme.colorScheme.primaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.account_balance_wallet,
                color: theme.colorScheme.onPrimaryContainer,
                size: 32,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'รวมทั้งเดือน',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    Text(
                      _formatAmount(_grandTotal),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${_expensesByProperty.length} บ้าน',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    '${_expensesByProperty.values.fold<int>(0, (sum, list) => sum + list.length)} รายการ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
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

  Widget _buildPropertyCard(
    ThemeData theme,
    String propertyId,
    List<Expense> expenses,
  ) {
    final propertyName = _getPropertyName(propertyId);
    final total = _totalByProperty[propertyId] ?? 0;

    // Group by category
    final Map<String, double> categoryTotals = {};
    for (final e in expenses) {
      final cat = e.category ?? 'other';
      categoryTotals[cat] = (categoryTotals[cat] ?? 0) + e.amount;
    }

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: theme.colorScheme.secondaryContainer,
          child: Icon(
            Icons.home,
            color: theme.colorScheme.onSecondaryContainer,
          ),
        ),
        title: Text(
          propertyName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${expenses.length} รายการ • ${_formatAmount(total)}'),
        children: [
          // Category summary
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: categoryTotals.entries.map((cat) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _categoryLabel(cat.key),
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        _formatAmount(cat.value),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),

          const Divider(),

          // Individual expenses
          ...expenses.map(
            (e) => ListTile(
              dense: true,
              leading: Icon(
                _categoryIcon(e.category),
                size: 20,
                color: theme.colorScheme.outline,
              ),
              title: Text(
                e.description ?? _categoryLabel(e.category),
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                '${e.expenseDate.day}/${e.expenseDate.month}/${e.expenseDate.year}',
                style: theme.textTheme.bodySmall,
              ),
              trailing: Text(
                _formatAmount(e.amount),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  IconData _categoryIcon(String? category) {
    switch (category) {
      case 'material':
        return Icons.inventory;
      case 'labor':
        return Icons.engineering;
      case 'contractor':
        return Icons.business;
      default:
        return Icons.receipt;
    }
  }
}
