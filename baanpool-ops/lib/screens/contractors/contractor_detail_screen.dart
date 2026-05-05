import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/contractor.dart';
import '../../services/supabase_service.dart';

/// หน้ารายละเอียดช่างภายนอก + ประวัติงาน
class ContractorDetailScreen extends StatefulWidget {
  final String contractorId;

  const ContractorDetailScreen({super.key, required this.contractorId});

  @override
  State<ContractorDetailScreen> createState() => _ContractorDetailScreenState();
}

class _ContractorDetailScreenState extends State<ContractorDetailScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  Contractor? _contractor;
  List<ContractorHistory> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _service.getContractor(widget.contractorId),
        _service.getContractorHistory(widget.contractorId),
      ]);
      _contractor = Contractor.fromJson(results[0] as Map<String, dynamic>);
      _history = (results[1] as List<Map<String, dynamic>>)
          .map((e) => ContractorHistory.fromJson(e))
          .toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showAddHistoryDialog() {
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    int rating = 3;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('เพิ่มประวัติงาน'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'รายละเอียดงาน *',
                      prefixIcon: Icon(Icons.description),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'กรุณากรอกรายละเอียด' : null,
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'ค่าใช้จ่าย (บาท)',
                      prefixIcon: Icon(Icons.attach_money),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'หมายเหตุ',
                      prefixIcon: Icon(Icons.notes),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  // Rating
                  Row(
                    children: [
                      const Text('คะแนน: '),
                      ...List.generate(5, (i) {
                        return IconButton(
                          icon: Icon(
                            i < rating ? Icons.star : Icons.star_border,
                            color: Colors.amber,
                          ),
                          onPressed: () {
                            setDialogState(() => rating = i + 1);
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);

                try {
                  await _service.createContractorHistory({
                    'contractor_id': widget.contractorId,
                    'description': descCtrl.text.trim(),
                    'amount': amountCtrl.text.trim().isEmpty
                        ? null
                        : double.parse(amountCtrl.text.trim()),
                    'notes': notesCtrl.text.trim().isEmpty
                        ? null
                        : notesCtrl.text.trim(),
                    'rating': rating,
                    'work_date': DateTime.now()
                        .toIso8601String()
                        .split('T')
                        .first,
                  });
                  _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('เพิ่มประวัติงานสำเร็จ'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
                    );
                  }
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  String _formatAmount(double amount) {
    final formatted = amount
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
    return '฿$formatted';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('รายละเอียด Contact')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_contractor == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('รายละเอียด Contact')),
        body: const Center(child: Text('ไม่พบข้อมูล')),
      );
    }

    final c = _contractor!;

    return Scaffold(
      appBar: AppBar(title: const Text('รายละเอียด Contact')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(c),
        icon: const Icon(Icons.edit),
        label: const Text('แก้ไขข้อมูล'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Contact info card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: theme.colorScheme.primaryContainer,
                          child: Icon(
                            Icons.engineering,
                            size: 32,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.name,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (c.specialty != null)
                                Text(
                                  c.specialty!,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        if (c.rating != null) _buildRating(c.rating!),
                      ],
                    ),
                    const Divider(height: 24),
                    if (c.phone != null)
                      _infoRow(
                        Icons.phone,
                        'เบอร์โทร',
                        c.phone!,
                        onTap: () => _callPhone(c.phone!),
                      ),
                    if (c.email != null)
                      _infoRow(
                        Icons.contact_page,
                        'ช่องทางติดต่ออื่นๆ',
                        c.email!,
                      ),
                    if (c.specialty != null)
                      _infoRow(Icons.stars_outlined, 'คุณสมบัติ', c.specialty!),
                    if (c.zone != null)
                      _infoRow(Icons.location_on_outlined, 'พื้นที่', c.zone!),
                    if (c.companyName != null)
                      _infoRow(Icons.business, 'บริษัท', c.companyName!),
                    if (c.notes != null)
                      _infoRow(Icons.notes, 'หมายเหตุ', c.notes!),
                    if (!c.isActive)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'ไม่ใช้งาน',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // History section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'ประวัติงาน (${_history.length})',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: _showAddHistoryDialog,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('เพิ่ม'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_history.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      'ยังไม่มีประวัติงาน',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ),
              )
            else
              ..._history.map((h) => _buildHistoryCard(h, theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryCard(ContractorHistory h, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    h.description ?? 'ไม่มีรายละเอียด',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (h.rating != null) _buildRating(h.rating!),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 4,
              children: [
                if (h.workDate != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '${h.workDate!.day}/${h.workDate!.month}/${h.workDate!.year}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                if (h.amount != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.attach_money,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatAmount(h.amount!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                if (h.propertyName != null)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.home,
                        size: 14,
                        color: theme.colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(h.propertyName!, style: theme.textTheme.bodySmall),
                    ],
                  ),
              ],
            ),
            if (h.notes != null && h.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                h.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    VoidCallback? onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            Icon(icon, size: 20, color: Colors.grey),
            const SizedBox(width: 12),
            SizedBox(
              width: 80,
              child: Text(
                label,
                style: const TextStyle(color: Colors.grey, fontSize: 14),
              ),
            ),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: onTap != null ? Colors.blue : null,
                  decoration: onTap != null ? TextDecoration.underline : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRating(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating ? Icons.star : Icons.star_border,
          size: 14,
          color: Colors.amber,
        );
      }),
    );
  }

  void _showEditDialog(Contractor contractor) {
    final nameCtrl = TextEditingController(text: contractor.name);
    final phoneCtrl = TextEditingController(text: contractor.phone ?? '');
    final emailCtrl = TextEditingController(text: contractor.email ?? '');
    final specialtyCtrl = TextEditingController(text: contractor.specialty ?? '');
    final companyCtrl = TextEditingController(text: contractor.companyName ?? '');
    final notesCtrl = TextEditingController(text: contractor.notes ?? '');
    String? selectedZone = contractor.zone;
    final formKey = GlobalKey<FormState>();
    const zoneOptions = ['ทั่วไป', 'บางแสน', 'พัทยา'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('แก้ไขข้อมูล Contact'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ชื่อ *',
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'กรุณากรอกชื่อ' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'เบอร์โทร',
                      prefixIcon: Icon(Icons.phone),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ช่องทางติดต่ออื่นๆ',
                      prefixIcon: Icon(Icons.contact_page),
                      hintText: 'เช่น LINE ID, Facebook',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: specialtyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'คุณสมบัติ',
                      prefixIcon: Icon(Icons.stars_outlined),
                      hintText: 'เช่น ไฟฟ้า, ประปา, แอร์, กฎหมาย',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedZone,
                    decoration: const InputDecoration(
                      labelText: 'พื้นที่ (Zone)',
                      prefixIcon: Icon(Icons.location_on_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('ไม่ระบุ'),
                      ),
                      ...zoneOptions.map((z) => DropdownMenuItem<String>(
                        value: z,
                        child: Text(z),
                      )),
                    ],
                    onChanged: (v) => setDialogState(() => selectedZone = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: companyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'บริษัท',
                      prefixIcon: Icon(Icons.business),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'หมายเหตุ',
                      prefixIcon: Icon(Icons.notes),
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(ctx);
                try {
                  await _service.updateContractor(contractor.id, {
                    'name': nameCtrl.text.trim(),
                    'phone': phoneCtrl.text.trim().isEmpty ? null : phoneCtrl.text.trim(),
                    'email': emailCtrl.text.trim().isEmpty ? null : emailCtrl.text.trim(),
                    'specialty': specialtyCtrl.text.trim().isEmpty ? null : specialtyCtrl.text.trim(),
                    'company_name': companyCtrl.text.trim().isEmpty ? null : companyCtrl.text.trim(),
                    'notes': notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
                    'zone': selectedZone,
                  });
                  _load();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('แก้ไขข้อมูลสำเร็จ'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
                    );
                  }
                }
              },
              child: const Text('บันทึก'),
            ),
          ],
        ),
      ),
    );
  }
}
