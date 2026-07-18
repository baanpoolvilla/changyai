import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/user.dart';
import '../services/auth_state_service.dart';

/// Shell screen with bottom navigation bar — role-aware
class ShellScreen extends StatefulWidget {
  final Widget child;

  const ShellScreen({super.key, required this.child});

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen> {
  final _authState = AuthStateService();

  @override
  void initState() {
    super.initState();
    _authState.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _authState.removeListener(_onAuthChanged);
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
          label: 'สั่งซื้ออุปกรณ์',
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
          icon: Icons.home_repair_service_outlined,
          selectedIcon: Icons.home_repair_service,
          label: 'บำรุงรักษา',
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

    // แจ้งเตือนย้ายไปอยู่บน AppBar แล้ว (NotificationBell) ไม่อยู่ใน nav

    // Admin-only: roles management + LINE log (only role=admin, not owner/manager)
    if (_authState.currentRole == UserRole.admin) {
      items.add(
        _NavItem(
          path: '/admin/roles',
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings,
          label: 'จัดการ Roles',
        ),
      );
      items.add(
        _NavItem(
          path: '/admin/line-log',
          icon: Icons.history_outlined,
          selectedIcon: Icons.history,
          label: 'Log LINE',
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

    // มีเมนูเดียว (เช่น ช่าง เห็นแค่ใบงาน) → เต็มจอ ไม่ต้องมีแถบเมนู
    // NavigationBar บังคับอย่างน้อย 2 ช่อง ไม่งั้น assert แตกตั้งแต่เข้าแอป
    if (navItems.length < 2) {
      return Scaffold(body: widget.child);
    }

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
                  'logo/logo.png',
                  width: isWide ? 48 : 36,
                  errorBuilder: (_, __, ___) => Icon(Icons.home_work, size: isWide ? 40 : 28),
                ),
              ),
              minWidth: 72,
              minExtendedWidth: 200,
              groupAlignment: -1,
              destinations: navItems
                  .map(
                    (item) => NavigationRailDestination(
                      icon: Icon(item.icon),
                      selectedIcon: Icon(item.selectedIcon),
                      label: Text(item.label),
                    ),
                  )
                  .toList(),
            ),
            const VerticalDivider(thickness: 1, width: 1),
            Expanded(child: widget.child),
          ],
        ),
      );
    }

    // ─── มือถือ: bottom nav ไม่เกิน 5 ช่อง ที่เหลือเข้า "เพิ่มเติม" ───
    // Material Design กำหนดไม่เกิน 5 — มากกว่านั้นข้อความจะตัดบรรทัดจนอ่านไม่ออก
    const maxTabs = 4; // + ช่อง "เพิ่มเติม" = 5
    final primary = navItems.take(maxTabs).toList();
    final overflow = navItems.skip(maxTabs).toList();
    final overflowSelected =
        currentIdx >= maxTabs; // อยู่ในหน้าที่ซ่อนอยู่ใน "เพิ่มเติม"

    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: overflowSelected ? primary.length : currentIdx,
        onDestinationSelected: (index) {
          if (index == primary.length && overflow.isNotEmpty) {
            _showMoreSheet(overflow);
            return;
          }
          context.go(navItems[index].path);
        },
        destinations: [
          for (final item in primary)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
          if (overflow.isNotEmpty)
            NavigationDestination(
              icon: const Icon(Icons.more_horiz),
              selectedIcon: const Icon(Icons.more_horiz),
              label: 'เพิ่มเติม',
            ),
        ],
      ),
    );
  }

  /// เมนูที่เหลือจาก bottom nav — เปิดเป็น bottom sheet
  Future<void> _showMoreSheet(List<_NavItem> items) async {
    final location = GoRouterState.of(context).uri.toString();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final item in items)
              ListTile(
                leading: Icon(
                  location.startsWith(item.path) ? item.selectedIcon : item.icon,
                ),
                title: Text(item.label),
                selected: location.startsWith(item.path),
                onTap: () {
                  Navigator.pop(ctx);
                  context.go(item.path);
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _NavItem {
  final String path;
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _NavItem({
    required this.path,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}
