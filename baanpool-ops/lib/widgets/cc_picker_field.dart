import 'package:flutter/material.dart';

/// ช่องเลือก CC (ผู้รับสำเนาแจ้งเตือน) — ใช้ร่วมกันระหว่างฟอร์ม PM หลายหน้า
///
/// [selected] ถูกแก้ไขในที่ (mutable set) แล้วเรียก [onChanged]
/// ให้หน้าจอที่เรียกใช้ setState เอง
class CcPickerField extends StatelessWidget {
  /// รายชื่อผู้ใช้ทั้งหมดที่เลือกได้ (map จากตาราง users)
  final List<Map<String, dynamic>> allUsers;

  /// id ที่ถูกเลือกอยู่ — แก้ไขในที่
  final Set<String> selected;

  /// ไม่ต้องแสดงคนนี้ (ปกติคือผู้รับผิดชอบ จะได้ไม่แจ้งซ้ำ)
  final String? excludeUserId;

  final VoidCallback onChanged;

  const CcPickerField({
    super.key,
    required this.allUsers,
    required this.selected,
    required this.onChanged,
    this.excludeUserId,
  });

  static String roleLabel(String? role) {
    switch (role) {
      case 'admin':
        return 'ผู้ดูแลระบบ';
      case 'owner':
        return 'เจ้าของ';
      case 'manager':
        return 'ผู้จัดการ';
      case 'caretaker':
        return 'ผู้ดูแลบ้าน';
      case 'technician':
        return 'ช่าง';
      default:
        return '-';
    }
  }

  String _nameOf(String id) {
    final u = allUsers.firstWhere(
      (e) => e['id'] == id,
      orElse: () => <String, dynamic>{},
    );
    return u['full_name'] as String? ?? u['email'] as String? ?? '-';
  }

  Future<void> _openPicker(BuildContext context) async {
    final temp = Set<String>.from(selected);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('เพิ่ม CC (แจ้งสำเนา)'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'ผู้รับสำเนาจะได้แจ้งเตือน (LINE + ในแอป) '
                    'ทุกครั้งที่ PM นี้สร้างใบงาน',
                    style: TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final u in allUsers)
                        if (u['id'] != excludeUserId)
                          CheckboxListTile(
                            dense: true,
                            title: Text(
                              u['full_name'] as String? ??
                                  u['email'] as String? ??
                                  '-',
                            ),
                            subtitle: Text(roleLabel(u['role'] as String?)),
                            value: temp.contains(u['id']),
                            onChanged: (checked) => setDialogState(() {
                              if (checked == true) {
                                temp.add(u['id'] as String);
                              } else {
                                temp.remove(u['id']);
                              }
                            }),
                          ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('ตกลง'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true) {
      selected
        ..clear()
        ..addAll(temp);
      if (excludeUserId != null) selected.remove(excludeUserId);
      onChanged();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.people_outline, size: 16, color: theme.colorScheme.outline),
            const SizedBox(width: 6),
            Text(
              'CC (แจ้งสำเนา)',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _openPicker(context),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('เพิ่ม CC'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        if (selected.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: selected
                .map(
                  (id) => Chip(
                    label: Text(
                      _nameOf(id),
                      style: const TextStyle(fontSize: 12),
                    ),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onDeleted: () {
                      selected.remove(id);
                      onChanged();
                    },
                  ),
                )
                .toList(),
          ),
      ],
    );
  }
}
