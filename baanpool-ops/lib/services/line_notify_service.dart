import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// LINE Messaging API push notification service.
///
/// Supports:
/// - Notify technician when assigned a work order
/// - Notify caretaker & manager when PM schedule is due soon / overdue
/// - Notify caretaker & manager when work order status changes
class LineNotifyService {
  static final LineNotifyService _instance = LineNotifyService._();
  factory LineNotifyService() => _instance;
  LineNotifyService._();

  final _client = Supabase.instance.client;

  String get _token => dotenv.env['LINE_MESSAGING_TOKEN'] ?? '';
  bool get _enabled => _token.isNotEmpty;

  // ─── Core: Push message via LINE Messaging API ─────────

  /// Send a text push message to a LINE user.
  Future<bool> _push(String lineUserId, String message) async {
    if (!_enabled || lineUserId.isEmpty) {
      debugPrint(
        'LINE push skipped: enabled=$_enabled, lineUserId=$lineUserId',
      );
      return false;
    }
    try {
      final res = await http.post(
        Uri.parse('https://api.line.me/v2/bot/message/push'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'to': lineUserId,
          'messages': [
            {'type': 'text', 'text': message},
          ],
        }),
      );
      debugPrint('LINE push → ${res.statusCode} ${res.body}');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('LINE push error: $e');
      return false;
    }
  }

  /// Send a Flex Message (rich card) to a LINE user.
  Future<bool> _pushFlex(
    String lineUserId,
    String altText,
    Map<String, dynamic> flexContent,
  ) async {
    if (!_enabled || lineUserId.isEmpty) {
      debugPrint(
        'LINE flex push skipped: enabled=$_enabled, lineUserId=$lineUserId',
      );
      return false;
    }
    try {
      final res = await http.post(
        Uri.parse('https://api.line.me/v2/bot/message/push'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_token',
        },
        body: jsonEncode({
          'to': lineUserId,
          'messages': [
            {'type': 'flex', 'altText': altText, 'contents': flexContent},
          ],
        }),
      );
      debugPrint('LINE flex push → ${res.statusCode} ${res.body}');
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('LINE flex push error: $e');
      return false;
    }
  }

  // ─── Helper: resolve line_user_id from users table ─────

  Future<String?> _getLineUserId(String userId) async {
    try {
      final user = await _client
          .from('users')
          .select('line_user_id')
          .eq('id', userId)
          .maybeSingle();
      return user?['line_user_id'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Get all managers and admins (+ optional caretaker of property)
  Future<List<Map<String, dynamic>>> _getManagersAndAdmins() async {
    try {
      return await _client
          .from('users')
          .select('id, full_name, line_user_id, role')
          .inFilter('role', ['admin', 'owner', 'manager']);
    } catch (_) {
      return [];
    }
  }

  /// Get the caretaker for a property
  Future<Map<String, dynamic>?> _getPropertyCaretaker(String propertyId) async {
    try {
      final prop = await _client
          .from('properties')
          .select('caretaker_id')
          .eq('id', propertyId)
          .maybeSingle();
      if (prop == null || prop['caretaker_id'] == null) return null;
      return await _client
          .from('users')
          .select('id, full_name, line_user_id')
          .eq('id', prop['caretaker_id'] as String)
          .maybeSingle();
    } catch (_) {
      return null;
    }
  }

  // ─── 1. Notify technician: assigned a new work order ───

  /// Called when a work order is created or reassigned.
  /// Returns a result string describing what happened.
  Future<String> notifyTechnicianAssigned({
    required String technicianUserId,
    required String workOrderTitle,
    required String propertyName,
    String priority = 'medium',
  }) async {
    if (!_enabled) {
      debugPrint('LINE notify disabled: LINE_MESSAGING_TOKEN is empty');
      return 'LINE_TOKEN_MISSING';
    }

    final lineId = await _getLineUserId(technicianUserId);
    debugPrint(
      'LINE notify: technicianUserId=$technicianUserId → lineId=$lineId',
    );
    if (lineId == null || lineId.isEmpty) {
      return 'NO_LINE_ID';
    }

    final priorityEmoji = _priorityEmoji(priority);

    final ok = await _pushFlex(
      lineId,
      '📢 งานใหม่: $workOrderTitle',
      _workOrderCard(
        title: '📢 คุณได้รับมอบหมายงานใหม่!',
        workOrderTitle: workOrderTitle,
        propertyName: propertyName,
        priority: priority,
        priorityEmoji: priorityEmoji,
        color: '#1DB446',
      ),
    );
    return ok ? 'SENT' : 'SEND_FAILED';
  }

  // ─── 2. Notify technician + caretaker + managers: PM due soon ───────

  /// Called when PM schedule is due within 7 days or overdue.
  /// Notifies the assigned technician + property manager + all managers/admins.
  Future<void> notifyPmDueSoon({
    required String propertyId,
    required String propertyName,
    required String pmTitle,
    required String assetName,
    required DateTime nextDueDate,
    required int daysUntilDue,
    String? assignedTo,
    String? pmDescription,
    String? assetId,
  }) async {
    final isOverdue = daysUntilDue < 0;
    final isDueToday = daysUntilDue == 0;
    final statusText = isOverdue
        ? '⚠️ เกินกำหนด ${-daysUntilDue} วัน'
        : isDueToday
        ? '⏰ ถึงกำหนดวันนี้'
        : '⏰ อีก $daysUntilDue วัน';
    final dateStr =
        '${nextDueDate.day}/${nextDueDate.month}/${nextDueDate.year}';

    final message =
        '${isOverdue || isDueToday ? "🔴" : "🟡"} แจ้งเตือน PM\n'
        '📋 $pmTitle\n'
        '🏠 บ้าน: $propertyName\n'
        '🔧 อุปกรณ์: $assetName\n'
        '${pmDescription != null && pmDescription.isNotEmpty ? "📝 รายละเอียด: $pmDescription\n" : ""}'
        '📅 กำหนด: $dateStr\n'
        '$statusText\n'
        '${assetId != null ? "🔗 https://changyai.vercel.app/assets/$assetId" : ""}';

    // Collect recipients: technician + caretaker + managers/admins
    final recipients = <String>{};

    // Assigned technician
    if (assignedTo != null && assignedTo.isNotEmpty) {
      final techLineId = await _getLineUserId(assignedTo);
      if (techLineId != null && techLineId.isNotEmpty) {
        recipients.add(techLineId);
      }
    }

    // Property manager (caretaker of this property)
    final caretaker = await _getPropertyCaretaker(propertyId);
    if (caretaker != null) {
      final lid = caretaker['line_user_id'] as String?;
      if (lid != null && lid.isNotEmpty) recipients.add(lid);
    }

    // All managers/admins
    final managers = await _getManagersAndAdmins();
    for (final m in managers) {
      final lid = m['line_user_id'] as String?;
      if (lid != null && lid.isNotEmpty) recipients.add(lid);
    }

    // Send to all unique recipients
    for (final lineId in recipients) {
      await _push(lineId, message);
    }
  }

  // ─── 3. Notify caretaker + managers: work order status change ──

  /// Called when a work order status is updated (e.g. completed).
  Future<void> notifyWorkOrderStatusChanged({
    required String workOrderTitle,
    required String propertyId,
    required String propertyName,
    required String oldStatus,
    required String newStatus,
    String? technicianName,
  }) async {
    final emoji = _statusEmoji(newStatus);
    final statusText = _statusDisplayName(newStatus);

    final message =
        '$emoji ใบงานอัปเดตสถานะ\n'
        '📝 $workOrderTitle\n'
        '🏠 บ้าน: $propertyName\n'
        '📊 สถานะ: $statusText';

    final recipients = <String>{};

    // Caretaker
    final caretaker = await _getPropertyCaretaker(propertyId);
    if (caretaker != null) {
      final lid = caretaker['line_user_id'] as String?;
      if (lid != null && lid.isNotEmpty) recipients.add(lid);
    }

    // Managers/admins
    final managers = await _getManagersAndAdmins();
    for (final m in managers) {
      final lid = m['line_user_id'] as String?;
      if (lid != null && lid.isNotEmpty) recipients.add(lid);
    }

    for (final lineId in recipients) {
      await _push(lineId, message);
    }
  }

  // ─── 4. Batch check: send PM reminders for all due schedules ───

  /// Call this from the dashboard to check all PM schedules and
  /// send notifications for those due within 7 days or overdue.
  /// Delegates to SQL RPC check_pm_due_schedules() which handles both
  /// LINE (via app_settings token) and in-app notifications with dedup.
  /// Returns count of PM schedules processed.
  Future<int> checkAndNotifyPmDueSchedules() async {
    try {
      final result = await _client.rpc('check_pm_due_schedules');
      return (result as int?) ?? 0;
    } catch (e) {
      debugPrint('PM notification check error: $e');
      return 0;
    }
  }

  // ignore: unused_element
  Future<int> _checkAndNotifyPmDueSchedulesLegacy() async {
    int sent = 0;
    try {
      // Get PM schedules due within 7 days
      final weekFromNow = DateTime.now().add(const Duration(days: 7));

      List<Map<String, dynamic>> duePms;
      try {
        duePms = await _client
            .from('pm_schedules')
            .select('*, asset:asset_id(name, property_id)')
            .eq('is_active', true)
            .lte('next_due_date', weekFromNow.toIso8601String());
      } catch (_) {
        duePms = await _client
            .from('pm_schedules')
            .select()
            .eq('is_active', true)
            .lte('next_due_date', weekFromNow.toIso8601String());
      }

      if (duePms.isEmpty) return 0;

      // Load all properties for name lookup
      final properties = await _client
          .from('properties')
          .select('id, name, caretaker_id');
      final propNames = <String, String>{
        for (final p in properties) p['id'] as String: p['name'] as String,
      };
      final propCaretakers = <String, String?>{
        for (final p in properties)
          p['id'] as String: p['caretaker_id'] as String?,
      };

      // Load active work orders to skip PMs that already have one
      final activeWorkOrders = await _client
          .from('work_orders')
          .select('asset_id, title')
          .inFilter('status', ['open', 'in_progress']);
      final activeWoKeys = <String>{};
      for (final wo in activeWorkOrders) {
        final aid = wo['asset_id'] as String?;
        if (aid != null) activeWoKeys.add(aid);
      }

      for (final pm in duePms) {
        final nextDue = DateTime.parse(pm['next_due_date'] as String);
        final daysUntilDue = nextDue.difference(DateTime.now()).inDays;

        // Resolve asset & property info
        String assetName = 'ไม่ระบุ';
        String propertyId = pm['property_id'] as String;
        String? assignedTo = pm['assigned_to'] as String?;
        final assetId = pm['asset_id'] as String?;

        if (pm['asset'] is Map) {
          assetName = pm['asset']['name'] as String? ?? 'ไม่ระบุ';
        }

        // Skip if an active work order already exists for this asset
        if (assetId != null && activeWoKeys.contains(assetId)) {
          debugPrint('PM skip: active work order exists for asset $assetId');
          continue;
        }

        final propertyName = propNames[propertyId] ?? 'ไม่ทราบบ้าน';

        // Send LINE notifications only if LINE token is configured
        if (_enabled) {
          await notifyPmDueSoon(
            propertyId: propertyId,
            propertyName: propertyName,
            pmTitle: pm['title'] as String,
            assetName: assetName,
            nextDueDate: nextDue,
            daysUntilDue: daysUntilDue,
            assignedTo: assignedTo,
            pmDescription: pm['description'] as String?,
            assetId: assetId,
          );
        }

        // Always create in-app notifications (regardless of LINE token)
        await _createPmInAppNotifications(
          pmId: pm['id'] as String,
          pmTitle: pm['title'] as String,
          propertyId: propertyId,
          propertyName: propertyName,
          daysUntilDue: daysUntilDue,
          nextDueDate: nextDue,
          assignedTo: assignedTo,
          caretakerId: propCaretakers[propertyId],
        );

        sent++;
      }
    } catch (e) {
      debugPrint('PM notification check error: $e');
    }
    return sent;
  }

  // ─── 5. Create in-app notifications for PM ─────────────

  Future<void> _createPmInAppNotifications({
    required String pmId,
    required String pmTitle,
    required String propertyId,
    required String propertyName,
    required int daysUntilDue,
    required DateTime nextDueDate,
    String? assignedTo,
    String? caretakerId,
  }) async {
    final isOverdue = daysUntilDue < 0;
    final isDueToday = daysUntilDue == 0;
    final emoji = (isOverdue || isDueToday) ? '🔴' : '🟡';
    final statusText = isOverdue
        ? '⚠️ เกินกำหนด ${-daysUntilDue} วัน'
        : isDueToday
        ? '⏰ ถึงกำหนดวันนี้'
        : '⏰ อีก $daysUntilDue วัน';
    final dateStr =
        '${nextDueDate.day}/${nextDueDate.month}/${nextDueDate.year}';

    final title = '$emoji PM: $pmTitle';
    final body = '🏠 บ้าน: $propertyName\n📅 กำหนด: $dateStr\n$statusText';

    final recipientIds = <String>{};

    // Assigned technician
    if (assignedTo != null && assignedTo.isNotEmpty) {
      recipientIds.add(assignedTo);
    }

    // Property manager (caretaker)
    if (caretakerId != null && caretakerId.isNotEmpty) {
      recipientIds.add(caretakerId);
    }

    // All admin/owner/manager users
    final managers = await _getManagersAndAdmins();
    for (final m in managers) {
      recipientIds.add(m['id'] as String);
    }

    // Dedup key: today's date in UTC for checking existing notifications
    final now = DateTime.now().toUtc();
    final todayStart =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}T00:00:00.000Z';

    // Insert in-app notifications for all unique recipients (skip if already sent today)
    for (final userId in recipientIds) {
      try {
        // Dedup: skip if this PM was already notified to this user today
        final existing = await _client
            .from('notifications')
            .select('id')
            .eq('user_id', userId)
            .eq('reference_id', pmId)
            .eq('type', 'pm')
            .gte('created_at', todayStart)
            .limit(1)
            .maybeSingle();

        if (existing != null) {
          debugPrint(
            'PM dedup: notification already exists for user $userId, pm $pmId today',
          );
          continue;
        }

        await _client.from('notifications').insert({
          'user_id': userId,
          'title': title,
          'body': body,
          'type': 'pm',
          'reference_id': pmId,
        });
      } catch (e) {
        debugPrint('Insert PM notification error for $userId: $e');
      }
    }
  }

  // ─── 6. Expense reminder: completed work orders without expenses ──

  /// Check for completed work orders that have no expense records.
  /// Sends a LINE notification to managers/admins/caretakers reminding them.
  /// Intended to be called daily at 17:00 or from the dashboard.
  /// Returns count of reminders sent.
  Future<int> checkAndNotifyMissingExpenses() async {
    if (!_enabled) return 0;

    int sent = 0;
    try {
      // Get all completed work orders
      final completedWos = await _client
          .from('work_orders')
          .select('id, title, property_id')
          .eq('status', 'completed');

      if (completedWos.isEmpty) return 0;

      // Get all expense records grouped by work_order_id
      final expenses = await _client
          .from('expenses')
          .select('work_order_id')
          .not('work_order_id', 'is', null);

      final woIdsWithExpenses = <String>{
        for (final e in expenses)
          if (e['work_order_id'] != null) e['work_order_id'] as String,
      };

      // Filter completed work orders that have NO expenses
      final missingExpenseWos = completedWos
          .where((wo) => !woIdsWithExpenses.contains(wo['id'] as String))
          .toList();

      if (missingExpenseWos.isEmpty) return 0;

      // Load property names
      final properties = await _client.from('properties').select('id, name');
      final propNames = <String, String>{
        for (final p in properties) p['id'] as String: p['name'] as String,
      };

      // Collect all manager/admin LINE IDs
      final managers = await _getManagersAndAdmins();
      final managerLineIds = <String>{};
      for (final m in managers) {
        final lid = m['line_user_id'] as String?;
        if (lid != null && lid.isNotEmpty) managerLineIds.add(lid);
      }

      // Send one notification per missing-expense work order
      for (final wo in missingExpenseWos) {
        final woTitle = wo['title'] as String;
        final propertyId = wo['property_id'] as String;
        final propertyName = propNames[propertyId] ?? '-';

        final message =
            '⚠️ แจ้งเตือนยังไม่บันทึกค่าใช้จ่าย\n'
            '📝 $woTitle\n'
            '🏠 บ้าน: $propertyName';

        // Collect recipients: caretaker of property + managers/admins
        final recipients = <String>{...managerLineIds};

        final caretaker = await _getPropertyCaretaker(propertyId);
        if (caretaker != null) {
          final lid = caretaker['line_user_id'] as String?;
          if (lid != null && lid.isNotEmpty) recipients.add(lid);
        }

        for (final lineId in recipients) {
          await _push(lineId, message);
        }
        sent++;
      }
    } catch (e) {
      debugPrint('Missing expense notification check error: $e');
    }
    return sent;
  }

  // ─── Helpers ───────────────────────────────────────────

  String _priorityEmoji(String priority) {
    switch (priority) {
      case 'urgent':
        return '🔴';
      case 'high':
        return '🟠';
      case 'medium':
        return '🔵';
      case 'low':
        return '⚪';
      default:
        return '🔵';
    }
  }

  String _statusEmoji(String status) {
    switch (status) {
      case 'open':
        return '🆕';
      case 'in_progress':
        return '🔄';
      case 'completed':
        return '✅';
      case 'cancelled':
        return '❌';
      default:
        return '📋';
    }
  }

  String _statusDisplayName(String status) {
    switch (status) {
      case 'open':
        return 'เปิด';
      case 'in_progress':
        return 'กำลังดำเนินการ';
      case 'completed':
        return 'เสร็จแล้ว';
      case 'cancelled':
        return 'ยกเลิก';
      default:
        return status;
    }
  }

  /// Build a Flex Message card for work order assignment.
  Map<String, dynamic> _workOrderCard({
    required String title,
    required String workOrderTitle,
    required String propertyName,
    required String priority,
    required String priorityEmoji,
    required String color,
  }) {
    return {
      'type': 'bubble',
      'header': {
        'type': 'box',
        'layout': 'vertical',
        'backgroundColor': color,
        'contents': [
          {
            'type': 'text',
            'text': title,
            'color': '#FFFFFF',
            'weight': 'bold',
            'size': 'md',
          },
        ],
      },
      'body': {
        'type': 'box',
        'layout': 'vertical',
        'spacing': 'md',
        'contents': [
          {
            'type': 'text',
            'text': '📝 $workOrderTitle',
            'weight': 'bold',
            'size': 'lg',
            'wrap': true,
          },
          {'type': 'separator'},
          {
            'type': 'box',
            'layout': 'vertical',
            'spacing': 'sm',
            'contents': [
              _flexRow('🏠 บ้าน', propertyName),
              _flexRow('$priorityEmoji ความสำคัญ', _priorityLabel(priority)),
            ],
          },
        ],
      },
      'footer': {
        'type': 'box',
        'layout': 'vertical',
        'contents': [
          {
            'type': 'text',
            'text': 'เข้าดูรายละเอียดที่แอป ChangYai',
            'size': 'xs',
            'color': '#AAAAAA',
            'align': 'center',
          },
        ],
      },
    };
  }

  Map<String, dynamic> _flexRow(String label, String value) {
    return {
      'type': 'box',
      'layout': 'horizontal',
      'contents': [
        {
          'type': 'text',
          'text': label,
          'size': 'sm',
          'color': '#555555',
          'flex': 0,
        },
        {
          'type': 'text',
          'text': value,
          'size': 'sm',
          'color': '#111111',
          'align': 'end',
          'weight': 'bold',
        },
      ],
    };
  }

  String _priorityLabel(String priority) {
    switch (priority) {
      case 'urgent':
        return 'เร่งด่วน';
      case 'high':
        return 'สูง';
      case 'medium':
        return 'ปานกลาง';
      case 'low':
        return 'ต่ำ';
      default:
        return priority;
    }
  }
}
