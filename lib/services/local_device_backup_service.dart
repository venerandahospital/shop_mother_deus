import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'local_db_service.dart';

/// Persists a copy of the main SQLite DB under a user-visible path (e.g.
/// Downloads) so it can survive app uninstall on Android when storage access
/// is granted. Mother app only.
class LocalDeviceBackupService {
  LocalDeviceBackupService._();

  static final LocalDeviceBackupService instance = LocalDeviceBackupService._();

  static const _kEnabledKey = 'local_device_backup_enabled';
  static const _kLastBackupAtKey = 'local_device_backup_last_at';
  static const _kInstallStoragePromptDone =
      'local_device_backup_install_storage_prompt_done';

  /// Folder name under Downloads (Android/desktop) or Documents (iOS fallback).
  static const _folderName = 'VenerandaShop';

  /// Single backup file (same schema as live DB).
  static const _backupFileName =
      'shop_manager_retail_supermarket_backup.db';

  static const Duration _motherPeriodicInterval = Duration(minutes: 5);

  Timer? _motherPeriodicTimer;
  bool _mirrorRunning = false;

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabledKey) ?? true;
  }

  Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabledKey, value);
  }

  Future<DateTime?> getLastBackupAt() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLastBackupAtKey);
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _setLastBackupAt(DateTime t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastBackupAtKey, t.toIso8601String());
  }

  /// Runs [mirrorDatabaseIfEnabled] on a fixed interval for the mother app only
  /// (not remote/child users). Does not use the network.
  Future<void> startPeriodicMotherBackup() async {
    if (kIsWeb) return;
    _motherPeriodicTimer ??= Timer.periodic(_motherPeriodicInterval, (_) {
      unawaited(_runMotherPeriodicMirror());
    });
    unawaited(_runMotherPeriodicMirror());
  }

  void stopPeriodicMotherBackup() {
    _motherPeriodicTimer?.cancel();
    _motherPeriodicTimer = null;
  }

  Future<void> _runMotherPeriodicMirror() async {
    try {
      final userType = await AuthService().getUserType();
      if (userType == 'REMOTE') return;
      await mirrorDatabaseIfEnabled();
    } catch (_) {}
  }

  /// Resolves the absolute backup file path for this platform.
  Future<String?> resolveBackupFilePath() async {
    if (kIsWeb) return null;
    if (Platform.isAndroid) {
      return p.join(
        '/storage/emulated/0/Download',
        _folderName,
        _backupFileName,
      );
    }
    if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      return p.join(docs.path, _folderName, _backupFileName);
    }
    final downloads = await getDownloadsDirectory();
    if (downloads == null) return null;
    return p.join(downloads.path, _folderName, _backupFileName);
  }

  /// Human-readable hint for settings UI.
  Future<String> describeBackupLocation() async {
    final path = await resolveBackupFilePath();
    if (path == null) return 'Not available on this platform.';
    if (Platform.isAndroid) {
      return 'Download/VenerandaShop/$_backupFileName (internal storage)';
    }
    return path;
  }

  /// Shows the system storage permission flow once after install (first cold
  /// start on Android). Safe to call on every launch; no-ops when already done.
  Future<void> promptStorageAccessOnInstallIfNeeded() async {
    if (kIsWeb || !Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_kInstallStoragePromptDone) ?? false) return;
    await requestStorageAccess();
    await prefs.setBool(_kInstallStoragePromptDone, true);
  }

  /// Opens the right system UI to grant storage for Downloads backups.
  /// On Android 11+ this uses “All files access” (not the empty App info → Permissions list).
  Future<(bool opened, String message)> openStorageManagementUi() async {
    if (kIsWeb) {
      return (false, 'Not available in web.');
    }
    if (Platform.isIOS) {
      return (true, 'This device keeps backups in the app folder; no extra step needed.');
    }
    if (!Platform.isAndroid) {
      final opened = await openAppSettings();
      return (
        opened,
        opened ? 'Allow file access in Settings if prompted.' : 'Could not open Settings.',
      );
    }

    await Permission.manageExternalStorage.request();
    if (await Permission.manageExternalStorage.isGranted) {
      return (true, 'All files access is on. You can return to the app.');
    }

    final opened = await openAppSettings();
    return (
      opened,
      opened
          ? 'Turn on “All files access” for this app (or Files and media), then come back.'
          : 'Open Settings → Apps → this app → find “All files access” or Files.',
    );
  }

  /// Request storage access needed to read/write the backup on Android.
  Future<(bool granted, String message)> requestStorageAccess() async {
    if (kIsWeb) {
      return (false, 'Not available in web.');
    }
    if (Platform.isIOS) {
      return (true, 'Using app Documents folder.');
    }
    if (Platform.isAndroid) {
      // Android 13+ no longer exposes legacy storage in App info; prefer all-files first.
      final manage = await Permission.manageExternalStorage.request();
      if (manage.isGranted) {
        return (true, 'All-files access granted.');
      }
      final storage = await Permission.storage.request();
      if (storage.isGranted) {
        return (true, 'Storage access granted.');
      }
      final photos = await Permission.photos.request();
      if (photos.isGranted) {
        return (true, 'Storage access granted.');
      }
      if (storage.isPermanentlyDenied || manage.isPermanentlyDenied) {
        return (
          false,
          'Permission denied. Use “Get storage permission” to open Settings.',
        );
      }
      return (
        false,
        'Storage permission is required to save the backup on this device.',
      );
    }
    return (true, 'OK');
  }

  Future<bool> _hasLikelyWriteAccess() async {
    if (kIsWeb || Platform.isIOS) return true;
    if (Platform.isAndroid) {
      final s = await Permission.storage.status;
      if (s.isGranted) return true;
      final p = await Permission.photos.status;
      if (p.isGranted) return true;
      final m = await Permission.manageExternalStorage.status;
      if (m.isGranted) return true;
    }
    return true;
  }

  /// Whether a non-empty backup file is present (after optional permission).
  Future<bool> backupFileExists() async {
    final path = await resolveBackupFilePath();
    if (path == null) return false;
    final f = File(path);
    if (!await f.exists()) return false;
    final len = await f.length();
    return len > 512;
  }

  /// Copy live DB → device backup. Respects [isEnabled] unless [force].
  Future<(bool ok, String message)> mirrorDatabaseIfEnabled({
    bool ignoreEnabled = false,
    bool force = false,
  }) async {
    if (_mirrorRunning) {
      return (false, 'Local backup already running.');
    }
    _mirrorRunning = true;
    try {
      if (!ignoreEnabled && !await isEnabled()) {
        return (false, 'Phone storage backup is turned off.');
      }
      if (!force && Platform.isAndroid && !await _hasLikelyWriteAccess()) {
        return (false, 'Storage permission not granted. Enable it in Settings.');
      }

      final destPath = await resolveBackupFilePath();
      if (destPath == null) {
        return (false, 'Backup path not available.');
      }

      final srcPath = await LocalDbService.instance.getDatabasePath();
      final src = File(srcPath);
      if (!await src.exists()) {
        return (false, 'Local database not found.');
      }

      final destFile = File(destPath);
      final dir = destFile.parent;
      await dir.create(recursive: true);

      final bytes = await src.readAsBytes();
      await destFile.writeAsBytes(bytes, flush: true);

      final now = DateTime.now();
      await _setLastBackupAt(now);
      return (true, 'Saved to ${await describeBackupLocation()}');
    } catch (e) {
      return (
        false,
        'Could not write phone backup. Grant storage permission or check free space. ($e)',
      );
    } finally {
      _mirrorRunning = false;
    }
  }

  /// Restore from device backup into the app database location.
  Future<(bool ok, String message)> restoreFromDeviceBackup() async {
    try {
      final path = await resolveBackupFilePath();
      if (path == null) {
        return (false, 'Backup path not available.');
      }
      final f = File(path);
      if (!await f.exists()) {
        return (false, 'No backup file on phone at expected location.');
      }
      if (await f.length() < 512) {
        return (false, 'Backup file is too small or damaged.');
      }
      await LocalDbService.instance.replaceDatabaseFromFile(path);
      return (true, 'Restored from phone storage backup.');
    } catch (e) {
      return (false, 'Restore failed: $e');
    }
  }
}
