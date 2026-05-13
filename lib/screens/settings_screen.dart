import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/backup_service.dart';
import '../services/local_device_backup_service.dart';
import '../services/local_db_service.dart';
import '../services/mother_api_server_service.dart';
import '../services/subscription_service.dart';
import '../navigation/app_router.dart';
import '../widgets/section_page_title.dart';
import 'profile_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _authService = AuthService();
  final _backupService = BackupService.instance;
  final _localDeviceBackup = LocalDeviceBackupService.instance;
  final _appSettings = AppSettingsService.instance;
  final _subscriptionService = SubscriptionService.instance;

  final TextEditingController _shopNameController = TextEditingController();
  final TextEditingController _currencyController = TextEditingController(
    text: 'USh',
  );
  final TextEditingController _dropboxTokenController = TextEditingController();
  final TextEditingController _dropboxRefreshTokenController =
      TextEditingController();
  final TextEditingController _dropboxClientIdController =
      TextEditingController();
  final TextEditingController _dropboxClientSecretController =
      TextEditingController();
  final TextEditingController _dropboxPathController = TextEditingController();
  final TextEditingController _dropboxAuthCodeController =
      TextEditingController();

  bool _lowStockAlerts = true;
  bool _backupEnabled = false;
  bool _phoneBackupEnabled = true;
  DateTime? _lastPhoneBackupAt;
  String _phoneBackupLocation = '';
  bool _phoneBackupRunning = false;
  bool _phoneRestoreRunning = false;
  bool _showFixedDecimals = false;
  bool _saving = false;
  bool _backupNowRunning = false;
  bool _restoreRunning = false;
  bool _exchangingCode = false;
  bool _loading = true;
  DateTime? _lastBackupAt;
  SubscriptionStatus? _subscriptionStatus;
  Map<String, String?> _businessProfile = const {};
  List<MotherApiEndpoint> _motherApiEndpoints = const [];
  Timer? _backupTimeRefreshTimer;
  Timer? _endpointRefreshTimer;

  String get _dropboxTokenModeStatus {
    final hasRefresh =
        _dropboxRefreshTokenController.text.trim().isNotEmpty &&
        _dropboxClientIdController.text.trim().isNotEmpty;
    if (hasRefresh) {
      return 'Token mode: Auto-renew enabled (refresh token)';
    }
    final hasAccess = _dropboxTokenController.text.trim().isNotEmpty;
    if (hasAccess) {
      return 'Token mode: Access token only (may expire)';
    }
    return 'Token mode: Not configured';
  }

  static const _kLowStockAlertsKey = 'settings_low_stock_alerts';

  @override
  void initState() {
    super.initState();
    _dropboxTokenController.addListener(_onTokenFieldsChanged);
    _dropboxRefreshTokenController.addListener(_onTokenFieldsChanged);
    _dropboxClientIdController.addListener(_onTokenFieldsChanged);
    _dropboxAuthCodeController.addListener(_onTokenFieldsChanged);
    _loadSettings();
    _backupTimeRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshLastBackupAt(),
    );
    _endpointRefreshTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _refreshMotherApiEndpoints(),
    );
  }

  void _onTokenFieldsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _shopNameController.text = _appSettings.shopName;
      _currencyController.text = _appSettings.currencySymbol;
      _showFixedDecimals = _appSettings.showFixedDecimals;
      _lowStockAlerts = prefs.getBool(_kLowStockAlertsKey) ?? true;
    });

    final backupEnabled = await _backupService.isEnabled();
    final token = await _backupService.getDropboxToken();
    final refreshToken = await _backupService.getDropboxRefreshToken();
    final clientId = await _backupService.getDropboxClientId();
    final clientSecret = await _backupService.getDropboxClientSecret();
    final path = await _backupService.getDropboxPath();
    final lastBackup = await _backupService.getLastBackupAt();
    final phoneBackupEnabled = await _localDeviceBackup.isEnabled();
    final lastPhoneBackup = await _localDeviceBackup.getLastBackupAt();
    final phoneLoc = await _localDeviceBackup.describeBackupLocation();
    final subscriptionStatus = await _subscriptionService.getStatus();
    final businessProfile = await LocalDbService.instance.getBusinessProfile();
    final motherApiEndpoints = await MotherApiServerService.instance
        .getAdvertisedEndpoints();

    if (!mounted) return;
    setState(() {
      _backupEnabled = backupEnabled;
      _dropboxTokenController.text = token;
      _dropboxRefreshTokenController.text = refreshToken;
      _dropboxClientIdController.text = clientId;
      _dropboxClientSecretController.text = clientSecret;
      _dropboxPathController.text = path;
      _lastBackupAt = lastBackup;
      _phoneBackupEnabled = phoneBackupEnabled;
      _lastPhoneBackupAt = lastPhoneBackup;
      _phoneBackupLocation = phoneLoc;
      _subscriptionStatus = subscriptionStatus;
      _businessProfile = businessProfile;
      _motherApiEndpoints = motherApiEndpoints;
      _loading = false;
    });
  }

  Future<void> _copyMotherApi(String url) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Mother API copied.')));
  }

  Future<void> _refreshLastBackupAt() async {
    final lastBackup = await _backupService.getLastBackupAt();
    final lastPhone = await _localDeviceBackup.getLastBackupAt();
    if (!mounted) return;
    if (_lastBackupAt != lastBackup || _lastPhoneBackupAt != lastPhone) {
      setState(() {
        _lastBackupAt = lastBackup;
        _lastPhoneBackupAt = lastPhone;
      });
    }
  }

  Future<void> _refreshMotherApiEndpoints() async {
    final latest = await MotherApiServerService.instance.getAdvertisedEndpoints();
    if (!mounted) return;
    final oldKey = _motherApiEndpoints.map((e) => e.baseUrl).join('|');
    final newKey = latest.map((e) => e.baseUrl).join('|');
    if (oldKey == newKey) return;
    setState(() => _motherApiEndpoints = latest);
  }

  Future<void> _copyBusinessCode() async {
    final code = (_businessProfile['code'] ?? '').trim();
    if (code.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Business code copied.')));
  }

  Future<void> _openRenewSubscription() async {
    await Navigator.of(context).pushNamed(AppRouter.subscriptionActivation);
    if (!mounted) return;
    final refreshed = await _subscriptionService.getStatus();
    if (!mounted) return;
    setState(() => _subscriptionStatus = refreshed);
  }

  Future<void> _saveSettings() async {
    setState(() {
      _saving = true;
    });
    final prefs = await SharedPreferences.getInstance();
    await _appSettings.setShopName(_shopNameController.text);
    await _appSettings.setCurrencySymbol(_currencyController.text);
    await _appSettings.setShowFixedDecimals(_showFixedDecimals);
    await prefs.setBool(_kLowStockAlertsKey, _lowStockAlerts);
    await _backupService.setEnabled(_backupEnabled);
    await _backupService.setDropboxToken(_dropboxTokenController.text);
    await _backupService.setDropboxRefreshToken(
      _dropboxRefreshTokenController.text,
    );
    await _backupService.setDropboxClientId(_dropboxClientIdController.text);
    await _backupService.setDropboxClientSecret(
      _dropboxClientSecretController.text,
    );
    await _backupService.setDropboxPath(_dropboxPathController.text);
    await _localDeviceBackup.setEnabled(_phoneBackupEnabled);

    if (!mounted) return;

    setState(() {
      _saving = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  Future<void> _backupNow() async {
    await _backupService.setEnabled(_backupEnabled);
    await _backupService.setDropboxToken(_dropboxTokenController.text);
    await _backupService.setDropboxRefreshToken(
      _dropboxRefreshTokenController.text,
    );
    await _backupService.setDropboxClientId(_dropboxClientIdController.text);
    await _backupService.setDropboxClientSecret(
      _dropboxClientSecretController.text,
    );
    await _backupService.setDropboxPath(_dropboxPathController.text);
    setState(() {
      _backupNowRunning = true;
    });
    final ok = await _backupService.backupNowDetailed(ignoreEnabled: true);
    final lastBackup = await _backupService.getLastBackupAt();
    if (!mounted) return;
    setState(() {
      _backupNowRunning = false;
      _lastBackupAt = lastBackup;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok.$2)));
    final lastPhone = await _localDeviceBackup.getLastBackupAt();
    if (!mounted) return;
    setState(() => _lastPhoneBackupAt = lastPhone);
  }

  Future<void> _grantPhoneStoragePermission() async {
    final r = await _localDeviceBackup.openStorageManagementUi();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.$2)));
  }

  Future<void> _phoneBackupOnly() async {
    setState(() => _phoneBackupRunning = true);
    final ok = await _localDeviceBackup.mirrorDatabaseIfEnabled(
      ignoreEnabled: true,
      force: true,
    );
    final lastPhone = await _localDeviceBackup.getLastBackupAt();
    if (!mounted) return;
    setState(() {
      _phoneBackupRunning = false;
      _lastPhoneBackupAt = lastPhone;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok.$2)));
  }

  Future<void> _restoreFromPhone() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from phone storage?'),
        content: const Text(
          'This replaces all data on this device with the backup file in Downloads/VenerandaShop. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _phoneRestoreRunning = true);
    final ok = await _localDeviceBackup.restoreFromDeviceBackup();
    if (!mounted) return;
    setState(() => _phoneRestoreRunning = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok.$2)));
  }

  Future<void> _restoreLatest() async {
    await _backupService.setDropboxToken(_dropboxTokenController.text);
    await _backupService.setDropboxRefreshToken(
      _dropboxRefreshTokenController.text,
    );
    await _backupService.setDropboxClientId(_dropboxClientIdController.text);
    await _backupService.setDropboxClientSecret(
      _dropboxClientSecretController.text,
    );
    await _backupService.setDropboxPath(_dropboxPathController.text);
    setState(() {
      _restoreRunning = true;
    });
    final ok = await _backupService.restoreLatestBackupDetailed();
    if (!mounted) return;
    setState(() {
      _restoreRunning = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok.$2)));
  }

  Future<void> _exchangeDropboxCode() async {
    final code = _dropboxAuthCodeController.text.trim();
    final clientId = _dropboxClientIdController.text.trim();
    final clientSecret = _dropboxClientSecretController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter authorization code first.')),
      );
      return;
    }

    setState(() => _exchangingCode = true);
    final result = await _backupService.exchangeAuthCodeForRefreshToken(
      authCode: code,
      clientId: clientId,
      clientSecret: clientSecret,
    );
    if (!mounted) return;

    if (result.$1) {
      _dropboxTokenController.text = await _backupService.getDropboxToken();
      _dropboxRefreshTokenController.text = await _backupService
          .getDropboxRefreshToken();
      _dropboxClientIdController.text = await _backupService
          .getDropboxClientId();
      _dropboxClientSecretController.text = await _backupService
          .getDropboxClientSecret();
      _dropboxAuthCodeController.clear();
    }

    setState(() => _exchangingCode = false);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.$2)));
  }

  Future<void> _logout() async {
    await _authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(AppRouter.login);
  }

  @override
  void dispose() {
    _backupTimeRefreshTimer?.cancel();
    _endpointRefreshTimer?.cancel();
    _dropboxTokenController.removeListener(_onTokenFieldsChanged);
    _dropboxRefreshTokenController.removeListener(_onTokenFieldsChanged);
    _dropboxClientIdController.removeListener(_onTokenFieldsChanged);
    _dropboxAuthCodeController.removeListener(_onTokenFieldsChanged);
    _shopNameController.dispose();
    _currencyController.dispose();
    _dropboxTokenController.dispose();
    _dropboxRefreshTokenController.dispose();
    _dropboxClientIdController.dispose();
    _dropboxClientSecretController.dispose();
    _dropboxPathController.dispose();
    _dropboxAuthCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canRenewNow =
        _subscriptionStatus != null &&
        (!_subscriptionStatus!.isActivated || _subscriptionStatus!.expired);

    return Scaffold(
      appBar: AppBar(title: const SectionPageTitle(pageTitle: 'Settings')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Shop',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mother API endpoint(s)',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_motherApiEndpoints.isEmpty)
                          const Text('No IPv4 endpoints detected yet.')
                        else
                          ..._motherApiEndpoints.asMap().entries.map((entry) {
                            final index = entry.key;
                            final endpoint = entry.value;
                            return Padding(
                              padding: EdgeInsets.only(
                                bottom:
                                    index == _motherApiEndpoints.length - 1
                                    ? 0
                                    : 10,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        if (endpoint.isHotspotLikely)
                                          Align(
                                            alignment: Alignment.centerLeft,
                                            child: OutlinedButton(
                                              onPressed: () =>
                                                  _copyMotherApi(endpoint.baseUrl),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: Colors.green,
                                                backgroundColor: Colors.green
                                                    .withValues(alpha: 0.06),
                                                side: const BorderSide(
                                                  color: Colors.green,
                                                  width: 1.2,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                              ),
                                              child: Text(
                                                endpoint.baseUrl,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                          )
                                        else
                                          Text(endpoint.baseUrl),
                                        Text(
                                          'Interface: ${endpoint.interfaceName}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        _copyMotherApi(endpoint.baseUrl),
                                    child: const Text('Copy'),
                                  ),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Business profile',
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Name: ${(_businessProfile['name'] ?? '').trim().isEmpty ? '-' : _businessProfile['name']!.trim()}',
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Code: ${(_businessProfile['code'] ?? '').trim().isEmpty ? '-' : _businessProfile['code']!.trim().toUpperCase()}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            TextButton.icon(
                              onPressed:
                                  (_businessProfile['code'] ?? '')
                                      .trim()
                                      .isEmpty
                                  ? null
                                  : _copyBusinessCode,
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _shopNameController,
                  decoration: const InputDecoration(
                    labelText: 'Shop name',
                    hintText: 'e.g. Main Street Supermarket',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _currencyController,
                  decoration: const InputDecoration(
                    labelText: 'Currency symbol',
                    hintText: 'e.g. USh, ₦, \$, KES',
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show fixed 2 decimals (e.g. 25.00)'),
                  subtitle: const Text(
                    'Off by default to hide trailing .00 on quantities and prices',
                  ),
                  value: _showFixedDecimals,
                  onChanged: (value) {
                    setState(() {
                      _showFixedDecimals = value;
                    });
                  },
                ),
                const SizedBox(height: 24),
                Text(
                  'Subscription',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _subscriptionStatus == null
                              ? 'Checking subscription...'
                              : (!_subscriptionStatus!.isActivated
                                    ? 'Status: Not activated'
                                    : _subscriptionStatus!.expired
                                    ? 'Status: Expired'
                                    : 'Status: Active'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _subscriptionStatus?.isActivated == false
                                ? Colors.orange.shade800
                                : _subscriptionStatus?.expired == true
                                ? Colors.red
                                : Colors.green.shade700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        if (_subscriptionStatus != null) ...[
                          Text('Days left: ${_subscriptionStatus!.daysLeft}'),
                          Text(
                            'Expires on: ${_subscriptionStatus!.expiresAt.toLocal().toString().split('.').first}',
                          ),
                        ],
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: canRenewNow
                                ? _openRenewSubscription
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2563EB),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.verified_outlined),
                            label: Text(
                              canRenewNow
                                  ? 'Renew / Activate'
                                  : 'Subscription active',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Phone storage backup',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Saves a copy of your database under Downloads/VenerandaShop on this device (Android) so you can restore after reinstall when Dropbox is not available. On the mother device, auto-save runs about every 5 minutes while the app is open and does not need internet. Grant storage access when prompted.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Include phone storage in auto backup'),
                  subtitle: Text(
                    _phoneBackupLocation,
                    style: theme.textTheme.bodySmall,
                  ),
                  value: _phoneBackupEnabled,
                  onChanged: (value) {
                    setState(() {
                      _phoneBackupEnabled = value;
                    });
                  },
                ),
                Text(
                  _lastPhoneBackupAt == null
                      ? 'Last phone backup: not yet'
                      : 'Last phone backup: ${_lastPhoneBackupAt!.toLocal()}',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _grantPhoneStoragePermission,
                    icon: const Icon(Icons.folder_shared_outlined),
                    label: const Text('Grant storage permission'),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _phoneBackupRunning ? null : _phoneBackupOnly,
                        icon: _phoneBackupRunning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_alt_outlined),
                        label: Text(
                          _phoneBackupRunning
                              ? 'Saving...'
                              : 'Back up to phone now',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _phoneRestoreRunning ? null : _restoreFromPhone,
                        icon: _phoneRestoreRunning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.restore_outlined),
                        label: Text(
                          _phoneRestoreRunning
                              ? 'Restoring...'
                              : 'Restore from phone',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Cloud Backup (Dropbox)',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Enable auto backup every 5 minutes'),
                  subtitle: const Text(
                    'Runs while the app is active and connected to internet',
                  ),
                  value: _backupEnabled,
                  onChanged: (value) {
                    setState(() {
                      _backupEnabled = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _dropboxTokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Dropbox access token',
                    hintText: 'Short-lived token (optional if refresh is set)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _dropboxRefreshTokenController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Dropbox refresh token',
                    hintText: 'Recommended for automatic token renewal',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _dropboxClientIdController,
                  decoration: const InputDecoration(
                    labelText: 'Dropbox app key (client id)',
                    hintText: 'Required when using refresh token',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _dropboxClientSecretController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Dropbox app secret',
                    hintText: 'Optional for PKCE apps, otherwise required',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _dropboxAuthCodeController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Dropbox authorization code',
                    hintText: 'Paste one-time code to generate refresh token',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _exchangingCode ? null : _exchangeDropboxCode,
                    icon: _exchangingCode
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.key),
                    label: Text(
                      _exchangingCode ? 'Exchanging...' : 'Exchange code',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _dropboxPathController,
                  decoration: const InputDecoration(
                    labelText: 'Dropbox backup path',
                    hintText: '/lab_app/shop_manager_latest.db',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _dropboxTokenModeStatus,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color:
                        _dropboxTokenModeStatus.contains('Auto-renew enabled')
                        ? Colors.green[700]
                        : Colors.orange[800],
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _lastBackupAt == null
                      ? 'Last backup: not yet'
                      : 'Last backup: ${_lastBackupAt!.toLocal()}',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _backupNowRunning ? null : _backupNow,
                        icon: _backupNowRunning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_upload),
                        label: Text(
                          _backupNowRunning ? 'Backing up...' : 'Backup now',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _restoreRunning ? null : _restoreLatest,
                        icon: _restoreRunning
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cloud_download),
                        label: Text(
                          _restoreRunning ? 'Restoring...' : 'Restore latest',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Alerts',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Low stock alerts'),
                  subtitle: const Text(
                    'Highlight items that are out of stock or below reorder level',
                  ),
                  value: _lowStockAlerts,
                  onChanged: (value) {
                    setState(() {
                      _lowStockAlerts = value;
                    });
                  },
                ),
                const Divider(height: 32),
                ListTile(
                  leading: const Icon(Icons.person),
                  title: const Text('Profile'),
                  subtitle: const Text('Edit account information'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const ProfileScreen()),
                    );
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.verified_user),
                  title: const Text('Child user role assignment'),
                  subtitle: const Text(
                    'Approve child signups and assign roles',
                  ),
                  onTap: () {
                    Navigator.of(context).pushNamed(AppRouter.remoteUserRoles);
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text(
                    'Logout',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: _logout,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _saveSettings,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'Saving...' : 'Save settings'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
