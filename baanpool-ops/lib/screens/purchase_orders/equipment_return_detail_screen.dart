import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/equipment_return.dart';
import '../../models/user.dart';
import '../../services/supabase_service.dart';
import '../../services/auth_state_service.dart';
import '../../utils/thai_datetime.dart';
import '../../utils/error_message.dart';

/// รายละเอียดการแจ้งคืนของ / ของมีปัญหา + ปุ่มเปลี่ยนสถานะ
class EquipmentReturnDetailScreen extends StatefulWidget {
  final String returnId;
  const EquipmentReturnDetailScreen({super.key, required this.returnId});

  @override
  State<EquipmentReturnDetailScreen> createState() =>
      _EquipmentReturnDetailScreenState();
}

class _EquipmentReturnDetailScreenState
    extends State<EquipmentReturnDetailScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  final _authState = AuthStateService();

  EquipmentReturn? _ret;
  bool _loading = true;
  bool _actionLoading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _service.getEquipmentReturn(widget.returnId);
      if (mounted) {
        setState(() {
          _ret = EquipmentReturn.fromJson(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('โหลดล้มเหลว: ${friendlyError(e)}')));
        setState(() => _loading = false);
      }
    }
  }

  void _popWith(String message) {
    if (!mounted) return;
    if (context.canPop()) {
      context.pop(message);
    } else {
      context.go('/purchase-orders');
    }
  }

  Future<void> _setStatus(String status, String message,
      {String? resolutionNote}) async {
    setState(() => _actionLoading = true);
    try {
      final now = DateTime.now();
      final uid = Supabase.instance.client.auth.currentUser?.id;
      await _service.updateEquipmentReturn(widget.returnId, {
        'status': status,
        if (status == 'resolved') 'resolved_by': uid,
        if (status == 'resolved') 'resolved_at': now.toIso8601String(),
        if (resolutionNote != null && resolutionNote.isNotEmpty)
          'resolution_note': resolutionNote,
        'updated_at': now.toIso8601String(),
      });
      _popWith(message);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('อัพเดตล้มเหลว: ${friendlyError(e)}')));
        setState(() => _actionLoading = false);
      }
    }
  }

  Future<void> _resolve() async {
    final noteCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('จบเรื่อง — สรุปผล'),
        content: TextField(
          controller: noteCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'ผลการดำเนินการ',
            hintText: 'เช่น คืนของแล้ว / เปลี่ยนตัวใหม่ / ได้เงินคืน',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('จบเรื่อง'),
          ),
        ],
      ),
    );
    final note = noteCtrl.text.trim();
    noteCtrl.dispose();
    if (ok != true) return;
    await _setStatus('resolved', 'จบเรื่องเรียบร้อยแล้ว', resolutionNote: note);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบรายการแจ้งคืน'),
        content: const Text('ต้องการลบรายการนี้ใช่หรือไม่? ไม่สามารถกู้คืนได้'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _actionLoading = true);
    try {
      await _service.deleteEquipmentReturn(widget.returnId);
      _popWith('ลบรายการแล้ว');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('ลบล้มเหลว: ${friendlyError(e)}')));
        setState(() => _actionLoading = false);
      }
    }
  }

  void _showFullImage(String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: const Text('รูป'),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final role = _authState.currentRole;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isManagerUp = role == UserRole.admin ||
        role == UserRole.owner ||
        role == UserRole.manager;
    final canManage =
        isManagerUp || (_ret != null && _ret!.createdBy == currentUserId);

    return Scaffold(
      appBar: AppBar(
        title: const Text('คืนของ / ของมีปัญหา'),
        actions: [
          if (isManagerUp && _ret != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'ลบ',
              onPressed: _actionLoading ? null : _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _ret == null
              ? const Center(child: Text('ไม่พบข้อมูล'))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      _ret!.poTitle ?? 'PO',
                                      style: theme.textTheme.titleLarge
                                          ?.copyWith(
                                              fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  _ReturnStatusChip(_ret!.status),
                                ],
                              ),
                              const SizedBox(height: 12),
                              _row(theme, Icons.inventory_2_outlined, 'อุปกรณ์',
                                  _ret!.itemName?.isNotEmpty == true
                                      ? '${_ret!.itemName}  ×${_ret!.qty}'
                                      : 'ทั้งรายการ  ×${_ret!.qty}'),
                              const SizedBox(height: 6),
                              _row(theme, Icons.report_problem_outlined,
                                  'ชนิดปัญหา', _ret!.problemType.displayName),
                              const SizedBox(height: 6),
                              _row(theme, Icons.person_outline, 'แจ้งโดย',
                                  '${_ret!.createdByName ?? 'ไม่ทราบ'}  •  ${formatThaiDate(_ret!.createdAt)}'),
                              if (_ret!.resolvedAt != null) ...[
                                const SizedBox(height: 6),
                                _row(theme, Icons.check_circle_outline,
                                    'จบเรื่องโดย',
                                    '${_ret!.resolvedByName ?? 'ไม่ทราบ'}  •  ${formatThaiDate(_ret!.resolvedAt!)}',
                                    color: Colors.green.shade700),
                              ],
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // รายละเอียดปัญหา
                      Text('รายละเอียดปัญหา',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(_ret!.reason),
                        ),
                      ),

                      // ผลการดำเนินการ
                      if (_ret!.resolutionNote != null &&
                          _ret!.resolutionNote!.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('ผลการดำเนินการ',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Card(
                          color: Colors.green.shade50,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(_ret!.resolutionNote!),
                          ),
                        ),
                      ],

                      // รูป
                      if (_ret!.imageUrls.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text('รูปประกอบ',
                            style: theme.textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 150,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: _ret!.imageUrls
                                .map((url) => Padding(
                                      padding:
                                          const EdgeInsets.only(right: 8),
                                      child: GestureDetector(
                                        onTap: () => _showFullImage(url),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: Image.network(
                                            url,
                                            width: 150,
                                            height: 150,
                                            fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) =>
                                                const SizedBox(
                                                    width: 150,
                                                    height: 150,
                                                    child: Center(
                                                        child: Icon(Icons
                                                            .broken_image))),
                                          ),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // ─── ปุ่มดำเนินการ ───
                      if (_actionLoading)
                        const Center(child: CircularProgressIndicator())
                      else if (canManage) ...[
                        if (_ret!.status == ReturnStatus.pending) ...[
                          Row(children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _setStatus(
                                    'processing', 'รับเรื่องแล้ว'),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('รับเรื่อง'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _setStatus('cancelled', 'ยกเลิกแล้ว'),
                                icon: const Icon(Icons.close),
                                label: const Text('ยกเลิก'),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red),
                              ),
                            ),
                          ]),
                        ],
                        if (_ret!.status == ReturnStatus.processing) ...[
                          Row(children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _resolve,
                                icon: const Icon(Icons.check),
                                label: const Text('จบเรื่อง'),
                                style: FilledButton.styleFrom(
                                    backgroundColor: Colors.green),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () =>
                                    _setStatus('cancelled', 'ยกเลิกแล้ว'),
                                icon: const Icon(Icons.close),
                                label: const Text('ยกเลิก'),
                                style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.red),
                              ),
                            ),
                          ]),
                        ],
                      ],
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
    );
  }

  Widget _row(ThemeData theme, IconData icon, String label, String value,
      {Color? color}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: color ?? Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: theme.textTheme.bodyMedium,
              children: [
                TextSpan(
                    text: '$label: ',
                    style: TextStyle(
                        color: color ?? theme.colorScheme.outline,
                        fontWeight: FontWeight.w600)),
                TextSpan(
                    text: value,
                    style: TextStyle(color: theme.colorScheme.onSurface)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReturnStatusChip extends StatelessWidget {
  final ReturnStatus status;
  const _ReturnStatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = _color(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(status.displayName,
          style: TextStyle(color: color, fontSize: 12)),
    );
  }

  Color _color(ReturnStatus s) {
    switch (s) {
      case ReturnStatus.pending:
        return Colors.orange;
      case ReturnStatus.processing:
        return Colors.indigo;
      case ReturnStatus.resolved:
        return Colors.green;
      case ReturnStatus.cancelled:
        return Colors.grey;
    }
  }
}
