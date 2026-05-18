import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/contractor.dart';
import '../../services/supabase_service.dart';
import '../../utils/page_wrapper.dart';

/// รายชื่อติดต่อ (Contact)
class ContractorsListScreen extends StatefulWidget {
  const ContractorsListScreen({super.key});

  @override
  State<ContractorsListScreen> createState() => _ContractorsListScreenState();
}

const _kCategories = ['งานช่าง', 'งานทั่วไป', 'ร้านอาหาร', 'ไฟฟ้า/ประปา', 'อื่นๆ'];

class _ContractorsListScreenState extends State<ContractorsListScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  List<Contractor> _contractors = [];
  bool _loading = true;
  String? _selectedCategory; // null = ทั้งหมด

  List<Contractor> get _filtered {
    if (_selectedCategory == null) return _contractors;
    return _contractors.where((c) => c.category == _selectedCategory).toList();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getContractors();
      _contractors = data.map((e) => Contractor.fromJson(e)).toList();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showAddEditDialog({Contractor? contractor}) {
    final nameCtrl = TextEditingController(text: contractor?.name ?? '');
    final phoneCtrl = TextEditingController(text: contractor?.phone ?? '');
    final emailCtrl = TextEditingController(text: contractor?.email ?? '');
    final specialtyCtrl = TextEditingController(
      text: contractor?.specialty ?? '',
    );
    final priceCtrl = TextEditingController(
      text: contractor?.price != null ? contractor!.price!.toStringAsFixed(0) : '',
    );
    final companyCtrl = TextEditingController(
      text: contractor?.companyName ?? '',
    );
    final notesCtrl = TextEditingController(text: contractor?.notes ?? '');
    String? selectedZone = contractor?.zone;
    String? selectedCategory = contractor?.category;
    final formKey = GlobalKey<FormState>();
    const zoneOptions = ['ทั่วไป', 'บางแสน', 'พัทยา'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
        title: Text(contractor == null ? 'เพิ่ม Contact' : 'แก้ไขข้อมูล Contact'),
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
                TextFormField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'ราคา/ค่าบริการ *',
                    prefixIcon: Icon(Icons.attach_money),
                    hintText: 'ระบุราคาเป็นตัวเลข',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'กรุณาระบุราคา';
                    if (double.tryParse(v.trim()) == null) return 'ราคาต้องเป็นตัวเลข';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: selectedCategory,
                  decoration: const InputDecoration(
                    labelText: 'หมวดหมู่ *',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  validator: (v) => v == null ? 'กรุณาเลือกหมวดหมู่' : null,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('เลือกหมวดหมู่'),
                    ),
                    ..._kCategories.map((cat) => DropdownMenuItem<String?>(
                      value: cat,
                      child: Text(cat),
                    )),
                  ],
                  onChanged: (v) => setDialogState(() => selectedCategory = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  value: selectedZone,
                  decoration: const InputDecoration(
                    labelText: 'พื้นที่ (Zone)',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('ไม่ระบุ'),
                    ),
                    ...zoneOptions.map((z) => DropdownMenuItem<String?>(
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
                final data = {
                  'name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim().isEmpty
                      ? null
                      : phoneCtrl.text.trim(),
                  'email': emailCtrl.text.trim().isEmpty
                      ? null
                      : emailCtrl.text.trim(),
                  'specialty': specialtyCtrl.text.trim().isEmpty
                      ? null
                      : specialtyCtrl.text.trim(),
                  'company_name': companyCtrl.text.trim().isEmpty
                      ? null
                      : companyCtrl.text.trim(),
                  'notes': notesCtrl.text.trim().isEmpty
                      ? null
                      : notesCtrl.text.trim(),
                  'zone': selectedZone,
                  'price': double.tryParse(priceCtrl.text.trim()),
                  'category': selectedCategory,
                };

                if (contractor == null) {
                  await _service.createContractor(data);
                } else {
                  await _service.updateContractor(contractor.id, data);
                }

                _load();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        contractor == null
                            ? 'เพิ่ม Contact สำเร็จ'
                            : 'แก้ไขข้อมูลสำเร็จ',
                      ),
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

  void _showDeleteDialog(Contractor contractor) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบ Contact'),
        content: Text('ต้องการลบ "${contractor.name}" หรือไม่?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await _service.deleteContractor(contractor.id);
                _load();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('ลบ ${contractor.name} แล้ว'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('ลบไม่สำเร็จ: $e')));
                }
              }
            },
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('รายชื่อ Contact')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Category filter chips
                if (_contractors.isNotEmpty)
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: const Text('ทั้งหมด'),
                            selected: _selectedCategory == null,
                            onSelected: (_) {
                              setState(() => _selectedCategory = null);
                            },
                          ),
                        ),
                        ..._kCategories.map(
                          (cat) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(cat),
                              selected: _selectedCategory == cat,
                              onSelected: (_) {
                                setState(() {
                                  _selectedCategory =
                                      _selectedCategory == cat ? null : cat;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.contacts_outlined,
                                size: 64,
                                color: theme.colorScheme.outline,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                _selectedCategory != null
                                    ? 'ไม่มี Contact ในหมวด "$_selectedCategory"'
                                    : 'ยังไม่มีข้อมูล Contact',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              if (_selectedCategory == null) ...[
                                const SizedBox(height: 16),
                                FilledButton.icon(
                                  onPressed: () => _showAddEditDialog(),
                                  icon: const Icon(Icons.add),
                                  label: const Text('เพิ่ม Contact'),
                                ),
                              ],
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: PageWrapper(
                            child: ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: _filtered.length,
                              itemBuilder: (context, index) {
                                final c = _filtered[index];
                                return _buildContractorCard(c, theme);
                              },
                            ),
                          ),
                        ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('เพิ่ม Contact'),
      ),
    );
  }

  Widget _buildContractorCard(Contractor c, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          await context.push('/contractors/${c.id}');
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: theme.colorScheme.primaryContainer,
                    child: Icon(
                      Icons.engineering,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.name,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (c.specialty != null)
                          Text(
                            c.specialty!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        if (c.zone != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.location_on, size: 12, color: theme.colorScheme.outline),
                              const SizedBox(width: 2),
                              Text(
                                c.zone!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                  if (c.rating != null) _buildRating(c.rating!),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _showAddEditDialog(contractor: c);
                      if (v == 'delete') _showDeleteDialog(c);
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          leading: Icon(Icons.edit),
                          title: Text('แก้ไข'),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          leading: Icon(Icons.delete, color: Colors.red),
                          title: Text(
                            'ลบ',
                            style: TextStyle(color: Colors.red),
                          ),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (c.phone != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.phone,
                          size: 14,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(c.phone!, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  if (c.companyName != null)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.business,
                          size: 14,
                          color: theme.colorScheme.outline,
                        ),
                        const SizedBox(width: 4),
                        Text(c.companyName!, style: theme.textTheme.bodySmall),
                      ],
                    ),
                  if (!c.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'ไม่ใช้งาน',
                        style: TextStyle(color: Colors.red, fontSize: 11),
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

  Widget _buildRating(int rating) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        return Icon(
          i < rating ? Icons.star : Icons.star_border,
          size: 16,
          color: Colors.amber,
        );
      }),
    );
  }
}
