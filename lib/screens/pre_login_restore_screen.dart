import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../navigation/app_router.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/local_device_backup_service.dart';

class PreLoginRestoreScreen extends StatefulWidget {
  const PreLoginRestoreScreen({super.key});

  @override
  State<PreLoginRestoreScreen> createState() => _PreLoginRestoreScreenState();
}

class _PreLoginRestoreScreenState extends State<PreLoginRestoreScreen>
    with WidgetsBindingObserver {
  final _backup = BackupService.instance;
  final _localBackup = LocalDeviceBackupService.instance;
  final _auth = AuthService();
  final _tokenController = TextEditingController();
  final _refreshTokenController = TextEditingController();
  final _clientIdController = TextEditingController();
  final _clientSecretController = TextEditingController();
  final _pathController = TextEditingController();
  bool _restoring = false;
  bool _restoringPhone = false;
  bool _loading = true;
  bool _phoneBackupAvailable = false;
  bool _checkingPhone = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPhoneBackupAfterResume();
    }
  }

  Future<void> _refreshPhoneBackupAfterResume() async {
    if (!mounted || _loading || _checkingPhone) return;
    final exists = await _localBackup.backupFileExists();
    if (!mounted) return;
    setState(() => _phoneBackupAvailable = exists);
  }

  Future<void> _init() async {
    await _loadSavedValues();
    await _localBackup.requestStorageAccess();
    final exists = await _localBackup.backupFileExists();
    if (!mounted) return;
    setState(() {
      _phoneBackupAvailable = exists;
      _checkingPhone = false;
    });
  }

  Future<void> _loadSavedValues() async {
    final token = await _backup.getDropboxToken();
    final refreshToken = await _backup.getDropboxRefreshToken();
    final clientId = await _backup.getDropboxClientId();
    final clientSecret = await _backup.getDropboxClientSecret();
    final path = await _backup.getDropboxPath();
    if (!mounted) return;
    setState(() {
      _tokenController.text = token;
      _refreshTokenController.text = refreshToken;
      _clientIdController.text = clientId;
      _clientSecretController.text = clientSecret;
      _pathController.text = path;
      _loading = false;
    });
  }

  Future<void> _restoreFromPhone() async {
    setState(() => _restoringPhone = true);
    final ok = await _localBackup.restoreFromDeviceBackup();
    if (!mounted) return;
    setState(() => _restoringPhone = false);
    if (ok.$1) {
      final hasAccount = await _auth.hasAnyAccount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok.$2)),
      );
      Navigator.of(context).pushReplacementNamed(
        hasAccount ? AppRouter.login : AppRouter.signup,
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok.$2)),
    );
  }

  Future<void> _restoreNow() async {
    final token = _tokenController.text.trim();
    final refreshToken = _refreshTokenController.text.trim();
    final clientId = _clientIdController.text.trim();
    if (token.isEmpty && (refreshToken.isEmpty || clientId.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter access token, or refresh token + app key first',
          ),
        ),
      );
      return;
    }

    setState(() => _restoring = true);
    await _backup.setDropboxToken(token);
    await _backup.setDropboxRefreshToken(refreshToken);
    await _backup.setDropboxClientId(clientId);
    await _backup.setDropboxClientSecret(_clientSecretController.text);
    await _backup.setDropboxPath(_pathController.text);

    final hasRemote = await _backup.hasRemoteBackupDetailed();
    if (!mounted) return;
    if (!hasRemote.$1) {
      setState(() => _restoring = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(hasRemote.$2)));
      Navigator.of(context).pushReplacementNamed(AppRouter.signup);
      return;
    }

    final ok = await _backup.restoreLatestBackupDetailed();
    if (!mounted) return;

    setState(() => _restoring = false);
    if (ok.$1) {
      final hasAccount = await _auth.hasAnyAccount();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ok.$2)),
      );
      Navigator.of(context).pushReplacementNamed(
        hasAccount ? AppRouter.login : AppRouter.signup,
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok.$2)),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tokenController.dispose();
    _refreshTokenController.dispose();
    _clientIdController.dispose();
    _clientSecretController.dispose();
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushReplacementNamed(AppRouter.login);
          },
        ),
        title: const Text('Restore backup'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'No local app data was found. Restore from a backup on this phone (if you saved one) or from Dropbox.',
                ),
                const SizedBox(height: 16),
                Text(
                  'Phone storage',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  _checkingPhone
                      ? 'Checking Downloads/VenerandaShop…'
                      : _phoneBackupAvailable
                          ? 'A backup file was found on this device.'
                          : kIsWeb
                              ? 'No backup file found on this device. Use Dropbox below.'
                              : 'No backup file found. You can use “Grant storage permission” in Settings after signing in, or restore from Dropbox below.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: (_restoringPhone ||
                          _restoring ||
                          !_phoneBackupAvailable ||
                          _checkingPhone)
                      ? null
                      : _restoreFromPhone,
                  icon: _restoringPhone
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.phone_android_outlined),
                  label: Text(
                    _restoringPhone
                        ? 'Restoring…'
                        : 'Restore from phone storage',
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Dropbox',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _tokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Dropbox access token',
                    hintText: 'Optional if refresh token is provided',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _refreshTokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Dropbox refresh token',
                    hintText: 'Recommended for automatic renewal',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clientIdController,
                  decoration: const InputDecoration(
                    labelText: 'Dropbox app key (client id)',
                    hintText: 'Required when using refresh token',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clientSecretController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Dropbox app secret',
                    hintText: 'Optional for PKCE apps',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _pathController,
                  decoration: const InputDecoration(
                    labelText: 'Dropbox backup path',
                    hintText: '/lab_app/shop_manager_latest.db',
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _restoring || _restoringPhone ? null : _restoreNow,
                  icon: _restoring
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_download),
                  label: Text(_restoring ? 'Restoring...' : 'Restore from Dropbox'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _restoring || _restoringPhone
                      ? null
                      : () {
                          Navigator.of(context).pushReplacementNamed(
                            AppRouter.signup,
                          );
                        },
                  child: const Text('Skip for now and go to sign up'),
                ),
              ],
            ),
    );
  }
}
