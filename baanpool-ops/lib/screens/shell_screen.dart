import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user.dart';
import '../services/auth_state_service.dart';
import '../services/notification_service.dart';

/// Shell screen with bottom navigation bar — role-aware
class ShellScreen extends StatefulWidget {
  final Widget child;

  const ShellScreen({super.key, required this.child});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  final _authState = AuthStateService();
  final _notiService = NotificationService();

  @override
  void initState() {
    super.initState();
    _authState.addListener(_onAuthChanged);
    _notiService.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _authState.removeListener(_onAuthChanged);
    _notiService.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    if (mounted) setState(() {});
  }

  /// Build navigation destinations based on user role
  List<_NavItem> _getNavItems() {
    final isAdmin = _authState.isAdmin;

    final items = <_NavItem>[];

    if (isAdmin) {
      items.add(
        _NavItem(
          path: '/',
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          label: 'แดชบอร์ด',
        ),
      );
    }

    // Work orders — visible to everyone
    items.add(
      _NavItem(
        path: '/work-orders',
        icon: Icons.assignment_outlined,
        selectedIcon: Icons.assignment,
        label: 'ใบงาน',
      ),
    );

    // Purchase Orders — visible to all except technician
    if (!_authState.isTechnician) {
      items.add(
        _NavItem(
          path: '/purchase-orders',
          icon: Icons.shopping_cart_outlined,
          selectedIcon: Icons.shopping_cart,
          label: 'สั่งอุปกรณ์',
        ),
      );
    }

    // Quick Expense — caretaker + manager บันทึกค่าใช้จ่ายเล็กน้อยเอง
    if (_authState.isCaretaker || _authState.isManager || isAdmin) {
      items.add(
        _NavItem(
          path: '/quick-expense',
          icon: Icons.add_shopping_cart_outlined,
          selectedIcon: Icons.add_shopping_cart,
          label: 'บันทึกค่าใช้จ่าย',
        ),
      );
    }

    if (isAdmin) {
      items.add(
        _NavItem(
          path: '/properties',
          icon: Icons.home_outlined,
          selectedIcon: Icons.home,
          label: 'บ้าน',
        ),
      );

      items.add(
        _NavItem(
          path: '/expenses',
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long,
          label: 'ค่าใช้จ่าย',
        ),
      );

      items.add(
        _NavItem(
          path: '/pm',
          icon: Icons.schedule_outlined,
          selectedIcon: Icons.schedule,
          label: 'PM',
        ),
      );

      items.add(
        _NavItem(
          path: '/contractors',
          icon: Icons.contacts_outlined,
          selectedIcon: Icons.contacts,
          label: 'Contact',
        ),
      );
    }

    // Notifications — visible to everyone
    items.add(
      _NavItem(
        path: '/notifications',
        icon: Icons.notifications_outlined,
        selectedIcon: Icons.notifications,
        label: 'แจ้งเตือน',
        badgeCount: _notiService.unreadCount,
      ),
    );

    // Admin-only: roles management (only role=admin, not owner/manager)
    if (_authState.currentRole == UserRole.admin) {
      items.add(
        _NavItem(
          path: '/admin/roles',
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings,
          label: 'จัดการ Roles',
        ),
      );
    }

    return items;
  }

  int _currentIndex(BuildContext context, List<_NavItem> items) {
    final location = GoRouterState.of(context).uri.toString();
    for (int i = 0; i < items.length; i++) {
      if (items[i].path == '/' && location == '/') return i;
      if (items[i].path != '/' && location.startsWith(items[i].path)) return i;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final navItems = _getNavItems();
    final currentIdx = _currentIndex(context, navItems).clamp(0, navItems.length - 1);
    final isDesktop = MediaQuery.of(context).size.width >= 720;

    if (isDesktop) {
      final isWide = MediaQuery.of(context).size.width >= 1200;
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: isWide,
              selectedIndex: currentIdx,
              onDestinationSelected: (index) {
                context.go(navItems[index].path);
              },
              labelType: isWide
                  ? NavigationRailLabelType.none
                  : NavigationRailLabelType.all,
              leading: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Image.asset(
                  'assets/logo.png',
                  width: isWide ? 40 : 32,
                  errorBuilder: (_, __, ___) => Icon(Icons.home_work, size: isWide ? 40 : 28),
                ),
              ),
              minWidth: 72,
              minExtendedWidth: 200,
              groupAlignment: -1,
              destinations: navItems.map((item) {
                final icon = item.badgeCount > 0
                    ? Badge(
                        label: Text(
                          item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        child: Icon(item.icon),
                      )
                    : Icon(item.icon);
                final selectedIcon = item.badgeCount > 0
                    ? Badge(
                        label: Text(
                          item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        child: Icon(item.selectedIcon),
                      )
                    : Icon(item.selectedIcon);
                return NavigationRailDestination(
                  icon: icon,
                  selectedIcon: selectedIcon,
                  label: Text(item.label),
                );
              }).toList(),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    // Mobile: bottom navigation bar
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIdx,
        onDestinationSelected: (index) {
          context.go(navItems[index].path);
        },
        destinations: navItems
            .map(
              (item) => NavigationDestination(
                icon: item.badgeCount > 0
                    ? Badge(
                        label: Text(
                          item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        child: Icon(item.icon),
                      )
                    : Icon(item.icon),
                selectedIcon: item.badgeCount > 0
                    ? Badge(
                        label: Text(
                          item.badgeCount > 99 ? '99+' : '${item.badgeCount}',
                          style: const TextStyle(fontSize: 10),
                        ),
                        child: Icon(item.selectedIcon),
                      )
                    : Icon(item.selectedIcon),
                label: item.label,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _NavItem {
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badgeCount;

  const _NavItem({
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badgeCount = 0,
  });
}
