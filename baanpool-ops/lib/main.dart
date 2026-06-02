import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'services/auth_state_service.dart';
import 'services/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use path URL strategy (no /#/ in URLs)
  usePathUrlStrategy();

  // Load environment variables
  await dotenv.load(fileName: '.env');

  // Initialize Supabase with session persistence
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    authOptions: const FlutterAuthClientOptions(autoRefreshToken: true),
  );

  // Try to recover persisted session (especially after app restart)
  try {
    final session = Supabase.instance.client.auth.currentSession;
    if (session != null) {
      await Supabase.instance.client.auth.refreshSession();
    }
  } catch (_) {
    // If refresh fails, user will be redirected to login
  }

  // Initialize auth state (loads current user profile + role)
  await AuthStateService().init();

  // Initialize in-app notifications (load + realtime)
  await NotificationService().init();

  // Re-initialize notifications when auth state changes (login/logout)
  Supabase.instance.client.auth.onAuthStateChange.listen((data) {
    if (data.event == AuthChangeEvent.signedIn) {
      NotificationService().reinit();
      // PM schedule checks run server-side via pg_cron (once per day)
    } else if (data.event == AuthChangeEvent.signedOut) {
      NotificationService().dispose2();
    }
  });

  runApp(const ChangYaiApp());
}

/// Global Supabase client accessor
final supabase = Supabase.instance.client;

class ChangYaiApp extends StatelessWidget {
  const ChangYaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Chang Yai-BPV',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
    );
  }
}
