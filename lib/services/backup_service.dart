import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'local_db_service.dart';
import 'local_device_backup_service.dart';

class BackupService {
  BackupService._();

  static final BackupService instance = BackupService._();

  static const String _kEnabledKey = 'backup_enabled';
  static const String _kDropboxTokenKey = 'backup_dropbox_token';
  static const String _kDropboxRefreshTokenKey = 'backup_dropbox_refresh_token';
  static const String _kDropboxClientIdKey = 'backup_dropbox_client_id';
  static const String _kDropboxClientSecretKey = 'backup_dropbox_client_secret';
  static const String _kDropboxTokenExpiresAtKey =
      'backup_dropbox_token_expires_at';
  static const String _kDropboxPathKey = 'backup_dropbox_path';
  static const String _kLastBackupAtKey = 'backup_last_backup_at';
  static const String _defaultDropboxPath = '/lab_app/shop_manager_latest.db';
  static const Duration _interval = Duration(minutes: 5);
  static const Duration _networkCheckInterval = Duration(seconds: 30);

  Timer? _timer;
  Timer? _networkTimer;
  bool _runningBackup = false;
  bool _hadInternet = false;

  String _dropboxErrorMessage(http.Response response) {
    if (response.statusCode == 401) {
      return 'Invalid or expired Dropbox token.';
    }
    if (response.statusCode == 409) {
      return 'Backup file not found at the Dropbox path.';
    }
    try {
      final body = jsonDecode(response.body);
      final summary = body['error_summary'] as String?;
      if (summary != null && summary.trim().isNotEmpty) {
        return 'Dropbox error: $summary';
      }
    } catch (_) {}
    return 'Dropbox request failed (${response.statusCode}).';
  }

  String _normalizeToken(String rawToken) {
    var token = rawToken.trim();
    if (token.toLowerCase().startsWith('bearer ')) {
      token = token.substring(7).trim();
    }
    if (token.length >= 2 &&
        ((token.startsWith('"') && token.endsWith('"')) ||
            (token.startsWith("'") && token.endsWith("'")))) {
      token = token.substring(1, token.length - 1).trim();
    }
    // Remove accidental spaces/newlines from copied tokens.
    token = token.replaceAll(RegExp(r'\s+'), '');
    return token;
  }

  Future<void> initialize() async {
    final online = await _hasInternet();
    _hadInternet = online;
    if (online) {
      await backupNow();
    }

    _timer ??= Timer.periodic(_interval, (_) async {
      try {
        await backupNow();
      } catch (_) {
        // Keep periodic backup loop alive even if network/API fails.
      }
    });

    _networkTimer ??= Timer.periodic(_networkCheckInterval, (_) async {
      await _checkConnectivityAndBackup();
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _networkTimer?.cancel();
    _networkTimer = null;
    LocalDeviceBackupService.instance.stopPeriodicMotherBackup();
  }

  Future<bool> _hasInternet() async {
    try {
      final result = await InternetAddress.lookup(
        'api.dropboxapi.com',
      ).timeout(const Duration(seconds: 3));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _checkConnectivityAndBackup() async {
    final online = await _hasInternet();
    if (online && !_hadInternet) {
      try {
        await backupNow();
      } catch (_) {}
    }
    _hadInternet = online;
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, value);
  }

  Future<String> getDropboxToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDropboxTokenKey) ?? '';
  }

  Future<void> setDropboxToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDropboxTokenKey, _normalizeToken(token));
  }

  Future<String> getDropboxRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDropboxRefreshTokenKey) ?? '';
  }

  Future<void> setDropboxRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDropboxRefreshTokenKey, _normalizeToken(token));
  }

  Future<String> getDropboxClientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDropboxClientIdKey) ?? '';
  }

  Future<void> setDropboxClientId(String clientId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDropboxClientIdKey, clientId.trim());
  }

  Future<String> getDropboxClientSecret() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDropboxClientSecretKey) ?? '';
  }

  Future<void> setDropboxClientSecret(String clientSecret) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDropboxClientSecretKey, clientSecret.trim());
  }

  Future<(bool ok, String message)> exchangeAuthCodeForRefreshToken({
    required String authCode,
    required String clientId,
    required String clientSecret,
  }) async {
    final normalizedCode = authCode.trim();
    final normalizedClientId = clientId.trim();
    final normalizedClientSecret = clientSecret.trim();
    if (normalizedCode.isEmpty) {
      return (false, 'Authorization code is required.');
    }
    if (normalizedClientId.isEmpty) {
      return (false, 'Dropbox app key (client id) is required.');
    }
    if (normalizedClientSecret.isEmpty) {
      return (false, 'Dropbox app secret is required.');
    }

    try {
      final response = await http.post(
        Uri.parse('https://api.dropboxapi.com/oauth2/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': normalizedClientId,
          'client_secret': normalizedClientSecret,
          'code': normalizedCode,
          'grant_type': 'authorization_code',
        },
      );

      if (response.statusCode != 200) {
        return (false, _dropboxErrorMessage(response));
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final accessToken = _normalizeToken(
        (body['access_token'] as String?) ?? '',
      );
      final refreshToken = _normalizeToken(
        (body['refresh_token'] as String?) ?? '',
      );
      final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 14400;
      if (refreshToken.isEmpty || accessToken.isEmpty) {
        return (
          false,
          'Dropbox did not return required tokens. Confirm code and app credentials.',
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kDropboxTokenKey, accessToken);
      await prefs.setString(_kDropboxRefreshTokenKey, refreshToken);
      await prefs.setString(_kDropboxClientIdKey, normalizedClientId);
      await prefs.setString(_kDropboxClientSecretKey, normalizedClientSecret);
      await prefs.setString(
        _kDropboxTokenExpiresAtKey,
        DateTime.now().add(Duration(seconds: expiresIn)).toIso8601String(),
      );
      return (true, 'Authorization code exchanged successfully.');
    } on SocketException {
      return (false, 'No internet connection.');
    } on TimeoutException {
      return (false, 'Network timeout while contacting Dropbox.');
    } catch (_) {
      return (false, 'Failed to exchange authorization code.');
    }
  }

  Future<String> _resolveDropboxAccessToken({bool forceRefresh = false}) async {
    final result = await _resolveDropboxAccessTokenDetailed(
      forceRefresh: forceRefresh,
    );
    return result.$1;
  }

  Future<(String token, String? error)> _resolveDropboxAccessTokenDetailed({
    bool forceRefresh = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    var accessToken = _normalizeToken(prefs.getString(_kDropboxTokenKey) ?? '');
    final refreshToken = _normalizeToken(
      prefs.getString(_kDropboxRefreshTokenKey) ?? '',
    );
    final clientId = (prefs.getString(_kDropboxClientIdKey) ?? '').trim();
    final clientSecret = (prefs.getString(_kDropboxClientSecretKey) ?? '')
        .trim();
    final expiresAtRaw = prefs.getString(_kDropboxTokenExpiresAtKey) ?? '';
    final expiresAt = DateTime.tryParse(expiresAtRaw);
    final stillValid =
        expiresAt != null &&
        expiresAt.isAfter(DateTime.now().add(const Duration(minutes: 1)));

    // Keep using existing token if it is still valid and refresh is not forced.
    if (!forceRefresh && accessToken.isNotEmpty && stillValid) {
      return (accessToken, null);
    }

    // If refresh credentials are present, renew access token automatically.
    if (refreshToken.isNotEmpty && clientId.isNotEmpty) {
      final body = <String, String>{
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': clientId,
      };
      if (clientSecret.isNotEmpty) {
        body['client_secret'] = clientSecret;
      }

      try {
        final response = await http.post(
          Uri.parse('https://api.dropboxapi.com/oauth2/token'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: body,
        );
        if (response.statusCode == 200) {
          final json = jsonDecode(response.body) as Map<String, dynamic>;
          final newToken = _normalizeToken(
            (json['access_token'] as String?) ?? '',
          );
          final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 14400;
          if (newToken.isNotEmpty) {
            final expiresAt = DateTime.now().add(Duration(seconds: expiresIn));
            await prefs.setString(_kDropboxTokenKey, newToken);
            await prefs.setString(
              _kDropboxTokenExpiresAtKey,
              expiresAt.toIso8601String(),
            );
            return (newToken, null);
          }
        }
        final bodyJson = jsonDecode(response.body) as Map<String, dynamic>;
        final err =
            (bodyJson['error_description'] ??
                    bodyJson['error_summary'] ??
                    bodyJson['error'])
                ?.toString();
        return (
          accessToken,
          err == null || err.isEmpty
              ? 'Failed to refresh Dropbox token (${response.statusCode}).'
              : 'Failed to refresh Dropbox token: $err',
        );
      } catch (_) {
        if (accessToken.isNotEmpty) {
          return (accessToken, 'Could not refresh token. Using saved token.');
        }
        return ('', 'Could not refresh Dropbox token. Check internet.');
      }
    }

    if (refreshToken.isNotEmpty && clientId.isEmpty) {
      return ('', 'Dropbox app key (client id) is required for refresh token.');
    }
    if (accessToken.isNotEmpty) {
      return (accessToken, null);
    }
    return ('', 'Dropbox token is missing.');
  }

  Future<String> getDropboxPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kDropboxPathKey) ?? _defaultDropboxPath;
  }

  Future<void> setDropboxPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final normalized = path.trim().isEmpty
        ? _defaultDropboxPath
        : (path.trim().startsWith('/') ? path.trim() : '/${path.trim()}');
    await prefs.setString(_kDropboxPathKey, normalized);
  }

  Future<DateTime?> getLastBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastBackupAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<bool> backupNow({bool ignoreEnabled = false}) async {
    if (_runningBackup) return false;
    _runningBackup = true;
    try {
      final cloudEnabled = await isEnabled();
      final phoneEnabled = await LocalDeviceBackupService.instance.isEnabled();
      if (!ignoreEnabled && !cloudEnabled && !phoneEnabled) return false;

      final dbPath = await LocalDbService.instance.getDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) return false;

      var localOk = false;
      try {
        final local = await LocalDeviceBackupService.instance
            .mirrorDatabaseIfEnabled(
          ignoreEnabled: ignoreEnabled,
          force: ignoreEnabled,
        );
        localOk = local.$1;
      } catch (_) {}

      if (!cloudEnabled && !ignoreEnabled) {
        return localOk;
      }

      final token = await _resolveDropboxAccessToken();
      if (token.isEmpty) {
        return localOk;
      }

      final bytes = await dbFile.readAsBytes();
      final remotePath = await getDropboxPath();
      final uri = Uri.parse('https://content.dropboxapi.com/2/files/upload');

      var response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({
            'path': remotePath,
            'mode': 'overwrite',
            'autorename': false,
            'mute': true,
            'strict_conflict': false,
          }),
        },
        body: bytes,
      );

      if (response.statusCode == 401) {
        final refreshedToken = await _resolveDropboxAccessToken(
          forceRefresh: true,
        );
        if (refreshedToken.isNotEmpty) {
          response = await http.post(
            uri,
            headers: {
              'Authorization': 'Bearer $refreshedToken',
              'Content-Type': 'application/octet-stream',
              'Dropbox-API-Arg': jsonEncode({
                'path': remotePath,
                'mode': 'overwrite',
                'autorename': false,
                'mute': true,
                'strict_conflict': false,
              }),
            },
            body: bytes,
          );
        }
      }

      if (response.statusCode != 200) {
        return localOk;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kLastBackupAtKey,
        DateTime.now().toIso8601String(),
      );
      return true;
    } catch (_) {
      return false;
    } finally {
      _runningBackup = false;
    }
  }

  Future<(bool ok, String message)> backupNowDetailed({
    bool ignoreEnabled = false,
  }) async {
    if (_runningBackup) return (false, 'Backup already running.');
    _runningBackup = true;
    try {
      final cloudEnabled = await isEnabled();
      final phoneEnabled = await LocalDeviceBackupService.instance.isEnabled();
      if (!ignoreEnabled && !cloudEnabled && !phoneEnabled) {
        return (false, 'Auto backup is disabled (cloud and phone).');
      }

      final dbPath = await LocalDbService.instance.getDatabasePath();
      final dbFile = File(dbPath);
      if (!await dbFile.exists()) {
        return (false, 'Local database file not found.');
      }

      final localResult = await LocalDeviceBackupService.instance
          .mirrorDatabaseIfEnabled(
        ignoreEnabled: ignoreEnabled,
        force: ignoreEnabled,
      );

      if (!cloudEnabled && !ignoreEnabled) {
        if (localResult.$1) {
          return (true, localResult.$2);
        }
        return (false, localResult.$2);
      }

      final resolved = await _resolveDropboxAccessTokenDetailed();
      final token = resolved.$1;
      if (token.isEmpty) {
        if (localResult.$1) {
          return (
            true,
            'Dropbox: ${resolved.$2 ?? 'token missing.'} Phone: ${localResult.$2}',
          );
        }
        return (false, resolved.$2 ?? 'Dropbox token is missing.');
      }

      final bytes = await dbFile.readAsBytes();
      final remotePath = await getDropboxPath();
      final uri = Uri.parse('https://content.dropboxapi.com/2/files/upload');
      var response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({
            'path': remotePath,
            'mode': 'overwrite',
            'autorename': false,
            'mute': true,
            'strict_conflict': false,
          }),
        },
        body: bytes,
      );
      if (response.statusCode == 401) {
        final refreshedToken = await _resolveDropboxAccessToken(
          forceRefresh: true,
        );
        if (refreshedToken.isNotEmpty) {
          response = await http.post(
            uri,
            headers: {
              'Authorization': 'Bearer $refreshedToken',
              'Content-Type': 'application/octet-stream',
              'Dropbox-API-Arg': jsonEncode({
                'path': remotePath,
                'mode': 'overwrite',
                'autorename': false,
                'mute': true,
                'strict_conflict': false,
              }),
            },
            body: bytes,
          );
        }
      }
      if (response.statusCode != 200) {
        final dropErr = _dropboxErrorMessage(response);
        if (localResult.$1) {
          return (
            true,
            'Dropbox failed ($dropErr). Phone backup: ${localResult.$2}',
          );
        }
        return (false, dropErr);
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kLastBackupAtKey,
        DateTime.now().toIso8601String(),
      );
      final phoneBit = localResult.$1 ? ' ${localResult.$2}' : '';
      return (true, 'Backup uploaded to Dropbox.$phoneBit');
    } on SocketException {
      return (false, 'No internet connection.');
    } on TimeoutException {
      return (false, 'Network timeout while contacting Dropbox.');
    } catch (_) {
      return (false, 'Unexpected backup error.');
    } finally {
      _runningBackup = false;
    }
  }

  Future<bool> hasRemoteBackup() async {
    try {
      final token = await _resolveDropboxAccessToken();
      if (token.isEmpty) return false;

      final remotePath = await getDropboxPath();
      final uri = Uri.parse('https://api.dropboxapi.com/2/files/get_metadata');
      var response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'path': remotePath}),
      );
      if (response.statusCode == 401) {
        final refreshedToken = await _resolveDropboxAccessToken(
          forceRefresh: true,
        );
        if (refreshedToken.isNotEmpty) {
          response = await http.post(
            uri,
            headers: {
              'Authorization': 'Bearer $refreshedToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'path': remotePath}),
          );
        }
      }
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<(bool ok, String message)> hasRemoteBackupDetailed() async {
    try {
      final resolved = await _resolveDropboxAccessTokenDetailed();
      final token = resolved.$1;
      if (token.isEmpty) {
        return (false, resolved.$2 ?? 'Dropbox token is missing.');
      }

      final remotePath = await getDropboxPath();
      final uri = Uri.parse('https://api.dropboxapi.com/2/files/get_metadata');
      var response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({'path': remotePath}),
      );
      if (response.statusCode == 401) {
        final refreshedToken = await _resolveDropboxAccessToken(
          forceRefresh: true,
        );
        if (refreshedToken.isNotEmpty) {
          response = await http.post(
            uri,
            headers: {
              'Authorization': 'Bearer $refreshedToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'path': remotePath}),
          );
        }
      }
      if (response.statusCode == 200) return (true, 'Backup found.');
      return (false, _dropboxErrorMessage(response));
    } on SocketException {
      return (false, 'No internet connection.');
    } on TimeoutException {
      return (false, 'Network timeout while contacting Dropbox.');
    } catch (_) {
      return (false, 'Failed to verify backup in Dropbox.');
    }
  }

  Future<bool> restoreLatestBackup() async {
    try {
      final token = await _resolveDropboxAccessToken();
      if (token.isEmpty) return false;

      final remotePath = await getDropboxPath();
      final uri = Uri.parse('https://content.dropboxapi.com/2/files/download');
      var response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Dropbox-API-Arg': jsonEncode({'path': remotePath}),
        },
      );
      if (response.statusCode == 401) {
        final refreshedToken = await _resolveDropboxAccessToken(
          forceRefresh: true,
        );
        if (refreshedToken.isNotEmpty) {
          response = await http.post(
            uri,
            headers: {
              'Authorization': 'Bearer $refreshedToken',
              'Dropbox-API-Arg': jsonEncode({'path': remotePath}),
            },
          );
        }
      }

      if (response.statusCode != 200) return false;

      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}${Platform.pathSeparator}db_restore.tmp',
      );
      await tempFile.writeAsBytes(response.bodyBytes, flush: true);

      await LocalDbService.instance.replaceDatabaseFromFile(tempFile.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<(bool ok, String message)> restoreLatestBackupDetailed() async {
    try {
      final resolved = await _resolveDropboxAccessTokenDetailed();
      final token = resolved.$1;
      if (token.isEmpty) {
        return (false, resolved.$2 ?? 'Dropbox token is missing.');
      }

      final remotePath = await getDropboxPath();
      final uri = Uri.parse('https://content.dropboxapi.com/2/files/download');
      var response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Dropbox-API-Arg': jsonEncode({'path': remotePath}),
        },
      );
      if (response.statusCode == 401) {
        final refreshedToken = await _resolveDropboxAccessToken(
          forceRefresh: true,
        );
        if (refreshedToken.isNotEmpty) {
          response = await http.post(
            uri,
            headers: {
              'Authorization': 'Bearer $refreshedToken',
              'Dropbox-API-Arg': jsonEncode({'path': remotePath}),
            },
          );
        }
      }
      if (response.statusCode != 200) {
        return (false, _dropboxErrorMessage(response));
      }

      final tempDir = Directory.systemTemp;
      final tempFile = File(
        '${tempDir.path}${Platform.pathSeparator}db_restore.tmp',
      );
      await tempFile.writeAsBytes(response.bodyBytes, flush: true);
      await LocalDbService.instance.replaceDatabaseFromFile(tempFile.path);
      return (true, 'Backup restored successfully.');
    } on SocketException {
      return (false, 'No internet connection.');
    } on TimeoutException {
      return (false, 'Network timeout while contacting Dropbox.');
    } catch (_) {
      return (false, 'Unexpected restore error.');
    }
  }

  Future<bool> restoreIfLocalMissing() async {
    final dbPath = await LocalDbService.instance.getDatabasePath();
    final localFile = File(dbPath);
    if (await localFile.exists()) {
      final size = await localFile.length();
      if (size > 0) return false;
      await localFile.delete();
    }

    if (await LocalDeviceBackupService.instance.backupFileExists()) {
      final dev = await LocalDeviceBackupService.instance.restoreFromDeviceBackup();
      if (dev.$1) return true;
    }

    final hasBackup = await hasRemoteBackup();
    if (!hasBackup) return false;
    return restoreLatestBackup();
  }

  Future<bool> hasUsableLocalDatabase() async {
    final dbPath = await LocalDbService.instance.getDatabasePath();
    final localFile = File(dbPath);
    if (!await localFile.exists()) return false;
    final size = await localFile.length();
    return size > 0;
  }
}
