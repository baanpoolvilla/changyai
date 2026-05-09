import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/user.dart';
import '../../models/work_order.dart';
import '../../models/work_order_comment.dart';
import '../../services/auth_state_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/thai_datetime.dart';

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
  String? _creatorName;
  bool _loading = true;
  bool _hasExpense = false;

  // Comments
  List<WorkOrderComment> _comments = [];
  final _commentController = TextEditingController();
  bool _addingComment = false;

  // For completion photo
  final ImagePicker _picker = ImagePicker();
  final List<XFile> _completionImages = [];
  final List<Uint8List> _completionImageBytes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final woData = await _service.getWorkOrder(widget.workOrderId);
      _workOrder = WorkOrder.fromJson(woData);

      // Load property, technician, creator, expense, and comments in parallel
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
        _service
            .getWorkOrderComments(widget.workOrderId)
            .then((data) {
              _comments = data
                  .map((e) => WorkOrderComment.fromJson(e))
                  .toList();
            })
            .catchError((_) {
              _comments = [];
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

      if (_workOrder!.createdBy != null) {
        futures.add(
          _service
              .getUser(_workOrder!.createdBy!)
              .then((user) {
                _creatorName = user?['full_name'] as String?;
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
    final completionNotesCtrl = TextEditingController();

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
                  'กรุณากรอกรายละเอียดและแนบรูปถ่ายก่อนกดยืนยัน',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),

                // Completion notes field
                TextField(
                  controller: completionNotesCtrl,
                  decoration: const InputDecoration(
                    labelText: 'รายละเอียดจบงาน *',
                    hintText: 'เช่น เปลี่ยนปั๊มน้ำแล้ว, ซ่อมไฟเสร็จ...',
                    prefixIcon: Icon(Icons.notes),
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  onChanged: (_) => setDialogState(() {}),
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
                        ? 'แนบรูปภาพหลังแก้ไข *'
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
              onPressed: (_completionImageBytes.isEmpty ||
                      completionNotesCtrl.text.trim().isEmpty)
                  ? null
                  : () async {
                      Navigator.pop(ctx);
                      await _completeWithPhotos(
                        notes: completionNotesCtrl.text.trim(),
                      );
                    },
              child: const Text('ยืนยันเสร็จ'),
            ),
          ],
        ),
      ),
    );
  }

  /// Upload completion photos to after_photo_urls and mark as completed
  Future<void> _completeWithPhotos({String? notes}) async {
    try {
      // Show loading
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('กำลังอัปโหลดรูปภาพ...')));
      }

      // Upload completion images → saved as after_photo_urls (separate from before photos)
      final afterPhotoUrls = <String>[];
      final uploadFutures = <Future<String?>>[];
      for (int i = 0; i < _completionImageBytes.length; i++) {
        final bytes = _completionImageBytes[i];
        final ext = _completionImages[i].name.split('.').last;
        final path =
            'work-orders/after_${DateTime.now().millisecondsSinceEpoch}_$i.$ext';
        uploadFutures.add(
          _service
              .uploadFile('photos', path, bytes)
              .then<String?>((url) => url)
              .catchError((_) {
                debugPrint('Upload after-photo $i failed');
                return null;
              }),
        );
      }
      final uploadResults = await Future.wait(uploadFutures);
      for (final url in uploadResults) {
        if (url != null) afterPhotoUrls.add(url);
      }

      // Update work order: status + after_photo_urls + completion notes
      // Note: photo_urls (before photos) remain untouched
      await _service.updateWorkOrder(widget.workOrderId, {
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String(),
        if (afterPhotoUrls.isNotEmpty) 'after_photo_urls': afterPhotoUrls,
        if (notes != null && notes.isNotEmpty) 'completion_notes': notes,
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

  Future<void> _addComment() async {
    final content = _commentController.text.trim();
    if (content.isEmpty) return;
    setState(() => _addingComment = true);
    try {
      await _service.addWorkOrderComment(widget.workOrderId, content);
      _commentController.clear();
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เพิ่มความคิดเห็นล้มเหลว: $e')),
        );
      }
    }
    if (mounted) setState(() => _addingComment = false);
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

                    // Created by
                    if (_creatorName != null)
                      _infoRow(
                        Icons.person_add_alt_1,
                        'สร้างโดย',
                        _creatorName!,
                      ),

                    // Responsible person
                    if (_technicianName != null)
                      _infoRow(Icons.engineering, 'รับผิดชอบโดย', _technicianName!),

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
                      formatThaiDateTime(wo.createdAt),
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

                    // Completion notes
                    if (wo.completionNotes != null && wo.completionNotes!.isNotEmpty)
                      _infoRow(
                        Icons.notes,
                        'รายละเอียดจบงาน',
                        wo.completionNotes!,
                      ),
                  ],
                ),
              ),
            ),

            // ─── ภาพก่อนแก้ไข ────────────────────────────────
            if (wo.photoUrls.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.photo_library_outlined,
                              size: 18, color: Colors.blueGrey),
                          const SizedBox(width: 8),
                          Text(
                            'ภาพก่อนแก้ไข (${wo.photoUrls.length})',
                            style: theme.textTheme.titleMedium,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 150,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: wo.photoUrls.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onTap: () => _showFullImage(
                                context,
                                wo.photoUrls[index],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  wo.photoUrls[index],
                                  width: 150,
                                  height: 150,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox(
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

            // ─── ภาพหลังแก้ไข ────────────────────────────────
            if (wo.afterPhotoUrls.isNotEmpty) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 18, color: Colors.green),
                          const SizedBox(width: 8),
                          Text(
                            'ภาพหลังแก้ไข (${wo.afterPhotoUrls.length})',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.green.shade700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 150,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: wo.afterPhotoUrls.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            return GestureDetector(
                              onTap: () => _showFullImage(
                                context,
                                wo.afterPhotoUrls[index],
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  wo.afterPhotoUrls[index],
                                  width: 150,
                                  height: 150,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox(
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

            // ─── Comment Section ─────────────────────────────
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.comment_outlined,
                            size: 18, color: Colors.blueGrey),
                        const SizedBox(width: 8),
                        Text(
                          'ความคิดเห็น (${_comments.length})',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // List of comments
                    if (_comments.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'ยังไม่มีความคิดเห็น',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    else
                      for (int i = 0; i < _comments.length; i++) ...[
                        _buildCommentItem(_comments[i]),
                        if (i < _comments.length - 1)
                          const Divider(height: 16),
                      ],

                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),

                    // Add comment input
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _commentController,
                            decoration: const InputDecoration(
                              hintText: 'เพิ่มความคิดเห็น...',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                            ),
                            maxLines: null,
                            minLines: 1,
                            textInputAction: TextInputAction.newline,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _addingComment
                            ? const SizedBox(
                                width: 40,
                                height: 40,
                                child: Center(
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2),
                                ),
                              )
                            : IconButton.filled(
                                onPressed: _addComment,
                                icon: const Icon(Icons.send),
                                tooltip: 'ส่งความคิดเห็น',
                              ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

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

            // ลบใบงาน — Super Admin only
            if (_authState.currentRole.isSuperAdmin) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showDeleteDialog,
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text('ลบใบงาน', style: TextStyle(color: Colors.red)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.red),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommentItem(WorkOrderComment comment) {
    final userName = comment.userName ?? 'ผู้ใช้';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_circle, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Text(
                userName,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                formatThaiDateTime(comment.createdAt),
                style: const TextStyle(color: Colors.grey, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 22),
            child: Text(comment.content, style: const TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog() {
    if (_workOrder == null) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบใบงาน'),
        content: Text(
          'ต้องการลบใบงาน "${_workOrder!.title}" หรือไม่?\n\nการดำเนินการนี้ไม่สามารถย้อนกลับได้',
        ),
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
                await _service.deleteWorkOrder(widget.workOrderId);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('ลบใบงานแล้ว'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  context.pop();
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('ลบไม่สำเร็จ: $e')),
                  );
                }
              }
            },
            child: const Text('ลบ'),
          ),
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context, String url) {    showDialog(
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
            width: 110,
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
