import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/notification_service.dart';

/// ระฆังแจ้งเตือนบน AppBar — ใช้ร่วมทุกหน้า
///
/// ฟังจำนวนที่ยังไม่อ่านจาก [NotificationService] เอง
/// หน้าที่เรียกใช้ไม่ต้องจัดการ state ให้
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final _noti = NotificationService();

  @override
  void initState() {
    super.initState();
    _noti.addListener(_onChanged);
  }

  @override
  void dispose() {
    _noti.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final count = _noti.unreadCount;
    final onNotificationsPage =
        GoRouterState.of(context).uri.toString().startsWith('/notifications');

    return IconButton(
      tooltip: count > 0 ? 'แจ้งเตือน ($count ยังไม่อ่าน)' : 'แจ้งเตือน',
      // push ไม่ใช่ go — จะได้มีปุ่มย้อนกลับ สำคัญกับ role ที่ไม่มีแถบเมนู (ช่าง)
      onPressed: onNotificationsPage ? null : () => context.push('/notifications'),
      icon: count > 0
          ? Badge(
              label: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(fontSize: 10),
              ),
              child: Icon(
                onNotificationsPage
                    ? Icons.notifications
                    : Icons.notifications_outlined,
              ),
            )
          : Icon(
              onNotificationsPage
                  ? Icons.notifications
                  : Icons.notifications_outlined,
            ),
    );
  }
}
