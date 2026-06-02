import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// LINE Login service — exchanges LINE code directly (no Edge Function needed)
class LineAuthService {
  final SupabaseClient _client;

  LineAuthService(this._client);

  String get _channelId => dotenv.env['LINE_CHANNEL_ID'] ?? '';
  String get _channelSecret => dotenv.env['LINE_CHANNEL_SECRET'] ?? '';

  /// Get the current redirect URL based on platform
  String get _redirectUrl {
    if (kIsWeb) {
      final uri = Uri.base;
      // Don't include port for standard ports (443 for HTTPS, 80 for HTTP)
      final isStandardPort =
          (uri.scheme == 'https' && uri.port == 443) ||
          (uri.scheme == 'http' && uri.port == 80);
      if (isStandardPort || uri.port == 0) {
        return '${uri.scheme}://${uri.host}/auth/callback';
      }
      return '${uri.scheme}://${uri.host}:${uri.port}/auth/callback';
    }
    return 'com.changyai.app://login-callback';
  }

  /// Open LINE Login page
  Future<void> signInWithLine() async {
    final state = _generateState();
    final nonce = _generateNonce();

    final authUrl = Uri.https('access.line.me', '/oauth2/v2.1/authorize', {
      'response_type': 'code',
      'client_id': _channelId,
      'redirect_uri': _redirectUrl,
      'state': state,
      'scope': 'profile openid email',
      'nonce': nonce,
      // Force consent screen + add OA as friend every login
      'bot_prompt': 'aggressive',
      'prompt': 'consent',
    });

    if (kIsWeb) {
      await launchUrl(authUrl, webOnlyWindowName: '_self');
    } else {
      await launchUrl(authUrl, mode: LaunchMode.externalApplication);
    }
  }

  /// Handle LINE callback: exchange code → get profile → sign in Supabase
  Future<void> handleCallback(String code) async {
    // 1) Exchange code for LINE access token
    final tokenRes = await http.post(
      Uri.parse('https://api.line.me/oauth2/v2.1/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'authorization_code',
        'code': code,
        'redirect_uri': _redirectUrl,
        'client_id': _channelId,
        'client_secret': _channelSecret,
      },
    );

    final tokenData = jsonDecode(tokenRes.body) as Map<String, dynamic>;
    if (tokenData.containsKey('error')) {
      throw Exception(tokenData['error_description'] ?? tokenData['error']);
    }

    final accessToken = tokenData['access_token'] as String;

    // 2) Get LINE user profile
    final profileRes = await http.get(
      Uri.parse('https://api.line.me/v2/profile'),
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    final profile = jsonDecode(profileRes.body) as Map<String, dynamic>;
    final lineUserId = profile['userId'] as String;
    final displayName = profile['displayName'] as String;
    final pictureUrl = profile['pictureUrl'] as String?;

    // 3) Sign in or sign up in Supabase using LINE userId as identifier
    final email = 'line_$lineUserId@changyai.app';
    final password = 'line_${lineUserId}_${_channelSecret.substring(0, 8)}';

    try {
      // Try sign in first
      await _client.auth.signInWithPassword(email: email, password: password);
    } on AuthException {
      // User doesn't exist in auth → sign up
      await _client.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': displayName,
          'avatar_url': pictureUrl,
          'line_user_id': lineUserId,
          'provider': 'line',
        },
      );

      // Sign in after sign up
      await _client.auth.signInWithPassword(email: email, password: password);
    }

    // 4) Upsert into users table with line_user_id
    final userId = _client.auth.currentUser!.id;

    // Check if there's already a users entry (admin may have pre-created)
    final existing = await _client
        .from('users')
        .select('id')
        .eq('id', userId)
        .maybeSingle();

    if (existing != null) {
      // Update existing entry with LINE info
      await _client
          .from('users')
          .update({'full_name': displayName, 'line_user_id': lineUserId})
          .eq('id', userId);
    } else {
      // Insert new entry — default role is technician
      await _client.from('users').upsert({
        'id': userId,
        'email': email,
        'full_name': displayName,
        'role': 'technician',
        'line_user_id': lineUserId,
      });
    }
  }

  /// Sign out
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  bool get isLoggedIn => _client.auth.currentUser != null;
  User? get currentUser => _client.auth.currentUser;
  Stream<AuthState> get onAuthStateChange => _client.auth.onAuthStateChange;

  String _generateState() {
    final bytes = List<int>.generate(
      16,
      (i) => DateTime.now().microsecond % 256,
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  String _generateNonce() {
    final bytes = List<int>.generate(
      32,
      (i) => DateTime.now().microsecond % 256,
    );
    return base64Url.encode(bytes).replaceAll('=', '');
  }
}
