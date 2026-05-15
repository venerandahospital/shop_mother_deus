import 'package:flutter/material.dart';
import 'navigation/app_router.dart';
import 'services/app_settings_service.dart';
import 'services/backup_service.dart';
import 'services/local_device_backup_service.dart';
import 'services/low_stock_notification_service.dart';
import 'services/mother_api_foreground_service.dart';
import 'services/mother_api_server_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettingsService.instance.initialize();
  await LocalDeviceBackupService.instance.startPeriodicMotherBackup();
  await BackupService.instance.initialize();
  await MotherApiServerService.instance.start();
  await MotherApiForegroundService.instance.startIfSupported();
  await LowStockNotificationService.instance.initialize();
  await LowStockNotificationService.instance.requestPermissionIfNeeded();
  await LowStockNotificationService.instance.scheduleTwiceDailyLowStockAlerts();
  runApp(const ShopApp());
}

class ShopApp extends StatelessWidget {
  const ShopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Veneranda Shop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563eb),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF5181da),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      initialRoute: AppRouter.splash,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
