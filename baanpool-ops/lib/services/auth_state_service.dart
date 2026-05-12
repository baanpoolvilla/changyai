import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user.dart';

/// Singleton service that tracks the current user's role and profile.
/// Notifies listeners when the role changes.
class AuthStateService extends ChangeNotifier {
  static final AuthStateService _instance = AuthStateService._internal();
  factory AuthStateService() => _instance;
  AuthStateService._internal();

  final SupabaseClient _client = Supabase.instance.client;

  AppUser? _currentAppUser;
  bool _loading = false;

  AppUser? get currentAppUser => _currentAppUser;
  bool get loading => _loading;

  UserRole get currentRole => _currentAppUser?.role ?? UserRole.technician;
  bool get isAdmin => currentRole.isAdmin;
  bool get isTechnician => currentRole == UserRole.technician;
  bool get isCaretaker => currentRole == UserRole.caretaker;
  bool get isLoggedIn => _client.auth.currentUser != null;

  StreamSubscription<AuthState>? _authSub;

  /// Initialize — call once from main.dart
  Future<void> init() async {
    // Listen for auth changes
    _authSub = _client.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.signedIn) {
        loadUserProfile();
      } else if (data.event == AuthChangeEvent.signedOut) {
        _currentAppUser = null;
        notifyListeners();
      }
    });

    // Load profile if already logged in
    if (_client.auth.currentUser != null) {
      await loadUserProfile();
    }
  }

  /// Fetch the current user's profile from the `users` table
  Future<void> loadUserProfile() async {
    final authUser = _client.auth.currentUser;
    if (authUser == null) return;

    _loading = true;
    notifyListeners();

    try {
      final data = await _client
          .from('users')
          .select()
          .eq('id', authUser.id)
          .maybeSingle();

      if (data != null) {
        _currentAppUser = AppUser.fromJson(data);
      } else {
        // User exists in auth but not in users table — create a default entry
        final newUser = {
          'id': authUser.id,
          'email': authUser.email ?? 'unknown@changyai.app',
          'full_name':
              authUser.userMetadata?['full_name'] ?? authUser.email ?? 'User',
          'role': 'technician',
        };
        await _client.from('users').upsert(newUser);
        _currentAppUser = AppUser(
          id: authUser.id,
          email: newUser['email']!,
          fullName: newUser['full_name']!,
          role: UserRole.technician,
          createdAt: DateTime.now(),
        );
      }
    } catch (e) {
      debugPrint('Error loading user profile: $e');
      // Fallback — still set a basic user object
      _currentAppUser = AppUser(
        id: authUser.id,
        email: authUser.email ?? '',
        fullName: authUser.userMetadata?['full_name'] ?? 'User',
        role: UserRole.technician,
        createdAt: DateTime.now(),
      );
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Sign out and clear cached state
  Future<void> signOut() async {
    await _client.auth.signOut();
    _currentAppUser = null;
    notifyListeners();
  }

  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}
