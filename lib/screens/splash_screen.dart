import 'package:flutter/material.dart';
import '../navigation/app_router.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/local_device_backup_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _goNext();
    });
  }

  Future<void> _goNext() async {
    await LocalDeviceBackupService.instance.promptStorageAccessOnInstallIfNeeded();
    await BackupService.instance.restoreIfLocalMissing();
    final hasLocalDb = await BackupService.instance.hasUsableLocalDatabase();
    final hasAccount = await _authService.hasAnyAccount();
    if (!mounted) return;
    if (!hasLocalDb) {
      Navigator.of(context).pushReplacementNamed(AppRouter.preLoginRestore);
      return;
    }
    if (!hasAccount) {
      Navigator.of(context).pushReplacementNamed(AppRouter.preLoginRestore);
      return;
    }
    Navigator.of(context).pushReplacementNamed(AppRouter.login);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF1e3a8a),
              Color(0xFF2563eb),
              Color(0xFF3b82f6),
              Color(0xFF60a5fa),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 140,
                    height: 140,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.store,
                      size: 100,
                      color: Colors.white.withOpacity(0.9),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Veneranda Shop',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
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
