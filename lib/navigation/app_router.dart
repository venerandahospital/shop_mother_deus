import 'package:flutter/material.dart';
import '../screens/login_screen.dart';
import '../screens/landing_screen.dart';
import '../screens/onboarding_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/main_navigation_screen.dart';
import '../screens/dashboard_screen.dart';
import '../screens/inventory_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/signup_screen.dart';
import '../screens/forgot_password_screen.dart';
import '../screens/pre_login_restore_screen.dart';
import '../screens/subscription_activation_screen.dart';
import '../screens/business_setup_screen.dart';
import '../screens/remote_user_roles_screen.dart';
import '../services/auth_service.dart';

class AppRouter {
  static const String landing = '/';
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String preLoginRestore = '/pre-login-restore';
  static const String signup = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String main = '/main';
  static const String dashboard = '/dashboard';
  static const String inventory = '/inventory';
  static const String settings = '/settings';
  static const String subscriptionActivation = '/subscription-activation';
  static const String businessSetup = '/business-setup';
  static const String remoteUserRoles = '/remote-user-roles';

  static Route<dynamic> generateRoute(RouteSettings routeSettings) {
    switch (routeSettings.name) {
      case landing:
        return MaterialPageRoute(builder: (_) => const LandingScreen());
      case splash:
        return MaterialPageRoute(builder: (_) => const SplashScreen());
      case onboarding:
        return MaterialPageRoute(builder: (_) => const OnboardingScreen());
      case login:
        return MaterialPageRoute(builder: (_) => const LoginScreen());
      case preLoginRestore:
        return MaterialPageRoute(builder: (_) => const PreLoginRestoreScreen());
      case signup:
        return MaterialPageRoute(builder: (_) => const SignupScreen());
      case forgotPassword:
        return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());
      case main:
        return MaterialPageRoute(builder: (_) => const MainNavigationScreen());
      case dashboard:
        return MaterialPageRoute(builder: (_) => const DashboardScreen());
      case inventory:
        return MaterialPageRoute(builder: (_) => const InventoryScreen());
      case settings:
        return MaterialPageRoute(builder: (_) => const SettingsScreen());
      case subscriptionActivation:
        return MaterialPageRoute(
          builder: (_) => const SubscriptionActivationScreen(),
        );
      case businessSetup:
        return MaterialPageRoute(builder: (_) => const BusinessSetupScreen());
      case remoteUserRoles:
        return MaterialPageRoute(builder: (_) => const RemoteUserRolesScreen());
      default:
        return MaterialPageRoute(
          builder: (_) => Scaffold(
            body: Center(
              child: Text('No route defined for ${routeSettings.name}'),
            ),
          ),
        );
    }
  }

  static Future<void> checkAuthAndNavigate(BuildContext context) async {
    final authService = AuthService();
    final isLoggedIn = await authService.isLoggedIn();

    if (isLoggedIn) {
      Navigator.of(context).pushReplacementNamed(main);
    } else {
      Navigator.of(context).pushReplacementNamed(login);
    }
  }
}
