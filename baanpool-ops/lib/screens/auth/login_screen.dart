import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/line_auth_service.dart';
import '../../services/auth_state_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _showEmailLogin = false;

  late final LineAuthService _lineAuth;
  StreamSubscription<AuthState>? _authSub;

  @override
  void initState() {
    super.initState();
    _lineAuth = LineAuthService(Supabase.instance.client);

    // Listen for auth state changes (e.g., after LINE callback)
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((
      data,
    ) async {
      if (data.event == AuthChangeEvent.signedIn && mounted) {
        await AuthStateService().loadUserProfile();
        if (mounted) {
          final authState = AuthStateService();
          context.go(authState.isTechnician ? '/work-orders' : '/');
        }
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signInWithLine() async {
    setState(() => _loading = true);
    try {
      await _lineAuth.signInWithLine();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('LINE Login ล้มเหลว: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      try {
        // Try sign in first
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
      } on AuthException catch (authErr) {
        // If user doesn't exist, auto sign-up
        if (authErr.message.contains('Invalid login credentials')) {
          final signUpRes = await Supabase.instance.client.auth.signUp(
            email: email,
            password: password,
            data: {'full_name': email.split('@').first},
          );

          if (signUpRes.user == null) {
            throw Exception('สร้างบัญชีไม่สำเร็จ');
          }

          // Check if admin pre-created this user in users table
          String role = 'admin'; // First user = admin by default
          String fullName = email.split('@').first;
          try {
            final existing = await Supabase.instance.client
                .from('users')
                .select()
                .eq('email', email)
                .maybeSingle();
            if (existing != null) {
              // Admin pre-created this user → update ID to match auth
              role = existing['role'] as String? ?? 'technician';
              fullName = existing['full_name'] as String? ?? fullName;
              await Supabase.instance.client
                  .from('users')
                  .update({'id': signUpRes.user!.id})
                  .eq('email', email);
            } else {
              // Check if we're the first user → admin
              final existingUsers = await Supabase.instance.client
                  .from('users')
                  .select('id')
                  .limit(2);
              if (existingUsers.isNotEmpty) {
                role = 'technician'; // Not the first user
              }
              // Insert new user entry
              await Supabase.instance.client.from('users').upsert({
                'id': signUpRes.user!.id,
                'email': email,
                'full_name': fullName,
                'role': role,
              });
            }
          } catch (_) {
            // RLS may block, try insert anyway
            try {
              await Supabase.instance.client.from('users').upsert({
                'id': signUpRes.user!.id,
                'email': email,
                'full_name': fullName,
                'role': role,
              });
            } catch (_) {}
          }

          // Sign in after sign up
          await Supabase.instance.client.auth.signInWithPassword(
            email: email,
            password: password,
          );

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'สร้างบัญชีใหม่สำเร็จ (Role: ${role == 'admin' ? 'ผู้ดูแลระบบ' : role})',
                ),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          rethrow;
        }
      }

      // Load user profile to get role
      await AuthStateService().loadUserProfile();
      if (mounted) {
        final authState = AuthStateService();
        context.go(authState.isTechnician ? '/work-orders' : '/');
      }
    } on AuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('เข้าสู่ระบบไม่สำเร็จ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Logo / Title
                Image.asset(
                  'logo/logo.png',
                  width: 180,
                  height: 120,
                  fit: BoxFit.contain,
                ),
                const SizedBox(height: 16),
                Text(
                  'ChangYai',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Property Operations System',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 48),

                // ═══════════════════════════════════
                // LINE Login Button (Primary)
                // ═══════════════════════════════════
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _loading ? null : _signInWithLine,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF06C755),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    icon: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const _LineIcon(),
                    label: const Text(
                      'เข้าสู่ระบบด้วย LINE',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // Divider
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'หรือ',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),

                const SizedBox(height: 16),

                // ═══════════════════════════════════
                // Email/Password Login (Secondary)
                // ═══════════════════════════════════
                if (!_showEmailLogin)
                  TextButton(
                    onPressed: () => setState(() => _showEmailLogin = true),
                    child: const Text('เข้าสู่ระบบด้วยอีเมล'),
                  )
                else
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'อีเมล',
                            prefixIcon: Icon(Icons.email_outlined),
                          ),
                          validator: (v) =>
                              v == null || v.isEmpty ? 'กรุณากรอกอีเมล' : null,
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'รหัสผ่าน',
                            prefixIcon: Icon(Icons.lock_outlined),
                          ),
                          validator: (v) => v == null || v.isEmpty
                              ? 'กรุณากรอกรหัสผ่าน'
                              : null,
                          onFieldSubmitted: (_) => _signInWithEmail(),
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: FilledButton(
                            onPressed: _loading ? null : _signInWithEmail,
                            child: _loading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('เข้าสู่ระบบ'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// LINE icon widget
class _LineIcon extends StatelessWidget {
  const _LineIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          'L',
          style: TextStyle(
            color: Color(0xFF06C755),
            fontWeight: FontWeight.w900,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
