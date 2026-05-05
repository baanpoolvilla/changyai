import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// In-app notification service with realtime subscription.
/// Listens to the `notifications` table for the current user.
class NotificationService extends ChangeNotifier {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final _client = Supabase.instance.client;
  RealtimeChannel? _channel;
  Timer? _pollTimer;

  List<Map<String, dynamic>> _notifications = [];
  int _unreadCount = 0;
  bool _initialized = false;

  List<Map<String, dynamic>> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get hasUnread => _unreadCount > 0;

  /// Initialize: load existing notifications + subscribe to realtime
  /// Can be called multiple times safely (re-subscribes if user changed)
  Future<void> init() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    // If already initialized for this user, skip
    if (_initialized) {
      // But still refresh to get latest
      await _loadNotifications();
      return;
    }

    _initialized = true;
    await _cleanupOldReadNotifications();
    await _loadNotifications();
    _subscribeRealtime(user.id);
    _startPolling();
  }

  /// Re-initialize (e.g. after login)
  Future<void> reinit() async {
    dispose2();
    await init();
  }

  /// Load existing notifications from DB
  Future<void> _loadNotifications() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      final data = await _client
          .from('notifications')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);
      _notifications = List<Map<String, dynamic>>.from(data);
      _unreadCount = _notifications.where((n) => n['is_read'] != true).length;
      notifyListeners();
    } catch (e) {
      debugPrint('Load notifications error: $e');
    }
  }

  /// Subscribe to realtime inserts on notifications table
  void _subscribeRealtime(String userId) {
    _channel?.unsubscribe();
    _channel = _client
        .channel('notifications:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            debugPrint('Realtime notification received: ${payload.newRecord}');
            final newNoti = payload.newRecord;
            if (newNoti.isNotEmpty) {
              // Check if we already have this notification (avoid duplicates)
              final existingIdx = _notifications.indexWhere(
                (n) => n['id'] == newNoti['id'],
              );
              if (existingIdx < 0) {
                _notifications.insert(0, newNoti);
                _unreadCount++;
                notifyListeners();
              }
            }
          },
        )
        .subscribe((status, [error]) {
          debugPrint('Realtime subscription status: $status, error: $error');
          if (status == RealtimeSubscribeStatus.channelError) {
            // Retry subscription after a delay
            Future.delayed(const Duration(seconds: 5), () {
              if (_initialized) {
                debugPrint('Retrying realtime subscription...');
                _subscribeRealtime(userId);
              }
            });
          }
        });
  }

  /// Fallback: poll every 30 seconds in case realtime misses events
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadNotifications();
    });
  }

  /// Reload notifications
  Future<void> refresh() async {
    await _loadNotifications();
  }

  /// Mark a single notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      final now = DateTime.now().toIso8601String();
      await _client
          .from('notifications')
          .update({'is_read': true, 'read_at': now})
          .eq('id', notificationId);

      final idx = _notifications.indexWhere((n) => n['id'] == notificationId);
      if (idx >= 0 && _notifications[idx]['is_read'] != true) {
        _notifications[idx] = {..._notifications[idx], 'is_read': true, 'read_at': now};
        _unreadCount = (_unreadCount - 1).clamp(0, 999);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Mark as read error: $e');
    }
  }

  /// Mark all as read
  Future<void> markAllAsRead() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      final now = DateTime.now().toIso8601String();
      await _client
          .from('notifications')
          .update({'is_read': true, 'read_at': now})
          .eq('user_id', user.id)
          .eq('is_read', false);

      for (int i = 0; i < _notifications.length; i++) {
        if (_notifications[i]['is_read'] != true) {
          _notifications[i] = {..._notifications[i], 'is_read': true, 'read_at': now};
        }
      }
      _unreadCount = 0;
      notifyListeners();
    } catch (e) {
      debugPrint('Mark all as read error: $e');
    }
  }

  /// Delete notifications that were read more than 2 days ago
  Future<void> _cleanupOldReadNotifications() async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return;

      final cutoff = DateTime.now().subtract(const Duration(days: 2)).toIso8601String();
      await _client
          .from('notifications')
          .delete()
          .eq('user_id', user.id)
          .eq('is_read', true)
          .lte('read_at', cutoff)
          .not('read_at', 'is', null);
    } catch (e) {
      debugPrint('Cleanup old notifications error: $e');
    }
  }

  /// Dispose realtime channel and polling
  void dispose2() {
    _channel?.unsubscribe();
    _channel = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _initialized = false;
  }
}
