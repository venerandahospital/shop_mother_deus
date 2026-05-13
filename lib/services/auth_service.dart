import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/client.dart';
import '../models/debt.dart';
import '../models/debt_payment.dart';
import '../models/expense.dart';
import '../models/item.dart';
import '../models/service_transaction.dart';
import '../models/store.dart';
import '../models/unit.dart';
import '../models/loan.dart';
import 'local_db_service.dart';

class AuthService {
  static const String _pendingRemoteApprovalLoginMessage =
      'Your account is not verified yet. Please contact the shop owner on the main device (mother app) so they can verify your account and assign your role.';

  static const String _tokenKey = 'sessionToken';
  static const String _usernameKey = 'username';
  static const String _userIdKey = 'userId';
  static const String _userRoleKey = 'userRole';
  static const String _userEmailKey = 'userEmail';
  static const String _userProfilePicKey = 'userProfilePic';
  static const String _userDetailsKey = 'userDetails';
  static const String _userTypeKey = 'userType';
  static const String _accountEmailKey = 'accountEmail';
  static const String _accountPasswordKey = 'accountPassword';
  static const String _accountNameKey = 'accountName';
  static const String _legacyPasswordKey = 'password';
  static const String _motherApiBaseUrlKey = 'motherApiBaseUrl';
  static const String _motherApiBaseUrlsKey = 'motherApiBaseUrls';
  static const String _motherApiLastMotherIdKey = 'motherApiLastMotherId';
  static const String _discoveryMagic = 'MOTHER_DISCOVERY_V1';
  static const String _discoveryToken = 'mother-discovery-v1';
  static const String _discoverType = 'discover_mother';
  static const String _helloType = 'mother_hello';
  static const int _discoveryPort = 42109;
  final _db = LocalDbService.instance;

  Future<void> setMotherApiBaseUrl(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = value.trim();
    if (normalized.isEmpty) {
      await prefs.remove(_motherApiBaseUrlKey);
      return;
    }
    final resolved = _normalizeBaseUrl(normalized);
    await prefs.setString(_motherApiBaseUrlKey, resolved);
    await _rememberMotherApiBaseUrl(resolved);
  }

  Future<String?> getMotherApiBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = (prefs.getString(_motherApiBaseUrlKey) ?? '').trim();
    return baseUrl.isEmpty ? null : baseUrl;
  }

  Future<List<String>> getSavedMotherApiBaseUrls() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_motherApiBaseUrlsKey) ?? const <String>[];
    final urls = raw.map(_normalizeBaseUrl).where((e) => e.isNotEmpty).toList();
    return urls.toSet().toList();
  }

  Future<String?> resolveMotherApiBaseUrl({
    Duration discoveryTimeout = const Duration(seconds: 4),
  }) async {
    final discovered = await discoverMotherApiBaseUrl(timeout: discoveryTimeout);
    if (discovered != null) {
      await setMotherApiBaseUrl(discovered);
      return discovered;
    }

    final saved = await getSavedMotherApiBaseUrls();
    for (final url in saved) {
      if (await _verifyMotherApiBaseUrl(url)) {
        await setMotherApiBaseUrl(url);
        return url;
      }
    }
    return null;
  }

  Future<String?> discoverMotherApiBaseUrl({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      final completer = Completer<String?>();
      final timer = Timer(timeout, () {
        if (!completer.isCompleted) completer.complete(null);
      });

      socket.listen((event) async {
        if (event != RawSocketEvent.read) return;
        final datagram = socket?.receive();
        if (datagram == null) return;
        final text = utf8.decode(datagram.data, allowMalformed: true).trim();
        if (text.isEmpty) return;
        Map<String, dynamic> body;
        try {
          final decoded = jsonDecode(text);
          if (decoded is! Map<String, dynamic>) return;
          body = decoded;
        } catch (_) {
          return;
        }
        String? candidate;
        if ((body['type'] ?? '').toString().trim() == _helloType &&
            (body['token'] ?? '').toString().trim() == _discoveryToken) {
          final baseUrl = (body['baseUrl'] ?? '').toString().trim();
          if (baseUrl.isNotEmpty) {
            candidate = _normalizeBaseUrl(baseUrl);
          }
        } else if ((body['type'] ?? '').toString().trim() == _discoveryMagic) {
          // Backward compatibility with previous discovery payload format.
          final port = (body['port'] as num?)?.toInt();
          if (port != null && port > 0) {
            candidate = 'http://${datagram.address.address}:$port';
          }
        }
        if (candidate == null || candidate.isEmpty) return;
        final ok = await _verifyMotherApiBaseUrl(candidate);
        if (!ok || completer.isCompleted) return;
        completer.complete(candidate);
      });

      socket.send(
        utf8.encode(
          jsonEncode({
            'type': _discoverType,
            'token': _discoveryToken,
          }),
        ),
        InternetAddress('255.255.255.255'),
        _discoveryPort,
      );

      final found = await completer.future;
      timer.cancel();
      return found;
    } catch (_) {
      return null;
    } finally {
      socket?.close();
    }
  }

  Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    String? name,
    bool forceLocal = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedEmail = email.trim().toLowerCase();
    final motherBaseUrl =
        forceLocal ? null : await getMotherApiBaseUrl();

    if (motherBaseUrl != null) {
      try {
        final response = await http
            .post(
              Uri.parse('$motherBaseUrl/auth/signup'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'email': normalizedEmail,
                'password': password,
                'name': (name == null || name.trim().isEmpty)
                    ? 'Veneranda Shop Owner'
                    : name.trim(),
              }),
            )
            .timeout(const Duration(seconds: 8));
        final data = _decodeJson(response.body);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return {
            'success': true,
            'message':
                (data['message'] ?? 'Signup submitted to mother app.').toString(),
          };
        }
        return {
          'success': false,
          'message': (data['message'] ?? 'Signup failed.').toString(),
        };
      } on SocketException {
        return {
          'success': false,
          'message': 'Cannot reach mother API. Check hotspot and URL.',
        };
      } on http.ClientException {
        return {
          'success': false,
          'message': 'Cannot reach mother API. Check hotspot and URL.',
        };
      } on TimeoutException {
        return {
          'success': false,
          'message': 'Mother API request timed out.',
        };
      } catch (_) {
        return {
          'success': false,
          'message': 'Signup failed due to server error.',
        };
      }
    }

    // Persist account credentials locally for future logins.
    await prefs.setString(_accountEmailKey, normalizedEmail);
    await prefs.setString(_accountPasswordKey, password);

    final displayName = (name == null || name.trim().isEmpty)
        ? 'Veneranda Shop Owner'
        : name.trim();
    await prefs.setString(_accountNameKey, displayName);
    await _db.upsertAuthAccount(
      email: normalizedEmail,
      password: password,
      name: displayName,
    );

    // Ensure signup does not auto-login. Clear only active session keys.
    await prefs.remove(_tokenKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_userDetailsKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userRoleKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userProfilePicKey);
    await prefs.remove(_userTypeKey);

    return {
      'success': true,
      'data': {
        'user': {
          'username': displayName,
          'email': normalizedEmail,
          'role': 'ADMIN',
        },
        'userType': 'LOCAL',
      },
      'userRole': 'ADMIN',
      'userType': 'LOCAL',
    };
  }

  Future<Map<String, dynamic>> login(
    String email,
    String password, {
    bool forceLocal = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedEmail = email.trim().toLowerCase();
    final motherBaseUrl =
        forceLocal ? null : await getMotherApiBaseUrl();
    String? remoteFailureMessage;

    // Prefer local credentials when they match (avoids unnecessary HTTP on mother).
    final localLogin = await _tryLocalLogin(
      prefs: prefs,
      normalizedEmail: normalizedEmail,
      password: password,
    );
    if (localLogin != null) {
      return localLogin;
    }

    if (motherBaseUrl != null) {
      try {
        final response = await http
            .post(
              Uri.parse('$motherBaseUrl/auth/login'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'email': normalizedEmail,
                'password': password,
              }),
            )
            .timeout(const Duration(seconds: 8));
        final data = _decodeJson(response.body);
        if (response.statusCode == 403) {
          remoteFailureMessage =
              (data['message'] ?? _pendingRemoteApprovalLoginMessage).toString();
        } else if (response.statusCode >= 200 && response.statusCode < 300) {
          final token = (data['token'] ?? '').toString();
          final user = data['user'] is Map<String, dynamic>
              ? (data['user'] as Map<String, dynamic>)
              : <String, dynamic>{};
          final userName = (user['name'] ?? 'Remote User').toString();
          final userEmail = (user['email'] ?? normalizedEmail)
              .toString()
              .trim()
              .toLowerCase();
          final userRole = (user['role'] ?? 'STAFF').toString().toUpperCase();
          final userProfilePic = (user['profilePic'] ?? '').toString().trim();
          if (token.isEmpty) {
            return {
              'success': false,
              'message': 'Mother API returned an invalid token.',
            };
          }
          await _saveToken(token);
          await _saveUsername(userName);
          await _saveUserEmail(userEmail);
          await _saveUserRole(userRole);
          await _saveUserType('REMOTE');
          await prefs.setString(_userProfilePicKey, userProfilePic);
          await _saveUserDetails(jsonEncode({
            'username': userName,
            'email': userEmail,
            'role': userRole,
            'profilePic': userProfilePic,
          }));
          return {
            'success': true,
            'data': {
              'user': {
                'username': userName,
                'email': userEmail,
                'role': userRole,
                'profilePic': userProfilePic,
              },
              'userType': 'REMOTE',
            },
            'userRole': userRole,
            'userType': 'REMOTE',
          };
        } else {
          remoteFailureMessage =
              (data['message'] ?? 'Login failed.').toString();
        }
      } on SocketException {
        remoteFailureMessage = 'Cannot reach mother API. Check hotspot and URL.';
      } on http.ClientException {
        remoteFailureMessage = 'Cannot reach mother API. Check hotspot and URL.';
      } on TimeoutException {
        remoteFailureMessage = 'Mother API request timed out.';
      } catch (_) {
        remoteFailureMessage = 'Login failed due to server error.';
      }
    }

    if (remoteFailureMessage != null) {
      return {
        'success': false,
        'message': remoteFailureMessage,
      };
    }

    return {
      'success': false,
      'message': 'Invalid email or password',
    };
  }

  Future<Map<String, dynamic>> resetPassword({
    required String email,
    required String newPassword,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty || newPassword.isEmpty) {
      return {'success': false, 'message': 'Email and new password are required.'};
    }
    final motherBaseUrl = await getMotherApiBaseUrl();
    if (motherBaseUrl != null) {
      try {
        final response = await http
            .post(
              Uri.parse('$motherBaseUrl/auth/reset-password'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'email': normalizedEmail,
                'newPassword': newPassword,
              }),
            )
            .timeout(const Duration(seconds: 8));
        final data = _decodeJson(response.body);
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return {
            'success': true,
            'message': (data['message'] ?? 'Password reset successful.').toString(),
          };
        }
        return {
          'success': false,
          'message': (data['message'] ?? 'Password reset failed.').toString(),
        };
      } catch (_) {
        // fall back to local reset path
      }
    }
    final updated = await _db.updateAuthPasswordByEmail(
      email: normalizedEmail,
      newPassword: newPassword,
    );
    if (updated > 0) {
      return {'success': true, 'message': 'Password reset successful.'};
    }
    return {'success': false, 'message': 'Account not found.'};
  }

  Future<Map<String, dynamic>?> _tryLocalLogin({
    required SharedPreferences prefs,
    required String normalizedEmail,
    required String password,
  }) async {
    final dbAccount = await _db.getAuthAccountByEmail(normalizedEmail);
    String savedEmail;
    String savedPassword;
    String savedName;

    if (dbAccount != null) {
      savedEmail = dbAccount['email'] ?? normalizedEmail;
      savedPassword = dbAccount['password'] ?? '';
      savedName = dbAccount['name'] ?? 'Shop Admin';
    } else {
      savedEmail = (prefs.getString(_accountEmailKey) ??
              prefs.getString(_userEmailKey) ??
              'admin@shop.com')
          .trim()
          .toLowerCase();
      savedPassword =
          prefs.getString(_accountPasswordKey) ??
              prefs.getString(_legacyPasswordKey) ??
              '123456';
      savedName = prefs.getString(_accountNameKey) ?? 'Shop Admin';
    }

    if (normalizedEmail != savedEmail || password != savedPassword) {
      return null;
    }

    await _db.upsertAuthAccount(
      email: savedEmail,
      password: savedPassword,
      name: savedName,
    );
    await prefs.setString(_accountEmailKey, savedEmail);
    await prefs.setString(_accountPasswordKey, savedPassword);
    await prefs.setString(_accountNameKey, savedName);

    await _saveToken('local-token-${DateTime.now().millisecondsSinceEpoch}');
    await _saveUsername(savedName);
    await _saveUserEmail(savedEmail);
    await _saveUserRole('ADMIN');
    await _saveUserType('LOCAL');
    await _saveUserDetails(
      '{"username":"$savedName","email":"$savedEmail","role":"ADMIN"}',
    );

    return {
      'success': true,
      'data': {
        'user': {
          'username': savedName,
          'email': savedEmail,
          'role': 'ADMIN',
        },
        'userType': 'LOCAL',
      },
      'userRole': 'ADMIN',
      'userType': 'LOCAL',
    };
  }

  Future<void> _saveToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
  }

  Future<void> _saveUsername(String username) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_usernameKey, username);
  }

  Future<void> _saveUserDetails(String userDetails) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userDetailsKey, userDetails);
  }

  Future<void> _saveUserRole(String userRole) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userRoleKey, userRole);
  }

  Future<void> _saveUserEmail(String userEmail) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userEmailKey, userEmail);
  }

  Future<void> _saveUserType(String userType) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userTypeKey, userType);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_usernameKey);
  }

  Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userRoleKey);
  }

  Future<String?> getUserType() async {
    final prefs = await SharedPreferences.getInstance();
    final value = (prefs.getString(_userTypeKey) ?? '').trim();
    return value.isEmpty ? null : value.toUpperCase();
  }

  Future<Map<String, dynamic>?> getUserDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final userDetailsJson = prefs.getString(_userDetailsKey);
    if (userDetailsJson != null) {
      return jsonDecode(userDetailsJson);
    }
    return null;
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<bool> hasAnyAccount() async {
    final hasDbAccount = await _db.hasAnyAuthAccount();
    return hasDbAccount;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_userDetailsKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userRoleKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userProfilePicKey);
    await prefs.remove(_userTypeKey);
  }

  String _normalizeBaseUrl(String raw) {
    var value = raw.trim();
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    return value.endsWith('/') ? value.substring(0, value.length - 1) : value;
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<Map<String, String>> getCurrentProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final isRemote = await isRemoteUser();
    if (isRemote) {
      final remoteProfile = await _getRemoteAuthorized('/auth/me');
      final remoteUser = remoteProfile?['user'];
      if (remoteUser is Map) {
        final remoteName = (remoteUser['name'] ?? '').toString().trim();
        final remoteEmail = (remoteUser['email'] ?? '').toString().trim().toLowerCase();
        final remoteRole = (remoteUser['role'] ?? '').toString().trim().toUpperCase();
        final remoteProfilePic = (remoteUser['profilePic'] ?? '').toString().trim();
        if (remoteName.isNotEmpty) await prefs.setString(_usernameKey, remoteName);
        if (remoteEmail.isNotEmpty) await prefs.setString(_userEmailKey, remoteEmail);
        if (remoteProfilePic.isNotEmpty || prefs.containsKey(_userProfilePicKey)) {
          await prefs.setString(_userProfilePicKey, remoteProfilePic);
        }
        await prefs.setString(
          _userDetailsKey,
          jsonEncode({
            'username': remoteName,
            'email': remoteEmail,
            'role': remoteRole.isEmpty ? 'STAFF' : remoteRole,
            'profilePic': remoteProfilePic,
          }),
        );
      }
    }
    final email = (isRemote
            ? (prefs.getString(_userEmailKey) ?? prefs.getString(_accountEmailKey) ?? '')
            : (prefs.getString(_accountEmailKey) ?? prefs.getString(_userEmailKey) ?? ''))
        .trim()
        .toLowerCase();
    final dbAccount = email.isEmpty ? null : await _db.getAuthAccountByEmail(email);
    final name = dbAccount?['name'] ??
        prefs.getString(_accountNameKey) ??
        prefs.getString(_usernameKey) ??
        'Shop Admin';
    final password = dbAccount?['password'] ??
        prefs.getString(_accountPasswordKey) ??
        prefs.getString(_legacyPasswordKey) ??
        '';
    final resolvedEmail = (dbAccount?['email'] ?? email).trim().toLowerCase();
    final profilePic = prefs.getString(_userProfilePicKey) ?? '';
    return {
      'name': name,
      'email': resolvedEmail,
      'password': password,
      'profilePic': profilePic,
    };
  }

  Future<(bool ok, String message)> updateProfile({
    required String name,
    required String email,
    String? newPassword,
    String? profilePic,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final normalizedEmail = email.trim().toLowerCase();
    final trimmedName = name.trim();
    if (trimmedName.isEmpty) return (false, 'Name is required.');
    if (normalizedEmail.isEmpty) return (false, 'Email is required.');

    if (await isRemoteUser()) {
      final response = await _postRemoteAuthorized('/auth/profile', {
        'name': trimmedName,
        'email': normalizedEmail,
        'profilePic': (profilePic ?? '').trim(),
      });
      if (!response.$1) return response;
      await prefs.setString(_usernameKey, trimmedName);
      await prefs.setString(_userEmailKey, normalizedEmail);
      if (profilePic != null) {
        await prefs.setString(_userProfilePicKey, profilePic.trim());
      }
      final role = (await getUserRole() ?? 'STAFF').toUpperCase();
      await prefs.setString(
        _userDetailsKey,
        jsonEncode({
          'username': trimmedName,
          'email': normalizedEmail,
          'role': role,
          'profilePic': (profilePic ?? '').trim(),
        }),
      );
      return (true, 'Profile updated successfully.');
    }

    final oldEmail = (prefs.getString(_accountEmailKey) ??
            prefs.getString(_userEmailKey) ??
            '')
        .trim()
        .toLowerCase();
    final currentPassword =
        prefs.getString(_accountPasswordKey) ?? prefs.getString(_legacyPasswordKey) ?? '';
    final updatedPassword =
        (newPassword == null || newPassword.isEmpty) ? currentPassword : newPassword;

    try {
      if (oldEmail.isNotEmpty) {
        final updatedRows = await _db.updateAuthAccountByEmail(
          oldEmail: oldEmail,
          newEmail: normalizedEmail,
          password: updatedPassword,
          name: trimmedName,
        );
        if (updatedRows == 0) {
          await _db.upsertAuthAccount(
            email: normalizedEmail,
            password: updatedPassword,
            name: trimmedName,
          );
        }
      } else {
        await _db.upsertAuthAccount(
          email: normalizedEmail,
          password: updatedPassword,
          name: trimmedName,
        );
      }

      await prefs.setString(_accountEmailKey, normalizedEmail);
      await prefs.setString(_accountPasswordKey, updatedPassword);
      await prefs.setString(_accountNameKey, trimmedName);
      await prefs.setString(_usernameKey, trimmedName);
      await prefs.setString(_userEmailKey, normalizedEmail);
      if (profilePic != null) {
        await prefs.setString(_userProfilePicKey, profilePic.trim());
      }
      await prefs.setString(
        _userDetailsKey,
        '{"username":"$trimmedName","email":"$normalizedEmail","role":"ADMIN"}',
      );
      return (true, 'Profile updated successfully.');
    } catch (_) {
      return (false, 'Failed to update profile.');
    }
  }

  Future<(bool ok, String message)> createRemoteTransaction({
    required String description,
    required double amount,
  }) async {
    if (!await isRemoteUser()) {
      return (true, 'Saved on this device.');
    }
    final baseUrl = await getMotherApiBaseUrl();
    if (baseUrl == null) return (true, 'Remote API not configured.');
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return (false, 'Missing remote token. Please sign in again.');
    }
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/transactions'),
            headers: {
              'Content-Type': 'application/json',
              HttpHeaders.authorizationHeader: 'Bearer $token',
            },
            body: jsonEncode({
              'description': description.trim(),
              'amount': amount,
            }),
          )
          .timeout(const Duration(seconds: 8));
      final data = _decodeJson(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (true, (data['message'] ?? 'Transaction synced.').toString());
      }
      return (false, (data['message'] ?? 'Failed to sync transaction.').toString());
    } on SocketException {
      return (false, 'Cannot reach mother API for transaction sync.');
    } on http.ClientException {
      return (false, 'Cannot reach mother API for transaction sync.');
    } on TimeoutException {
      return (false, 'Transaction sync timed out.');
    } catch (_) {
      return (false, 'Transaction sync failed.');
    }
  }

  Future<bool> isRemoteUser() async {
    return (await getUserType()) == 'REMOTE';
  }

  Future<(bool ok, String message)> saveRemoteStore({
    int? id,
    required String name,
    String? description,
    bool isDefault = false,
  }) async {
    return _postRemoteAuthorized('/stores', {
      'id': ?id,
      'name': name.trim(),
      'description': (description ?? '').trim(),
      'isDefault': isDefault,
    });
  }

  Future<(bool ok, String message)> saveRemoteClient({
    int? id,
    int? storeId,
    required String name,
    String? phone,
    String? address,
  }) async {
    return _postRemoteAuthorized('/clients', {
      'id': ?id,
      'storeId': ?storeId,
      'name': name.trim(),
      'phone': (phone ?? '').trim(),
      'address': (address ?? '').trim(),
    });
  }

  Future<(bool ok, String message)> saveRemoteItem(Map<String, Object?> payload) async {
    return _postRemoteAuthorized('/items', payload);
  }

  Future<(bool ok, String message)> deleteRemoteItem(int id) async {
    return _postRemoteAuthorized('/items/delete', {'id': id});
  }

  Future<(bool ok, String message)> saveRemoteUnit({
    int? id,
    required String unitName,
    required String unitShortName,
  }) async {
    return _postRemoteAuthorized('/units', {
      'id': ?id,
      'unitName': unitName.trim(),
      'unitShortName': unitShortName.trim(),
    });
  }

  Future<(bool ok, String message)> deleteRemoteUnit(int id) async {
    return _postRemoteAuthorized('/units/delete', {'id': id});
  }

  Future<List<String>> fetchRemoteItemCategories({
    required String type,
  }) async {
    final normalized = type.trim().toLowerCase();
    if (normalized != 'sale' && normalized != 'business') {
      return const <String>[];
    }
    final data = await _getRemoteAuthorized('/item-categories?type=$normalized');
    if (data == null) return const <String>[];
    final rows = data['data'];
    if (rows is! List) return const <String>[];
    return rows
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<(bool ok, String message)> saveRemoteItemCategory({
    required String type,
    required String name,
    String? oldName,
  }) async {
    final normalizedType = type.trim().toLowerCase();
    return _postRemoteAuthorized('/item-categories?type=$normalizedType', {
      'name': name.trim(),
      'oldName': (oldName ?? '').trim(),
    });
  }

  Future<(bool ok, String message)> deleteRemoteItemCategory({
    required String type,
    required String name,
  }) async {
    final normalizedType = type.trim().toLowerCase();
    return _postRemoteAuthorized('/item-categories/delete', {
      'type': normalizedType,
      'name': name.trim(),
    });
  }

  Future<(bool ok, String message)> receiveRemoteStock(Map<String, Object?> payload) async {
    return _postRemoteAuthorized('/stock/receive', payload);
  }

  Future<(bool ok, String message)> adjustRemoteStock(
    Map<String, Object?> payload,
  ) async {
    return _postRemoteAuthorized('/stock/adjust', payload);
  }

  Future<(bool ok, String message)> saveRemoteStockTransfer(
    Map<String, Object?> payload,
  ) async {
    return _postRemoteAuthorized('/stock/transfers', payload);
  }

  Future<(bool ok, String message)> createRemoteSale(Map<String, Object?> payload) async {
    return _postRemoteAuthorized('/sales', payload);
  }

  Future<(bool ok, String message)> deleteRemoteSale(int id) async {
    return _postRemoteAuthorized('/sales/delete', {'id': id});
  }

  Future<(bool ok, String message)> saveRemoteExpense({
    int? id,
    int? storeId,
    required String title,
    String? category,
    String? paidBy,
    String? receivedBy,
    String? notes,
    required double amount,
    DateTime? createdAt,
  }) async {
    return _postRemoteAuthorized('/expenses', {
      'id': ?id,
      'storeId': ?storeId,
      'title': title.trim(),
      'category': (category ?? '').trim(),
      'paidBy': (paidBy ?? '').trim(),
      'receivedBy': (receivedBy ?? '').trim(),
      'notes': (notes ?? '').trim(),
      'amount': amount,
      if (createdAt != null) 'createdAt': createdAt.toIso8601String(),
    });
  }

  Future<(bool ok, String message)> deleteRemoteExpense(int id) async {
    return _postRemoteAuthorized('/expenses/delete', {'id': id});
  }

  Future<(bool ok, String message)> saveRemoteService({
    int? id,
    int? storeId,
    required String title,
    String? notes,
    required double amount,
    DateTime? createdAt,
  }) async {
    return _postRemoteAuthorized('/services', {
      'id': ?id,
      'storeId': ?storeId,
      'title': title.trim(),
      'notes': (notes ?? '').trim(),
      'amount': amount,
      if (createdAt != null) 'createdAt': createdAt.toIso8601String(),
    });
  }

  Future<(bool ok, String message)> deleteRemoteService(int id) async {
    return _postRemoteAuthorized('/services/delete', {'id': id});
  }

  Future<(bool ok, String message, double? remaining)> payRemoteDebt({
    required String customerName,
    required double amount,
    int? clientId,
    bool useClientAccount = false,
  }) async {
    if (!await isRemoteUser()) {
      return (false, 'Local account: debt is updated on this device only.', null);
    }
    final baseUrl = await getMotherApiBaseUrl();
    if (baseUrl == null) return (true, 'Remote API not configured.', null);
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return (false, 'Missing remote token. Please sign in again.', null);
    }
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/debts/pay'),
            headers: {
              'Content-Type': 'application/json',
              HttpHeaders.authorizationHeader: 'Bearer $token',
            },
            body: jsonEncode({
              'customerName': customerName.trim(),
              'amount': amount,
              'clientId': ?clientId,
              'useClientAccount': useClientAccount,
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = _decodeJson(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final remaining = (data['remaining'] as num?)?.toDouble();
        return (true, (data['message'] ?? 'Debt payment saved').toString(), remaining);
      }
      return (false, (data['message'] ?? 'Remote debt payment failed').toString(), null);
    } on SocketException {
      return (false, 'Cannot reach mother API.', null);
    } on http.ClientException {
      return (false, 'Cannot reach mother API.', null);
    } on TimeoutException {
      return (false, 'Mother API request timed out.', null);
    } catch (_) {
      return (false, 'Remote debt payment failed.', null);
    }
  }

  Future<double?> fetchRemoteClientAccountBalance(int clientId) async {
    final data = await _getRemoteAuthorized('/clients/account?clientId=$clientId');
    if (data == null) return null;
    return (data['balance'] as num?)?.toDouble();
  }

  /// Ledger rows for [clientId] (same shape as [LocalDbService.getClientAccountTransactions]).
  Future<List<Map<String, Object?>>> fetchRemoteClientAccountTransactions(
    int clientId,
  ) async {
    return _extractMapList(
      await _getRemoteAuthorized(
        '/clients/account/transactions?clientId=$clientId',
      ),
    );
  }

  Future<List<Loan>> fetchRemoteLoans() async {
    final data = await _getRemoteAuthorized('/loans');
    if (data == null) return const <Loan>[];
    final rows = data['data'];
    if (rows is! List) return const <Loan>[];
    final out = <Loan>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        out.add(Loan.fromMap(row));
      } else if (row is Map) {
        out.add(Loan.fromMap(Map<String, dynamic>.from(row)));
      }
    }
    return out;
  }

  Future<(bool ok, String message)> saveRemoteLoan(
    Map<String, dynamic> body,
  ) async {
    return _postRemoteAuthorized('/loans', body);
  }

  Future<List<Map<String, Object?>>> fetchRemoteLoanPayments({
    int? loanId,
    int? clientId,
  }) async {
    final params = <String>[];
    if (loanId != null) params.add('loanId=$loanId');
    if (clientId != null) params.add('clientId=$clientId');
    final suffix = params.isEmpty ? '' : '?${params.join('&')}';
    return _extractMapList(
      await _getRemoteAuthorized('/loans/payments$suffix'),
    );
  }

  Future<(bool ok, String message)> postRemoteLoanPayment({
    required int loanId,
    required int clientId,
    required double amount,
    int? storeId,
    String? note,
  }) async {
    final result = await _postRemoteAuthorized('/loans/payments', {
      'loanId': loanId,
      'clientId': clientId,
      'amount': amount,
      'storeId': ?storeId,
      'note': (note ?? '').trim(),
    });
    return result;
  }

  Future<(bool ok, String message)> postRemoteClientAccountTransaction({
    required int clientId,
    required double amount,
    required String transactionType,
    String? note,
  }) async {
    return _postRemoteAuthorized('/clients/account/transaction', {
      'clientId': clientId,
      'amount': amount,
      'transactionType': transactionType.trim(),
      'note': (note ?? '').trim(),
    });
  }

  Future<List<Item>> fetchRemoteItems() async {
    final data = await _getRemoteAuthorized('/items');
    if (data == null) return const <Item>[];
    final rows = data['data'];
    if (rows is! List) return const <Item>[];
    final result = <Item>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        result.add(Item.fromMap(row));
      } else if (row is Map) {
        result.add(Item.fromMap(Map<String, dynamic>.from(row)));
      }
    }
    return result;
  }

  Future<List<Store>> fetchRemoteStores() async {
    final data = await _getRemoteAuthorized('/stores');
    if (data == null) return const <Store>[];
    final rows = data['data'];
    if (rows is! List) return const <Store>[];
    final result = <Store>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        result.add(Store.fromMap(row));
      } else if (row is Map) {
        result.add(Store.fromMap(Map<String, dynamic>.from(row)));
      }
    }
    return result;
  }

  Future<List<Unit>> fetchRemoteUnits() async {
    final data = await _getRemoteAuthorized('/units');
    if (data == null) return const <Unit>[];
    final rows = data['data'];
    if (rows is! List) return const <Unit>[];
    final result = <Unit>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        result.add(Unit.fromMap(row));
      } else if (row is Map) {
        result.add(Unit.fromMap(Map<String, dynamic>.from(row)));
      }
    }
    return result;
  }

  Future<List<Client>> fetchRemoteClients() async {
    final data = await _getRemoteAuthorized('/clients');
    if (data == null) return const <Client>[];
    final rows = data['data'];
    if (rows is! List) return const <Client>[];
    final result = <Client>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        result.add(Client.fromMap(row));
      } else if (row is Map) {
        result.add(Client.fromMap(Map<String, dynamic>.from(row)));
      }
    }
    return result;
  }

  Future<List<Map<String, Object?>>> fetchRemoteSalesHistory({
    DateTime? start,
    DateTime? end,
  }) async {
    final queryParts = <String>[];
    if (start != null) {
      queryParts.add('start=${Uri.encodeQueryComponent(start.toIso8601String())}');
    }
    if (end != null) {
      queryParts.add('end=${Uri.encodeQueryComponent(end.toIso8601String())}');
    }
    final suffix = queryParts.isEmpty ? '' : '?${queryParts.join('&')}';
    return _extractMapList(await _getRemoteAuthorized('/sales/history$suffix'));
  }

  Future<List<Debt>> fetchRemoteDebts({bool? isPaid}) async {
    final suffix = isPaid == null
        ? ''
        : '?isPaid=${isPaid ? 'true' : 'false'}';
    final data = await _getRemoteAuthorized('/debts$suffix');
    if (data == null) return const <Debt>[];
    final rows = data['data'];
    if (rows is! List) return const <Debt>[];
    return rows
        .map((e) => e is Map<String, dynamic>
            ? Debt.fromMap(e)
            : Debt.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<DebtPayment>> fetchRemoteDebtPayments({
    String? customerName,
  }) async {
    final name = (customerName ?? '').trim();
    final suffix = name.isEmpty
        ? ''
        : '?customerName=${Uri.encodeQueryComponent(name)}';
    final data = await _getRemoteAuthorized('/debt-payments$suffix');
    if (data == null) return const <DebtPayment>[];
    final rows = data['data'];
    if (rows is! List) return const <DebtPayment>[];
    return rows
        .map((e) => e is Map<String, dynamic>
            ? DebtPayment.fromMap(e)
            : DebtPayment.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Expense>> fetchRemoteExpenses() async {
    final data = await _getRemoteAuthorized('/expenses');
    if (data == null) return const <Expense>[];
    final rows = data['data'];
    if (rows is! List) return const <Expense>[];
    return rows
        .map((e) => e is Map<String, dynamic>
            ? Expense.fromMap(e)
            : Expense.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<ServiceTransaction>> fetchRemoteServices() async {
    final data = await _getRemoteAuthorized('/services');
    if (data == null) return const <ServiceTransaction>[];
    final rows = data['data'];
    if (rows is! List) return const <ServiceTransaction>[];
    return rows
        .map((e) => e is Map<String, dynamic>
            ? ServiceTransaction.fromMap(e)
            : ServiceTransaction.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  Future<List<Map<String, Object?>>> fetchRemoteStockReceipts() async {
    return _extractMapList(await _getRemoteAuthorized('/stock/receipts'));
  }

  Future<(bool ok, String message)> deleteRemoteStockReceipt(int id) async {
    return _postRemoteAuthorized('/stock/receipts/delete', {'id': id});
  }

  Future<List<Map<String, Object?>>> fetchRemoteStockTransfers() async {
    return _extractMapList(await _getRemoteAuthorized('/stock/transfers'));
  }

  Future<List<Map<String, Object?>>> fetchRemoteItemTransactions(
    int itemId,
  ) async {
    if (itemId <= 0) return const <Map<String, Object?>>[];
    final encodedItemId = Uri.encodeQueryComponent(itemId.toString());
    return _extractMapList(
      await _getRemoteAuthorized('/items/transactions?itemId=$encodedItemId'),
    );
  }

  Future<(bool ok, String message)> _postRemoteAuthorized(
    String path,
    Map<String, Object?> payload,
  ) async {
    if (!await isRemoteUser()) {
      return (false, 'Local account: data is stored on this device only.');
    }
    final baseUrl = await getMotherApiBaseUrl();
    if (baseUrl == null) return (true, 'Remote API not configured.');
    final token = await getToken();
    if (token == null || token.isEmpty) {
      return (false, 'Missing remote token. Please sign in again.');
    }
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl$path'),
            headers: {
              'Content-Type': 'application/json',
              HttpHeaders.authorizationHeader: 'Bearer $token',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 10));
      final data = _decodeJson(response.body);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return (true, (data['message'] ?? 'Synced to mother').toString());
      }
      return (false, (data['message'] ?? 'Remote sync failed').toString());
    } on SocketException {
      return (false, 'Cannot reach mother API.');
    } on http.ClientException {
      return (false, 'Cannot reach mother API.');
    } on TimeoutException {
      return (false, 'Mother API request timed out.');
    } catch (_) {
      return (false, 'Remote sync failed.');
    }
  }

  Future<Map<String, dynamic>?> _getRemoteAuthorized(String path) async {
    if (!await isRemoteUser()) return null;
    final baseUrl = await getMotherApiBaseUrl();
    if (baseUrl == null) return null;
    final token = await getToken();
    if (token == null || token.isEmpty) return null;
    try {
      final response = await http
          .get(
            Uri.parse('$baseUrl$path'),
            headers: {HttpHeaders.authorizationHeader: 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return null;
      }
      return _decodeJson(response.body);
    } catch (_) {
      return null;
    }
  }

  Future<void> _rememberMotherApiBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_motherApiBaseUrlsKey) ?? <String>[];
    final normalized = _normalizeBaseUrl(url);
    final next = <String>[normalized, ...current.where((e) => e != normalized)];
    if (next.length > 10) {
      next.removeRange(10, next.length);
    }
    await prefs.setStringList(_motherApiBaseUrlsKey, next);
  }

  Future<bool> _verifyMotherApiBaseUrl(String baseUrl) async {
    final normalized = _normalizeBaseUrl(baseUrl);
    try {
      final response = await http
          .get(Uri.parse('$normalized/health'))
          .timeout(const Duration(seconds: 2));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final body = _decodeJson(response.body);
      if ((body['ok'] as bool?) != true) return false;
      final motherId = (body['motherId'] ?? '').toString().trim();
      if (motherId.isEmpty) return false;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_motherApiLastMotherIdKey, motherId);
      await _rememberMotherApiBaseUrl(normalized);
      return true;
    } catch (_) {
      return false;
    }
  }

  List<Map<String, Object?>> _extractMapList(Map<String, dynamic>? payload) {
    if (payload == null) return const <Map<String, Object?>>[];
    final rows = payload['data'];
    if (rows is! List) return const <Map<String, Object?>>[];
    final result = <Map<String, Object?>>[];
    for (final row in rows) {
      if (row is Map<String, dynamic>) {
        result.add(Map<String, Object?>.from(row));
      } else if (row is Map) {
        result.add(Map<String, Object?>.from(row));
      }
    }
    return result;
  }
}

