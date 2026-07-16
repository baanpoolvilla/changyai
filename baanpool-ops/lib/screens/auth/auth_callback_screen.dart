import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/line_auth_service.dart';
import '../../services/auth_state_service.dart';
import '../../utils/error_message.dart';

/// Auth callback screen — handles redirect from LINE OAuth
class AuthCallbackScreen extends StatefulWidget {
  const AuthCallbackScreen({super.key});

  @override
  State<AuthCallbackScreen> createState() => _AuthCallbackScreenState();
}

class _AuthCallbackScreenState extends State<AuthCallbackScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _handleCallback();
  }

  Future<void> _handleCallback() async {
    try {
      // Extract 'code' from the current URL query parameters
      final uri = Uri.base;
      final code = uri.queryParameters['code'];

      if (code == null || code.isEmpty) {
        setState(() => _error = 'ไม่พบ authorization code');
        return;
      }

      // Exchange LINE code for Supabase session
      final lineAuth = LineAuthService(Supabase.instance.client);
      await lineAuth.handleCallback(code);

      // Load user profile to get role
      await AuthStateService().loadUserProfile();

      // Success → go to appropriate page based on role
      if (mounted) {
        final authState = AuthStateService();
        context.go(authState.isTechnician ? '/work-orders' : '/');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'เข้าสู่ระบบไม่สำเร็จ: ${friendlyError(e)}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: _error != null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.error_outline, size: 48, color: Colors.red),
                  const SizedBox(height: 16),
                  Text(_error!, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('กลับหน้า Login'),
                  ),
                ],
              )
            : const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('กำลังเข้าสู่ระบบ...'),
                ],
              ),
      ),
    );
  }
}
