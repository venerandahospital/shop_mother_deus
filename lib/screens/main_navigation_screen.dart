import 'package:flutter/material.dart';

import 'dashboard_screen.dart';
import 'sales_history_screen.dart';
import 'inventory_screen.dart';
import 'stores_screen.dart';
import 'settings_screen.dart';
import '../widgets/bottom_nav.dart';
import '../services/subscription_service.dart';
import '../services/auth_service.dart';
import '../navigation/app_router.dart';
import '../navigation/main_shell_tab_bus.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;

  const MainNavigationScreen({super.key, this.initialIndex = 0});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  bool _checkedSubscription = false;
  bool _showSettings = true;
  bool _skipSubscriptionForRemote = false;
  final _authService = AuthService();
  List<Widget> get _screens => <Widget>[
    const DashboardScreen(),
    const SalesHistoryScreen(),
    const InventoryScreen(),
    const StoresScreen(),
    if (_showSettings) const SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex < 0 ? 0 : widget.initialIndex;
    MainShellTabBus.instance.pendingIndex.addListener(_onShellTabRequested);
  }

  @override
  void dispose() {
    MainShellTabBus.instance.pendingIndex.removeListener(_onShellTabRequested);
    super.dispose();
  }

  void _onShellTabRequested() {
    final idx = MainShellTabBus.instance.pendingIndex.value;
    if (idx == null || !mounted) return;
    final max = _screens.length - 1;
    final clamped = idx.clamp(0, max);
    setState(() => _currentIndex = clamped);
    MainShellTabBus.instance.clearPending();
  }

  Future<void> _onWillPop() async {
    // Instead of exiting the app from root, always take user to Dashboard.
    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checkedSubscription) return;
    _checkedSubscription = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeUserSessionGuards();
    });
  }

  Future<void> _initializeUserSessionGuards() async {
    await _loadUserType();
    await _checkSubscriptionGateAndReminder();
  }

  Future<void> _loadUserType() async {
    final userType = await _authService.getUserType();
    final shouldShowSettings = userType != 'REMOTE';
    if (!mounted) return;
    setState(() {
      _showSettings = shouldShowSettings;
      _skipSubscriptionForRemote = userType == 'REMOTE';
      if (!_showSettings && _currentIndex >= _screens.length) {
        _currentIndex = 0;
      }
    });
  }

  Future<void> _checkSubscriptionGateAndReminder() async {
    if (_skipSubscriptionForRemote) return;
    final status = await SubscriptionService.instance.getStatus();
    if (!mounted) return;
    if (status.expired) {
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AppRouter.subscriptionActivation, (_) => false);
      return;
    }
    final showReminder = await SubscriptionService.instance
        .shouldShowReminderToday();
    if (!mounted || !showReminder) return;

    final urgent = status.daysLeft <= 2;
    await showDialog<void>(
      context: context,
      barrierDismissible: !urgent,
      builder: (context) => AlertDialog(
        icon: Icon(
          urgent ? Icons.warning_amber_rounded : Icons.info_outline,
          color: urgent ? const Color(0xFFD97706) : null,
        ),
        title: Text(urgent ? 'Renew within 2 days' : 'Subscription reminder'),
        content: Text(
          urgent
              ? status.daysLeft <= 0
                  ? 'Your subscription ends today. Renew now so child devices and sync keep working.'
                  : 'Only ${status.daysLeft} day(s) left on your subscription. '
                        'Renew now to avoid interruption for child apps and daily use.'
              : 'Your subscription expires in ${status.daysLeft} day(s). '
                    'Please renew before expiry to avoid interruption.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(urgent ? 'Not now' : 'Later'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  urgent ? const Color(0xFFD97706) : const Color(0xFF2563EB),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).pushNamed(AppRouter.subscriptionActivation);
            },
            child: const Text('Renew now'),
          ),
        ],
      ),
    );
    await SubscriptionService.instance.markReminderShownToday();
  }

  Future<void> _handleNavTap(int index) async {
    // Require re-auth when opening Settings.
    if (_showSettings && index == _screens.length - 1) {
      final allowed = await _confirmPasswordForSettings();
      if (!mounted || !allowed) return;
    }
    setState(() {
      _currentIndex = index;
    });
  }

  Future<bool> _confirmPasswordForSettings() async {
    final profile = await _authService.getCurrentProfile();
    final currentPassword = (profile['password'] ?? '').trim();
    if (currentPassword.isEmpty) return true;

    var enteredPassword = '';
    var obscure = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('Confirm password'),
            content: TextField(
              autofocus: true,
              obscureText: obscure,
              onChanged: (value) => enteredPassword = value,
              decoration: InputDecoration(
                labelText: 'Enter password',
                suffixIcon: IconButton(
                  onPressed: () {
                    setDialogState(() => obscure = !obscure);
                  },
                  icon: Icon(obscure ? Icons.visibility_off : Icons.visibility),
                ),
              ),
              onSubmitted: (_) => Navigator.of(context).pop(true),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                ),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
      },
    );

    if (ok != true) return false;
    if (enteredPassword.trim() == currentPassword) return true;
    if (!mounted) return false;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Wrong password.')));
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final safeIndex = _currentIndex >= _screens.length ? 0 : _currentIndex;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _onWillPop();
      },
      child: Scaffold(
        body: IndexedStack(index: safeIndex, children: _screens),
        bottomNavigationBar: BottomNav(
          currentIndex: safeIndex,
          onTap: _handleNavTap,
          showSettings: _showSettings,
        ),
      ),
    );
  }
}
