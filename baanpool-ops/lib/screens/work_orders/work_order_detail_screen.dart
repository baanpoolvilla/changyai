import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user.dart';
import '../../models/work_order.dart';
import '../../services/auth_state_service.dart';
import '../../services/supabase_service.dart';

class WorkOrderDetailScreen extends StatefulWidget {
  final String workOrderId;

  const WorkOrderDetailScreen({super.key, required this.workOrderId});

  @override
  State<WorkOrderDetailScreen> createState() => _WorkOrderDetailScreenState();
}

class _WorkOrderDetailScreenState extends State<WorkOrderDetailScreen> {
  final _service = SupabaseService(Supabase.instance.client);
  final _authState = AuthStateService();
  WorkOrder? _workOrder;
  String? _propertyName;
  String? _technicianName;
  bool _loading = true;
  bool _hasExpense = false;

  // For completion photo
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _completionImages = [];
  final List<Uint8List> _completionImageBytes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final woData = await _service.getWorkOrder(widget.workOrderId);
      _workOrder = WorkOrder.fromJson(woData);

      // Load property, technician, and expense check in parallel
      final futures = <Future>[
        _service
            .getProperty(_workOrder!.propertyId)
            .then((prop) {
              _propertyName = prop['name'] as String?;
            })
            .catchError((_) {}),
        _service
            .getExpenses(workOrderId: widget.workOrderId)
            .then((expenses) {
              _hasExpense = expenses.isNotEmpty;
            })
            .catchError((_) {
              _hasExpense = false;
            }),
      ];

      if (_workOrder!.assignedTo != null) {
        futures.add(
          _service
              .getUser(_workOrder!.assignedTo!)
              .then((user) {
                _technicianName = user?['full_name'] as String?;
              })
              .catchError((_) {}),
        );
      }

      await Future.wait(futures);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('โหลดข้อมูลล้มเหลว: $e')));
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _updateStatus(String newStatus) async {
    try {
      if (newStatus == 'completed') {
        // Also set completed_at when admin changes status to completed
        await _service.updateWorkOrder(widget.workOrderId, {
          'status': 'completed',
          'completed_at': DateTime.now().toIso8601String(),
        });
        // Update PM schedule if linked to an asset
        if (_workOrder?.assetId != null) {
          await _service.completePmSchedulesForAsset(_workOrder!.assetId!);
        }
      } else {
        await _service.updateWorkOrderStatus(widget.workOrderId, newStatus);
      }

      // LINE notification is sent automatically via database trigger

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('อัปเดตสถานะสำเร็จ'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('อัปเดตล้มเหลว: $e')));
      }
    }
  }

  void _showStatusDialog() {
    if (_workOrder == null) return;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('เปลี่ยนสถานะ'),
        children: [
          for (final status in WorkOrderStatus.values)
            SimpleDialogOption(
              onPressed: () {
                Navigator.pop(ctx);
                final value = status == WorkOrderStatus.inProgress
                    ? 'in_progress'
                    : status.name;
                _updateStatus(value);
              },
              child: Row(
                children: [
                  Icon(_statusIcon(status), color: _statusColor(status)),
                  const SizedBox(width: 12),
                  Text(
                    status.displayName,
                    style: TextStyle(
                      fontWeight: _workOrder!.status == status
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                  if (_workOrder!.status == status) ...[
                    const Spacer(),
                    const Icon(Icons.check, size: 18),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Show dialog requiring photo before marking work order as completed
  void _showCompletionDialog() {
    // Reset completion images
    _completionImages.clear();
    _completionImageBytes.clear();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('ยืนยันทำเสร็จแล้ว'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'กรุณาแนบรูปถ่ายก่อนกดยืนยัน',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),

                // Preview picked images
                if (_completionImageBytes.isNotEmpty) ...[
                  SizedBox(
                    height: 100,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _completionImageBytes.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _completionImageBytes[index],
                                width: 100,
                                height: 100,
                                fit: BoxFit.cover,
                              ),
                            ),
                            Positioned(
                              top: 2,
                              right: 2,
                              child: GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    _completionImages.removeAt(index);
                                    _completionImageBytes.removeAt(index);
                                  });
                                },
                                child: Container(
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  padding: const EdgeInsets.all(4),
                                  child: const Icon(
                                    Icons.close,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // Pick image button
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final images = await _picker.pickMultiImage(
                        imageQuality: 70,
                      );
                      if (images.isEmpty) return;
                      for (final img in images) {
                        final bytes = await img.readAsBytes();
                        setDialogState(() {
                          _completionImages.add(img);
                          _completionImageBytes.add(bytes);
                        });
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('เลือกรูปภาพล้มเหลว: $e')),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: Text(
                    _completionImageBytes.isEmpty
                        ? 'แนบรูปถ่าย *'
                        : 'เพิ่มรูป (${_completionImageBytes.length})',
                  ),
                ),

                if (_completionImageBytes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '* จำเป็นต้องแนบรูปถ่ายอย่างน้อย 1 รูป',
                      style: TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: _completionImageBytes.isEmpty
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _completeWithPhotos();
                    },
              child: const Text('ยืนยันเสร็จ'),
            ),
          ],
        ),
      ),
    );
  }

  /// Upload completion photos and mark as completed
  Future<void> _completeWithPhotos() async {
    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('กำลังอัปโหลดรูปภาพ...')));
      }

      // Upload images in parallel
      final photoUrls = <String>[..._workOrder?.photoUrls ?? []];
      final uploadFutures = <Future<String?>>[];
      for (int i = 0; i < _completionImageBytes.length; i++) {
        final bytes = _completionImageBytes[i];
        final ext = _completionImages[i].name.split('.').last;
        final path =
            'work-orders/complete_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        uploadFutures.add(
          _service
              .uploadFile('photos', path, bytes)
              .then<String?>((url) => url)
              .catchError((_) {
                debugPrint('Upload completion image $i failed');
                return null;
              }),
        );
      }
      final uploadResults = await Future.wait(uploadFutures);
      for (final url in uploadResults) {
        if (url != null) photoUrls.add(url);
      }

      // Update work order: status + photos
      await _service.updateWorkOrder(widget.workOrderId, {
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String(),
        'photo_urls': photoUrls,
      });

      // Update PM schedule if this work order is linked to an asset
      if (_workOrder?.assetId != null) {
        await _service.completePmSchedulesForAsset(_workOrder!.assetId!);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('อัปเดตสถานะเสร็จสมบูรณ์'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('อัปเดตล้มเหลว: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('รายละเอียดใบงาน')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_workOrder == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('รายละเอียดใบงาน')),
        body: const Center(child: Text('ไม่พบข้อมูลใบงาน')),
      );
    }

    final wo = _workOrder!;

    return Scaffold(
      appBar: AppBar(title: const Text('รายละเอียดใบงาน')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Title + Priority
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            wo.title,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        _priorityBadge(wo.priority),
                      ],
                    ),
                    const Divider(height: 24),

                    // Status
                    _infoRow(
                      Icons.info_outline,
                      'สถานะ',
                      wo.status.displayName,
                      valueColor: _statusColor(wo.status),
                    ),

                    // Property
                    if (_propertyName != null)
                      _infoRow(Icons.home, 'บ้าน', _propertyName!),

                    // Responsible person
                    if (_technicianName != null)
                      _infoRow(Icons.person, 'รับผิดชอบโดย', _technicianName!),

                    // Priority
                    _infoRow(
                      Icons.flag,
                      'ความเร่งด่วน',
                      wo.priority.displayName,
                    ),

                    // Created date
                    _infoRow(
                      Icons.calendar_today,
                      'สร้างเมื่อ',
                      '${wo.createdAt.day}/${wo.createdAt.month}/${wo.createdAt.year} ${wo.createdAt.hour.toString().padLeft(2, '0')}:${wo.createdAt.minute.toString().padLeft(2, '0')}',
                    ),

                    // Due date
                    if (wo.dueDate != null)
                      _infoRow(
                        Icons.event,
                        'กำหนดส่ง',
                        '${wo.dueDate!.day}/${wo.dueDate!.month}/${wo.dueDate!.year}',
                        valueColor: wo.isOverdue ? Colors.red : null,
                      ),

                    // Completed at
                    if (wo.completedAt != null)
                      _infoRow(
                        Icons.check_circle,
                        'เสร็จเมื่อ',
                        '${wo.completedAt!.day}/${wo.completedAt!.month}/${wo.completedAt!.year}',
                        valueColor: Colors.green,
                      ),
                  ],
                ),
              ),
            ),

            // Photos
            if (wo.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'รูปภาพ (${wo.photoUrls.length})',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 150,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: wo.photoUrls.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onTap: () =>
                                  _showFullImage(context, wo.photoUrls[index]),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  wo.photoUrls[index],
                                  width: 150,
                                  height: 150,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const SizedBox(
                                    width: 150,
                                    height: 150,
                                    child: Center(
                                      child: Icon(Icons.broken_image),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Description
            if (wo.description != null && wo.description!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('รายละเอียด', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text(wo.description!),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Expense button for completed work orders (hidden for technicians, hidden if expense already exists)
            if (wo.status == WorkOrderStatus.completed &&
                !_hasExpense &&
                AuthStateService().currentRole.canManageExpenses) ...[
              FilledButton.icon(
                onPressed: () async {
                  var url = '/expenses/new?workOrderId=${wo.id}';
                  // Auto-detect PM schedule for proper expense categorization
                  if (wo.assetId != null) {
                    final pmId = await _service.getPmScheduleIdForAsset(
                      wo.assetId!,
                    );
                    if (pmId != null) {
                      url += '&pmScheduleId=$pmId';
                    }
                  }
                  if (mounted) context.push(url);
                },
                icon: const Icon(Icons.receipt_long),
                label: const Text('เพิ่มค่าใช้จ่าย'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
              ),
              const SizedBox(height: 8),
            ],

            // Action buttons
            if (wo.status != WorkOrderStatus.completed &&
                wo.status != WorkOrderStatus.cancelled) ...[
              // เปลี่ยนสถานะ — Admin only
              if (_authState.currentRole == UserRole.admin)
                FilledButton.icon(
                  onPressed: _showStatusDialog,
                  icon: const Icon(Icons.edit),
                  label: const Text('เปลี่ยนสถานะ'),
                ),
              if (_authState.currentRole == UserRole.admin)
                const SizedBox(height: 8),
              if (wo.status == WorkOrderStatus.open)
                FilledButton.tonalIcon(
                  onPressed: () => _updateStatus('in_progress'),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('เริ่มดำเนินการ'),
                ),
              if (wo.status == WorkOrderStatus.inProgress)
                FilledButton.tonalIcon(
                  onPressed: _showCompletionDialog,
                  icon: const Icon(Icons.check),
                  label: const Text('ทำเสร็จแล้ว'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        child: Stack(
          children: [
            InteractiveViewer(child: Image.network(url, fit: BoxFit.contain)),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(backgroundColor: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey),
          const SizedBox(width: 12),
          SizedBox(
            width: 100,
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
                color: valueColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _priorityBadge(WorkOrderPriority priority) {
    Color color;
    String label;
    switch (priority) {
      case WorkOrderPriority.urgent:
        color = Colors.red;
        label = 'เร่งด่วน';
      case WorkOrderPriority.high:
        color = Colors.orange;
        label = 'สูง';
      case WorkOrderPriority.medium:
        color = Colors.blue;
        label = 'ปกติ';
      case WorkOrderPriority.low:
        color = Colors.grey;
        label = 'ต่ำ';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _statusColor(WorkOrderStatus status) {
    switch (status) {
      case WorkOrderStatus.open:
        return Colors.blue;
      case WorkOrderStatus.inProgress:
        return Colors.orange;
      case WorkOrderStatus.completed:
        return Colors.green;
      case WorkOrderStatus.cancelled:
        return Colors.grey;
    }
  }

  IconData _statusIcon(WorkOrderStatus status) {
    switch (status) {
      case WorkOrderStatus.open:
        return Icons.fiber_new;
      case WorkOrderStatus.inProgress:
        return Icons.autorenew;
      case WorkOrderStatus.completed:
        return Icons.check_circle;
      case WorkOrderStatus.cancelled:
        return Icons.cancel;
    }
  }
}
