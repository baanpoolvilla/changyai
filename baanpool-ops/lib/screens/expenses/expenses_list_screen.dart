import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/expense.dart';
import '../../models/user.dart';
import '../../services/auth_state_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/thai_datetime.dart';
import '../../utils/page_wrapper.dart';
import '../../utils/csv_downloader.dart'
import '../../utils/error_message.dart';
    if (dart.library.html) '../../utils/csv_downloader_web.dart';

class ExpensesListScreen extends StatefulWidget {
  const ExpensesListScreen({super.key});

  @override
  State<ExpensesListScreen> createState() => _ExpensesListScreenState();
}

class _ExpensesListScreenState extends State<ExpensesListScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  final _authState = AuthStateService();
  bool _loading = true;

  // Current selected month
  late int _selectedYear;
  late int _selectedMonth;

  // Category filter
  String? _selectedCategoryPrefix; // null = all
  Map<String, String> _categories = {}; // prefix → displayName

  // Data
  List<Expense> _allExpenses = [];
  List<Map<String, dynamic>> _properties = [];
  List<Map<String, dynamic>> _workOrders = [];
  List<Map<String, dynamic>> _purchaseOrders = [];
  List<Map<String, dynamic>> _pmSchedules = [];

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
        _service.getWorkOrders(),
        _service.getPurchaseOrders(),
        _service.getPmSchedules(),
      ]);
      final cats = await _service.getPropertyCategories();

      _allExpenses = results[0].map((e) => Expense.fromJson(e)).toList();
      _properties = results[1];
      _workOrders = results[2];
      _purchaseOrders = results[3];
      _pmSchedules = results[4];
      _categories = cats;

      _computeReport();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: ${friendlyError(e)}')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _computeReport() {
    _expensesByProperty.clear();
    _totalByProperty.clear();
    _grandTotal = 0;

    final filtered = _allExpenses.where((e) {
      return e.expenseDate.year == _selectedYear &&
          e.expenseDate.month == _selectedMonth;
    }).toList();

    for (final expense in filtered) {
      final pid = expense.propertyId ?? 'unknown';

      // Apply category filter: skip properties not in selected category
      if (_selectedCategoryPrefix != null) {
        final propName = _getPropertyName(pid);
        if (!propName.startsWith(_selectedCategoryPrefix!)) continue;
      }

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

  String? _getWorkOrderTitle(String? id) {
    if (id == null) return null;
    final wo = _workOrders.cast<Map<String, dynamic>?>().firstWhere(
      (w) => w?['id'] == id,
      orElse: () => null,
    );
    return wo?['title'] as String?;
  }

  String? _getPurchaseOrderTitle(String? id) {
    if (id == null) return null;
    final po = _purchaseOrders.cast<Map<String, dynamic>?>().firstWhere(
      (p) => p?['id'] == id,
      orElse: () => null,
    );
    return po?['title'] as String?;
  }

  String? _getPmTitle(String? id) {
    if (id == null) return null;
    final pm = _pmSchedules.cast<Map<String, dynamic>?>().firstWhere(
      (p) => p?['id'] == id,
      orElse: () => null,
    );
    return pm?['title'] as String?;
  }

  String? _getExpenseReferenceTitle(Expense expense) {
    return _getWorkOrderTitle(expense.workOrderId) ??
        _getPurchaseOrderTitle(expense.purchaseOrderId) ??
        _getPmTitle(expense.pmScheduleId);
  }

  String _getExpenseDisplayTitle(Expense expense) {
    final referenceTitle = _getExpenseReferenceTitle(expense);
    if (referenceTitle != null && referenceTitle.isNotEmpty) {
      return referenceTitle;
    }

    final description = expense.description?.trim();
    if (description != null && description.isNotEmpty) {
      return description;
    }

    return expense.isNoExpense ? 'ไม่มีค่าใช้จ่าย' : _categoryLabel(expense.category);
  }

  String _getExpenseDisplayDetail(Expense expense) {
    if (expense.isNoExpense) return 'ไม่มีค่าใช้จ่าย';

    final description = expense.description?.trim();
    final referenceTitle = _getExpenseReferenceTitle(expense);
    if (description != null && description.isNotEmpty && description != referenceTitle) {
      return description;
    }

    return _categoryLabel(expense.category);
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

  // ─── Export report as CSV text ─────────────────────────

  Future<void> _exportReport() async {
    if (_expensesByProperty.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ไม่มีข้อมูลค่าใช้จ่ายในเดือนนี้')),
      );
      return;
    }

    final monthLabel = '${_monthName(_selectedMonth)} $_selectedYear';

    // Build work order name map for references
    final woNames = <String, String>{};
    for (final wo in _workOrders) {
      woNames[wo['id'] as String] = wo['title'] as String? ?? '';
    }

    final buf = StringBuffer();

    // CSV Header
    buf.writeln('รายงานค่าใช้จ่ายรายเดือน - $monthLabel');
    buf.writeln('');
    buf.writeln(
      'บ้าน,รายการ,ประเภท,ประเภทค่าใช้จ่าย,รับผิดชอบโดย,อ้างอิง,วันที่,จำนวนเงิน (บาท)',
    );

    for (final entry in _expensesByProperty.entries) {
      final propName = _getPropertyName(entry.key);
      for (final e in entry.value) {
        final desc = e.isNoExpense
            ? 'ไม่มีค่าใช้จ่าย'
            : (e.description ?? _categoryLabel(e.category));
        final cat = e.isNoExpense ? 'ไม่มีค่าใช้จ่าย' : _categoryLabel(e.category);
        final costTypeLabel = e.costType.displayName;
        final paidByLabel = e.paidBy.displayName;
        final ref = e.workOrderId != null
            ? (woNames[e.workOrderId] ?? e.workOrderId ?? '')
            : (e.pmScheduleId ?? '');
        final date =
            '${e.expenseDate.day}/${e.expenseDate.month}/${e.expenseDate.year}';
        buf.writeln(
          '"$propName","$desc","$cat","$costTypeLabel","$paidByLabel","$ref","$date",${e.amount.toStringAsFixed(2)}',
        );
      }
    }

    buf.writeln('');
    buf.writeln(
      '"รวมทั้งเดือน","","","","","","",${_grandTotal.toStringAsFixed(2)}',
    );

    // Summary by property
    buf.writeln('');
    buf.writeln('สรุปตามบ้าน');
    buf.writeln('บ้าน,จำนวนรายการ,รวมเงิน (บาท)');
    for (final entry in _expensesByProperty.entries) {
      final propName = _getPropertyName(entry.key);
      final total = _totalByProperty[entry.key] ?? 0;
      buf.writeln(
        '"$propName",${entry.value.length},${total.toStringAsFixed(2)}',
      );
    }

    // Summary by paid_by
    buf.writeln('');
    buf.writeln('สรุปตามผู้รับผิดชอบ');
    buf.writeln('รับผิดชอบโดย,จำนวนรายการ,รวมเงิน (บาท)');
    final filtered = _allExpenses.where((e) {
      return e.expenseDate.year == _selectedYear &&
          e.expenseDate.month == _selectedMonth;
    }).toList();
    final paidByGroups = <String, List<Expense>>{};
    for (final e in filtered) {
      paidByGroups.putIfAbsent(e.paidBy.displayName, () => []).add(e);
    }
    for (final entry in paidByGroups.entries) {
      final total = entry.value.fold<double>(0, (s, e) => s + e.amount);
      buf.writeln(
        '"${entry.key}",${entry.value.length},${total.toStringAsFixed(2)}',
      );
    }

    final csvText = buf.toString();

    // Download as CSV file
    final fileName =
        'รายงานค่าใช้จ่าย_${_monthName(_selectedMonth)}_$_selectedYear.csv';
    try {
      downloadCsvFile(csvText, fileName);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('ดาวน์โหลด $fileName สำเร็จ')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ไม่สามารถดาวน์โหลดไฟล์ได้: ${friendlyError(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('ค่าใช้จ่าย'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Export รายงาน',
            onPressed: _exportReport,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Month selector
                _buildMonthSelector(theme),

                // Category filter chips
                if (_categories.isNotEmpty) _buildCategoryFilter(theme),

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
                          child: PageWrapper(
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 80),
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
                ),
              ],
            ),
      floatingActionButton: _authState.currentRole.canManageExpenses
          ? FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/expenses/new');
                _loadData();
              },
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มค่าใช้จ่าย'),
            )
          : null,
    );
  }

  Future<void> _deleteExpense(Expense e) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบรายการค่าใช้จ่าย'),
        content: Text(
          'ต้องการลบ "${e.isNoExpense ? 'ไม่มีค่าใช้จ่าย' : (e.description ?? _categoryLabel(e.category))}" '
          '(${_formatAmount(e.amount)}) ใช่หรือไม่?\n\nไม่สามารถกู้คืนได้',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.deleteExpense(e.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ลบรายการเรียบร้อย')),
        );
        _loadData();
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ลบไม่สำเร็จ: $err')),
        );
      }
    }
  }

  Widget _buildCategoryFilter(ThemeData theme) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        children: [
          // "ทั้งหมด" chip
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: const Text('ทั้งหมด'),
              selected: _selectedCategoryPrefix == null,
              onSelected: (_) {
                setState(() => _selectedCategoryPrefix = null);
                _computeReport();
              },
            ),
          ),
          // Category chips
          ..._categories.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(entry.value),
                selected: _selectedCategoryPrefix == entry.key,
                onSelected: (_) {
                  setState(() {
                    _selectedCategoryPrefix =
                        _selectedCategoryPrefix == entry.key ? null : entry.key;
                  });
                  _computeReport();
                },
              ),
            );
          }),
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
      if (e.isNoExpense) continue;
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
              onTap: e.workOrderId != null || e.purchaseOrderId != null
                  ? () {
                      if (e.workOrderId != null) {
                        context.push('/work-orders/${e.workOrderId}');
                      } else if (e.purchaseOrderId != null) {
                        context.push('/purchase-orders/${e.purchaseOrderId}');
                      }
                    }
                  : null,
              leading: Icon(
                e.isNoExpense ? Icons.verified_outlined : _categoryIcon(e.category),
                size: 20,
                color: e.isNoExpense ? Colors.green : theme.colorScheme.outline,
              ),
              title: Text(
                _getExpenseDisplayTitle(e),
                style: theme.textTheme.bodyMedium,
              ),
              subtitle: Text(
                () {
                  final ref = _getExpenseDisplayDetail(e);
                  final sourceLabel =
                      e.purchaseOrderId != null ? 'คำสั่งซื้อ' : e.costType.displayName;
                  final creator = e.createdByName != null
                      ? ' • บันทึกโดย ${e.createdByName}'
                      : '';
                  return '$ref • ${formatThaiDate(e.expenseDate)}'
                      ' • $sourceLabel'
                      ' • ${e.paidBy.displayName}'
                      '$creator';
                }(),
                style: theme.textTheme.bodySmall,
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        e.isNoExpense ? 'ไม่มีค่าใช้จ่าย' : _formatAmount(e.amount),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: e.isNoExpense ? Colors.green : null,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: e.paidBy == ExpensePaidBy.company
                              ? Colors.blue.withValues(alpha: 0.1)
                              : Colors.orange.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          e.paidBy.displayName,
                          style: TextStyle(
                            fontSize: 10,
                            color: e.paidBy == ExpensePaidBy.company
                                ? Colors.blue
                                : Colors.orange,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_authState.currentRole.isSuperAdmin) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                      tooltip: 'ลบรายการ',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () => _deleteExpense(e),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
