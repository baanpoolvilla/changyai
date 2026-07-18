import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/auth_callback_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/properties/properties_list_screen.dart';
import '../screens/properties/property_detail_screen.dart';
import '../screens/properties/property_form_screen.dart';
import '../screens/assets/assets_list_screen.dart';
import '../screens/assets/asset_detail_screen.dart';
import '../screens/work_orders/work_orders_list_screen.dart';
import '../screens/work_orders/work_order_detail_screen.dart';
import '../screens/work_orders/work_order_form_screen.dart';
import '../screens/work_orders/external_work_order_upload_screen.dart';
import '../screens/expenses/expenses_list_screen.dart';
import '../screens/expenses/expense_form_screen.dart';
import '../screens/expenses/expense_report_screen.dart';
import '../screens/pm/pm_schedule_screen.dart';
import '../screens/pm/equipment_overview_screen.dart';
import '../screens/admin/roles_management_screen.dart';
import '../screens/admin/line_log_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/contractors/contractors_list_screen.dart';
import '../screens/contractors/contractor_detail_screen.dart';
import '../screens/purchase_orders/purchase_orders_list_screen.dart';
import '../screens/purchase_orders/purchase_order_form_screen.dart';
import '../screens/purchase_orders/purchase_order_detail_screen.dart';
import '../screens/shell_screen.dart';
import '../services/auth_state_service.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;
    final isExternalUploadRoute =
        state.uri.path.startsWith('/external-upload/');
    final isAuthRoute =
        state.uri.toString().startsWith('/login') ||
        state.uri.toString().startsWith('/auth');

    // Not logged in → go to login
    if (!isLoggedIn && !isAuthRoute && !isExternalUploadRoute) {
      return '/login';
    }
    // Logged in but on login page → go to dashboard or work-orders
    if (isLoggedIn && isAuthRoute) {
      final authState = AuthStateService();
      return authState.isTechnician ? '/work-orders' : '/';
    }

    // Role-based access guards
    if (isLoggedIn) {
      final authState = AuthStateService();
      final path = state.uri.toString();

      // Technicians cannot access dashboard, expenses, admin pages
      if (authState.isTechnician) {
        if (path == '/' ||
            path.startsWith('/expenses') ||
            path.startsWith('/admin')) {
          return '/work-orders';
        }
      }

      // Only admin role can access admin pages (not owner/manager)
      if (path.startsWith('/admin') &&
          authState.currentRole != UserRole.admin) {
        return '/work-orders';
      }
    }

    return null;
  },
  routes: [
    // Auth
    GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
    GoRoute(
      path: '/auth/callback',
      builder: (context, state) => const AuthCallbackScreen(),
    ),

    // Public photo-only upload page for external technicians
    GoRoute(
      path: '/external-upload/:token',
      builder: (context, state) => ExternalWorkOrderUploadScreen(
        token: state.pathParameters['token']!,
      ),
    ),

    // Main shell with bottom navigation
    ShellRoute(
      builder: (context, state, child) => ShellScreen(child: child),
      routes: [
        // Dashboard (admin only — technicians will be redirected)
        GoRoute(
          path: '/',
          builder: (context, state) => const DashboardScreen(),
        ),

        // Properties
        GoRoute(
          path: '/properties',
          builder: (context, state) => const PropertiesListScreen(),
          routes: [
            GoRoute(
              path: 'new',
              builder: (context, state) => const PropertyFormScreen(),
            ),
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  PropertyDetailScreen(propertyId: state.pathParameters['id']!),
              routes: [
                GoRoute(
                  path: 'edit',
                  builder: (context, state) => PropertyFormScreen(
                    propertyId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
          ],
        ),

        // Assets
        GoRoute(
          path: '/assets',
          builder: (context, state) => const AssetsListScreen(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) =>
                  AssetDetailScreen(assetId: state.pathParameters['id']!),
            ),
          ],
        ),

        // Work Orders
        GoRoute(
          path: '/work-orders',
          builder: (context, state) => WorkOrdersListScreen(
            initialFilter: state.uri.queryParameters['filter'],
            propertyId: state.uri.queryParameters['propertyId'],
          ),
          routes: [
            GoRoute(
              path: 'new',
              builder: (context, state) {
                final q = state.uri.queryParameters;
                return WorkOrderFormScreen(
                  prefillTitle: q['title'],
                  prefillPropertyId: q['propertyId'],
                  prefillTechnicianId: q['technicianId'],
                  prefillDescription: q['description'],
                  prefillAssetId: q['assetId'],
                  prefillPriority: q['priority'],
                  prefillPmScheduleId: q['pmScheduleId'],
                  prefillPmScheduleIds: q['pmScheduleIds']
                      ?.split(',')
                      .where((s) => s.isNotEmpty)
                      .toList(),
                  prefillAdditionalPropertyIds: q['additionalPropertyIds']
                      ?.split(',')
                      .where((s) => s.isNotEmpty)
                      .toList(),
                );
              },
            ),
            GoRoute(
              path: ':id',
              builder: (context, state) => WorkOrderDetailScreen(
                workOrderId: state.pathParameters['id']!,
              ),
            ),
          ],
        ),

        // Expenses (admin only — technicians will be redirected)
        GoRoute(
          path: '/expenses',
          builder: (context, state) => const ExpensesListScreen(),
          routes: [
            GoRoute(
              path: 'new',
              builder: (context, state) => ExpenseFormScreen(
                workOrderId: state.uri.queryParameters['workOrderId'],
                pmScheduleId: state.uri.queryParameters['pmScheduleId'],
              ),
            ),
            GoRoute(
              path: 'report',
              builder: (context, state) => const ExpenseReportScreen(),
            ),
          ],
        ),

        // PM Schedules
        GoRoute(
          path: '/pm',
          builder: (context, state) => PmScheduleScreen(
            initialPropertyId: state.uri.queryParameters['propertyId'],
          ),
        ),

        // Equipment Overview (แอร์/ฉีดปลวก/สระว่ายน้ำ ทุกหลัง)
        GoRoute(
          path: '/equipment-overview',
          builder: (context, state) => const EquipmentOverviewScreen(),
        ),

        // Admin — Roles Management
        GoRoute(
          path: '/admin/roles',
          builder: (context, state) => const RolesManagementScreen(),
        ),

        // Admin — LINE Notification Log
        GoRoute(
          path: '/admin/line-log',
          builder: (context, state) => const LineLogScreen(),
        ),

        // Notifications
        GoRoute(
          path: '/notifications',
          builder: (context, state) => const NotificationsScreen(),
        ),

        // Contractors (ช่างภายนอก / ผู้รับเหมา)
        GoRoute(
          path: '/contractors',
          builder: (context, state) => const ContractorsListScreen(),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) => ContractorDetailScreen(
                contractorId: state.pathParameters['id']!,
              ),
            ),
          ],
        ),

        // Purchase Orders
        GoRoute(
          path: '/purchase-orders',
          builder: (context, state) => const PurchaseOrdersListScreen(),
          routes: [
            GoRoute(
              path: 'new',
              builder: (context, state) => const PurchaseOrderFormScreen(),
            ),
            GoRoute(
              path: ':id',
              builder: (context, state) => PurchaseOrderDetailScreen(
                orderId: state.pathParameters['id']!,
              ),
            ),
          ],
        ),
      ],
    ),
  ],
);
