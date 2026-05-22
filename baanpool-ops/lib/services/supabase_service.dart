import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service layer for all Supabase operations
class SupabaseService {
  final SupabaseClient _client;

  SupabaseService(this._client);

  // ─── Auth ──────────────────────────────────────────────

  Future<AuthResponse> signIn(String email, String password) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  User? get currentUser => _client.auth.currentUser;

  // ─── Properties ────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getProperties() async {
    return await _client
        .from('properties')
        .select('*, caretaker:caretaker_id(full_name)')
        .order('name', ascending: true);
  }

  Future<Map<String, dynamic>> getProperty(String id) async {
    return await _client.from('properties').select().eq('id', id).single();
  }

  Future<void> createProperty(Map<String, dynamic> data) async {
    await _client.from('properties').insert(data);
  }

  Future<void> updateProperty(String id, Map<String, dynamic> data) async {
    await _client.from('properties').update(data).eq('id', id);
  }

  Future<void> deleteProperty(String id) async {
    await _client.from('properties').delete().eq('id', id);
  }

  // ─── Property Categories ────────────────────────────────

  /// Get all category display names
  Future<Map<String, String>> getPropertyCategories() async {
    try {
      final data = await _client
          .from('property_categories')
          .select()
          .order('prefix', ascending: true);
      return {
        for (final row in data)
          row['prefix'] as String: row['display_name'] as String,
      };
    } catch (_) {
      // Table might not exist yet
      return {};
    }
  }

  /// Upsert a category display name
  Future<void> upsertPropertyCategory(String prefix, String displayName) async {
    await _client.from('property_categories').upsert({
      'prefix': prefix,
      'display_name': displayName,
    });
  }

  // ─── Assets ────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAssets({String? propertyId}) async {
    var query = _client.from('assets').select();
    if (propertyId != null) query = query.eq('property_id', propertyId);
    return await query.order('name', ascending: true);
  }

  Future<Map<String, dynamic>> getAsset(String id) async {
    return await _client.from('assets').select().eq('id', id).single();
  }

  Future<void> createAsset(Map<String, dynamic> data) async {
    await _client.from('assets').insert(data);
  }

  Future<void> updateAsset(String id, Map<String, dynamic> data) async {
    await _client.from('assets').update(data).eq('id', id);
  }

  Future<void> deleteAsset(String id) async {
    await _client.from('assets').delete().eq('id', id);
  }

  // ─── Work Orders ──────────────────────────────────────

  Future<List<Map<String, dynamic>>> getWorkOrders({
    String? status,
    List<String>? statuses,
    String? propertyId,
    String? assignedTo,
    String? priority,
    bool? createdToday,
    bool? noExpense,
  }) async {
    var query = _client
        .from('work_orders')
        .select();
    if (status != null) query = query.eq('status', status);
    if (statuses != null) query = query.inFilter('status', statuses);
    if (propertyId != null) query = query.eq('property_id', propertyId);
    if (assignedTo != null) query = query.eq('assigned_to', assignedTo);
    if (priority != null) query = query.eq('priority', priority);
    if (createdToday == true) {
      final today = DateTime.now();
      final start = DateTime(today.year, today.month, today.day);
      final end = start.add(const Duration(days: 1));
      query = query
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String());
    }
    final data = await query.order('created_at', ascending: false);
    if (noExpense == true) {
      final withExpenses = await getWorkOrderIdsWithExpenses();
      return data
          .where((wo) =>
              wo['status'] == 'completed' &&
              !withExpenses.contains(wo['id'] as String))
          .toList();
    }
    return data;
  }

  Future<void> createWorkOrder(Map<String, dynamic> data) async {
    final userId = _client.auth.currentUser?.id;
    if (userId != null && !data.containsKey('created_by')) {
      data = {...data, 'created_by': userId};
    }
    try {
      await _client.from('work_orders').insert(data);
    } catch (e) {
      // Fallback: retry without created_by if column not yet in schema cache
      if (e.toString().contains('created_by') && data.containsKey('created_by')) {
        final fallback = Map<String, dynamic>.from(data)..remove('created_by');
        await _client.from('work_orders').insert(fallback);
      } else {
        rethrow;
      }
    }
  }

  Future<Map<String, dynamic>> getWorkOrder(String id) async {
    return await _client
        .from('work_orders')
        .select()
        .eq('id', id)
        .single();
  }

  Future<void> updateWorkOrderStatus(String id, String status) async {
    await _client.from('work_orders').update({'status': status}).eq('id', id);
  }

  Future<void> updateWorkOrder(String id, Map<String, dynamic> data) async {
    await _client.from('work_orders').update(data).eq('id', id);
  }

  /// Delete a work order — only Super Admin (admin role) should call this
  Future<void> deleteWorkOrder(String id) async {
    await _client.from('work_orders').delete().eq('id', id);
  }

  // ─── Expenses ─────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getExpenses({
    String? workOrderId,
    String? propertyId,
  }) async {
    var query = _client.from('expenses').select('*, creator:created_by(full_name)');
    if (workOrderId != null) query = query.eq('work_order_id', workOrderId);
    if (propertyId != null) query = query.eq('property_id', propertyId);
    return await query.order('expense_date', ascending: false);
  }

  Future<void> deleteExpense(String id) async {
    await _client.from('expenses').delete().eq('id', id);
  }

  Future<void> createExpense(Map<String, dynamic> data) async {
    final userId = _client.auth.currentUser?.id;
    final dataWithCreator = userId != null ? {...data, 'created_by': userId} : data;
    try {
      await _client.from('expenses').insert(dataWithCreator);
    } catch (e) {
      if (e.toString().contains('created_by')) {
        await _client.from('expenses').insert(data);
      } else {
        rethrow;
      }
    }
  }

  // ─── PM Schedules ─────────────────────────────────────

  Future<List<Map<String, dynamic>>> getPmSchedules({
    bool? dueSoon,
    String? assetId,
    String? assignedTo,
    String? propertyId,
  }) async {
    try {
      var query = _client
          .from('pm_schedules')
          .select(
            '*, users:assigned_to(full_name), creator:created_by(full_name), properties:property_id(name), assets:asset_id(name)',
          )
          .eq('is_active', true);
      if (assetId != null) query = query.eq('asset_id', assetId);
      if (assignedTo != null) query = query.eq('assigned_to', assignedTo);
      if (propertyId != null) query = query.eq('property_id', propertyId);
      if (dueSoon == true) {
        final weekFromNow = DateTime.now().add(const Duration(days: 7));
        query = query.lte('next_due_date', weekFromNow.toIso8601String());
      }
      return await query.order('next_due_date', ascending: true);
    } catch (_) {
      // Fallback: query without join (assigned_to column may not exist yet)
      var query = _client.from('pm_schedules').select().eq('is_active', true);
      if (assetId != null) query = query.eq('asset_id', assetId);
      if (propertyId != null) query = query.eq('property_id', propertyId);
      if (dueSoon == true) {
        final weekFromNow = DateTime.now().add(const Duration(days: 7));
        query = query.lte('next_due_date', weekFromNow.toIso8601String());
      }
      return await query.order('next_due_date', ascending: true);
    }
  }

  Future<void> createPmSchedule(Map<String, dynamic> data) async {
    final userId = _client.auth.currentUser?.id;
    final dataWithCreator = userId != null ? {...data, 'created_by': userId} : data;
    try {
      await _client.from('pm_schedules').insert(dataWithCreator);
    } catch (e) {
      if (e.toString().contains('created_by')) {
        await _client.from('pm_schedules').insert(data);
      } else {
        rethrow;
      }
    }
  }

  /// Create multiple PM schedules at once (batch insert)
  Future<void> createPmSchedulesBatch(
    List<Map<String, dynamic>> dataList,
  ) async {
    if (dataList.isEmpty) return;
    await _client.from('pm_schedules').insert(dataList);
  }

  Future<void> updatePmSchedule(String id, Map<String, dynamic> data) async {
    await _client.from('pm_schedules').update(data).eq('id', id);
  }

  Future<void> deletePmSchedule(String id) async {
    await _client.from('pm_schedules').delete().eq('id', id);
  }

  /// Complete PM schedules for an asset — update last_completed_date and advance next_due_date
  Future<void> completePmSchedulesForAsset(String assetId) async {
    try {
      final schedules = await _client
          .from('pm_schedules')
          .select()
          .eq('asset_id', assetId)
          .eq('is_active', true);

      final now = DateTime.now();
      for (final s in schedules) {
        final frequency = s['frequency'] as String? ?? 'monthly';
        final nextDue = _calcNextDueDate(now, frequency);
        await _client
            .from('pm_schedules')
            .update({
              'last_completed_date': now.toIso8601String(),
              'next_due_date': nextDue.toIso8601String(),
            })
            .eq('id', s['id'] as String);
      }
    } catch (_) {}
  }

  /// Calculate next due date based on PM frequency
  DateTime _calcNextDueDate(DateTime from, String frequency) {
    // Map DB values to internal enum-style names
    const legacyMap = {
      'weekly': 'week1',
      'biweekly': 'week2',
      'triweekly': 'week3',
      'monthly': 'month1',
      'bimonthly': 'month2',
      'quarterly': 'month3',
      'month4': 'month4',
      'month5': 'month5',
      'semiannual': 'month6',
      'month7': 'month7',
      'month8': 'month8',
      'month9': 'month9',
      'month10': 'month10',
      'month11': 'month11',
      'annual': 'month12',
    };
    final f = legacyMap[frequency] ?? frequency;
    if (f == 'week1') return from.add(const Duration(days: 7));
    if (f == 'week2') return from.add(const Duration(days: 14));
    if (f == 'week3') return from.add(const Duration(days: 21));
    final monthMatch = RegExp(r'^month(\d+)$').firstMatch(f);
    if (monthMatch != null) {
      final months = int.parse(monthMatch.group(1)!);
      return DateTime(from.year, from.month + months, from.day);
    }
    return DateTime(from.year, from.month + 1, from.day);
  }

  /// Find the PM schedule ID for an asset (first active schedule)
  Future<String?> getPmScheduleIdForAsset(String assetId) async {
    try {
      final data = await _client
          .from('pm_schedules')
          .select('id')
          .eq('asset_id', assetId)
          .eq('is_active', true)
          .limit(1);
      if (data.isNotEmpty) return data[0]['id'] as String;
    } catch (_) {}
    return null;
  }

  /// Get the last maintenance (completed PM) date for an asset
  Future<DateTime?> getLastMaintenanceDate(String assetId) async {
    try {
      final data = await _client
          .from('pm_schedules')
          .select('last_completed_date')
          .eq('asset_id', assetId)
          .not('last_completed_date', 'is', null)
          .order('last_completed_date', ascending: false)
          .limit(1);
      if (data.isNotEmpty && data[0]['last_completed_date'] != null) {
        return DateTime.parse(data[0]['last_completed_date'] as String);
      }
    } catch (_) {}

    // Fallback: check work_orders completed for this asset
    try {
      final data = await _client
          .from('work_orders')
          .select('completed_at')
          .eq('asset_id', assetId)
          .eq('status', 'completed')
          .not('completed_at', 'is', null)
          .order('completed_at', ascending: false)
          .limit(1);
      if (data.isNotEmpty && data[0]['completed_at'] != null) {
        return DateTime.parse(data[0]['completed_at'] as String);
      }
    } catch (_) {}

    return null;
  }

  /// Get last maintenance dates for multiple assets (batch — single query)
  Future<Map<String, DateTime?>> getLastMaintenanceDates(
    List<String> assetIds,
  ) async {
    if (assetIds.isEmpty) return {};

    final result = <String, DateTime?>{for (final id in assetIds) id: null};

    // Batch 1: get all PM schedule last_completed_date for these assets
    try {
      final pmData = await _client
          .from('pm_schedules')
          .select('asset_id, last_completed_date')
          .inFilter('asset_id', assetIds)
          .not('last_completed_date', 'is', null)
          .order('last_completed_date', ascending: false);

      for (final row in pmData) {
        final assetId = row['asset_id'] as String;
        final date = DateTime.parse(row['last_completed_date'] as String);
        if (result[assetId] == null || date.isAfter(result[assetId]!)) {
          result[assetId] = date;
        }
      }
    } catch (_) {}

    // Batch 2: get completed work_orders for assets still without a date
    final missingIds = result.entries
        .where((e) => e.value == null)
        .map((e) => e.key)
        .toList();

    if (missingIds.isNotEmpty) {
      try {
        final woData = await _client
            .from('work_orders')
            .select('asset_id, completed_at')
            .inFilter('asset_id', missingIds)
            .eq('status', 'completed')
            .not('completed_at', 'is', null)
            .order('completed_at', ascending: false);

        for (final row in woData) {
          final assetId = row['asset_id'] as String;
          final date = DateTime.parse(row['completed_at'] as String);
          if (result[assetId] == null || date.isAfter(result[assetId]!)) {
            result[assetId] = date;
          }
        }
      } catch (_) {}
    }

    return result;
  }

  // ─── Storage ──────────────────────────────────────────

  Future<String> uploadFile(
    String bucket,
    String path,
    Uint8List bytes, {
    String? contentType,
  }) async {
    await _client.storage.from(bucket).uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType ?? _mimeFromPath(path),
          ),
        );
    return _client.storage.from(bucket).getPublicUrl(path);
  }

  static String _mimeFromPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  // ─── Work Order Comments ─────────────────────────────

  /// Get all comments for a work order (with user info)
  Future<List<Map<String, dynamic>>> getWorkOrderComments(
    String workOrderId,
  ) async {
    return await _client
        .from('work_order_comments')
        .select('*, user:user_id(full_name)')
        .eq('work_order_id', workOrderId)
        .order('created_at', ascending: true);
  }

  /// Add a comment to a work order
  Future<void> addWorkOrderComment(
    String workOrderId,
    String content,
  ) async {
    final userId = _client.auth.currentUser?.id;
    await _client.from('work_order_comments').insert({
      'work_order_id': workOrderId,
      'content': content,
      if (userId != null) 'user_id': userId,
    });
  }

  // ─── Property Work Order Status Counts ───────────────

  /// Batch-fetch open/in_progress work order counts for a list of properties
  /// Returns: { propertyId: { 'open': n, 'in_progress': n } }
  Future<Map<String, Map<String, int>>> getWorkOrderStatusCountsForProperties(
    List<String> propertyIds,
  ) async {
    if (propertyIds.isEmpty) return {};
    try {
      final data = await _client
          .from('work_orders')
          .select('property_id, status')
          .inFilter('property_id', propertyIds)
          .inFilter('status', ['open', 'in_progress']);

      final result = <String, Map<String, int>>{};
      for (final row in data) {
        final propId = row['property_id'] as String;
        final status = row['status'] as String;
        result.putIfAbsent(propId, () => {'open': 0, 'in_progress': 0});
        result[propId]![status] = (result[propId]![status] ?? 0) + 1;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  // ─── Dashboard Stats ─────────────────────────────────

  Future<int> getUrgentJobsCount() async {
    final data = await _client
        .from('work_orders')
        .select('id')
        .eq('priority', 'urgent')
        .neq('status', 'completed');
    return data.length;
  }

  Future<int> getTodayJobsCount() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final end = start.add(const Duration(days: 1));
    final data = await _client
        .from('work_orders')
        .select('id')
        .gte('created_at', start.toIso8601String())
        .lt('created_at', end.toIso8601String());
    return data.length;
  }

  /// Lightweight: get only recent work orders (limited) for dashboard
  Future<List<Map<String, dynamic>>> getRecentWorkOrders({
    int limit = 5,
  }) async {
    return await _client
        .from('work_orders')
        .select()
        .order('created_at', ascending: false)
        .limit(limit);
  }

  /// Lightweight: get property count + name map without full data
  Future<List<Map<String, dynamic>>> getPropertyNamesOnly() async {
    return await _client
        .from('properties')
        .select('id, name')
        .order('name', ascending: true);
  }

  /// Batch-fetch user full_names by a list of user IDs
  Future<Map<String, String>> getUserNamesByIds(List<String> ids) async {
    if (ids.isEmpty) return {};
    final data = await _client
        .from('users')
        .select('id, full_name')
        .inFilter('id', ids);
    return {
      for (final u in data) u['id'] as String: u['full_name'] as String,
    };
  }

  /// Count completed work orders that have no expense records
  Future<int> getNoExpenseWorkOrdersCount() async {
    final withExpenses = await getWorkOrderIdsWithExpenses();
    final completed = await _client
        .from('work_orders')
        .select('id')
        .eq('status', 'completed');
    final noExpense = completed.where(
      (wo) => !withExpenses.contains(wo['id'] as String),
    );
    return noExpense.length;
  }

  /// Get work_order_ids that have at least one expense (for badge checking)
  Future<Set<String>> getWorkOrderIdsWithExpenses() async {
    final data = await _client
        .from('expenses')
        .select('work_order_id')
        .not('work_order_id', 'is', null);
    return {
      for (final e in data)
        if (e['work_order_id'] != null) e['work_order_id'] as String,
    };
  }

  // ─── User Management ─────────────────────────────────

  /// Get all users (for admin roles management)
  Future<List<Map<String, dynamic>>> getUsers() async {
    return await _client
        .from('users')
        .select()
        .order('created_at', ascending: false);
  }

  Future<List<Map<String, dynamic>>> getTechnicians() async {
    return await _client
        .from('users')
        .select()
        .eq('role', 'technician')
        .order('full_name', ascending: true);
  }

  /// Get all users with 'caretaker' role
  Future<List<Map<String, dynamic>>> getCaretakers() async {
    return await _client
        .from('users')
        .select()
        .eq('role', 'caretaker')
        .order('full_name', ascending: true);
  }

  /// Get a single user by ID
  Future<Map<String, dynamic>?> getUser(String id) async {
    return await _client.from('users').select().eq('id', id).maybeSingle();
  }

  /// Update a user's role
  Future<void> updateUserRole(String userId, String role) async {
    await _client.from('users').update({'role': role}).eq('id', userId);
  }

  /// Update user profile
  Future<void> updateUser(String userId, Map<String, dynamic> data) async {
    await _client.from('users').update(data).eq('id', userId);
  }

  /// Delete a user from the users table
  Future<void> deleteUser(String userId) async {
    await _client.from('users').delete().eq('id', userId);
  }

  /// Create a new user entry in the users table directly.
  /// The user can log in later via LINE or email signup.
  /// This avoids Supabase Auth signUp rate limiting (429).
  Future<void> createUser({
    required String fullName,
    required String email,
    required String role,
    String? phone,
  }) async {
    await _client.from('users').insert({
      'email': email,
      'full_name': fullName,
      'role': role,
      'phone': phone,
    });
  }

  // ─── LINE Notification ────────────────────────────────

  /// Send a LINE push message to a user (requires line_user_id)
  Future<void> sendLineNotification({
    required String lineUserId,
    required String message,
  }) async {
    final token = dotenv.env['LINE_MESSAGING_TOKEN'];
    if (token == null || token.isEmpty) return;

    await http.post(
      Uri.parse('https://api.line.me/v2/bot/message/push'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'to': lineUserId,
        'messages': [
          {'type': 'text', 'text': message},
        ],
      }),
    );
  }

  // ─── Contractors (ช่างภายนอก) ────────────────────────

  Future<List<Map<String, dynamic>>> getContractors({bool? activeOnly}) async {
    var query = _client.from('contractors').select();
    if (activeOnly == true) query = query.eq('is_active', true);
    return await query.order('name', ascending: true);
  }

  Future<Map<String, dynamic>> getContractor(String id) async {
    return await _client.from('contractors').select().eq('id', id).single();
  }

  Future<void> createContractor(Map<String, dynamic> data) async {
    await _client.from('contractors').insert(data);
  }

  Future<void> updateContractor(String id, Map<String, dynamic> data) async {
    await _client.from('contractors').update(data).eq('id', id);
  }

  Future<void> deleteContractor(String id) async {
    await _client.from('contractors').delete().eq('id', id);
  }

  // ─── Contractor History (ประวัติช่างภายนอก) ─────────

  Future<List<Map<String, dynamic>>> getContractorHistory(
    String contractorId,
  ) async {
    return await _client
        .from('contractor_history')
        .select(
          '*, work_orders:work_order_id(title), properties:property_id(name)',
        )
        .eq('contractor_id', contractorId)
        .order('work_date', ascending: false);
  }

  Future<void> createContractorHistory(Map<String, dynamic> data) async {
    await _client.from('contractor_history').insert(data);
  }

  Future<void> updateContractorHistory(
    String id,
    Map<String, dynamic> data,
  ) async {
    await _client.from('contractor_history').update(data).eq('id', id);
  }

  Future<void> deleteContractorHistory(String id) async {
    await _client.from('contractor_history').delete().eq('id', id);
  }

  /// Notify assigned technician about a new work order via LINE
  Future<void> notifyWorkOrderAssigned({
    required String assignedToUserId,
    required String workOrderTitle,
    required String propertyName,
  }) async {
    try {
      final user = await getUser(assignedToUserId);
      if (user == null) return;
      final lineUserId = user['line_user_id'] as String?;
      if (lineUserId == null || lineUserId.isEmpty) return;

      await sendLineNotification(
        lineUserId: lineUserId,
        message:
            '📢 คุณได้รับมอบหมายงานใหม่!\n'
            '📝 $workOrderTitle\n'
            '🏠 บ้าน: $propertyName\n'
            'เข้าไปดูรายละเอียดได้ที่แอป ChangYai',
      );
    } catch (_) {
      // Silent fail — notification is optional
    }
  }

  // ─── Purchase Orders (สั่งอุปกรณ์) ──────────────────

  Future<List<Map<String, dynamic>>> getPurchaseOrders({
    String? status,
    String? propertyId,
    String? createdBy,
  }) async {
    var query = _client.from('purchase_orders').select('*, creator:created_by(full_name), assignee:po_assigned_to(full_name)');
    if (status != null) query = query.eq('status', status);
    if (propertyId != null) query = query.eq('property_id', propertyId);
    if (createdBy != null) query = query.eq('created_by', createdBy);
    return await query.order('created_at', ascending: false);
  }

  Future<Map<String, dynamic>> getPurchaseOrder(String id) async {
    return await _client.from('purchase_orders').select('*, creator:created_by(full_name), assignee:po_assigned_to(full_name)').eq('id', id).single();
  }

  Future<void> createPurchaseOrder(Map<String, dynamic> data) async {
    final userId = _client.auth.currentUser?.id;
    final d = userId != null ? {...data, 'created_by': userId} : data;
    await _client.from('purchase_orders').insert(d);
  }

  Future<void> updatePurchaseOrder(String id, Map<String, dynamic> data) async {
    await _client.from('purchase_orders').update(data).eq('id', id);
  }

  Future<void> deletePurchaseOrder(String id) async {
    await _client.from('purchase_orders').delete().eq('id', id);
  }

  // ─── Purchase Order Comments ──────────────────────────

  Future<List<Map<String, dynamic>>> getPOComments(String poId) async {
    return await _client
        .from('purchase_order_comments')
        .select('*, user:user_id(full_name)')
        .eq('purchase_order_id', poId)
        .order('created_at', ascending: true);
  }

  Future<void> createPOComment(Map<String, dynamic> data) async {
    await _client.from('purchase_order_comments').insert(data);
  }
}
