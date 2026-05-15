import 'package:flutter/foundation.dart';

/// Lets a pushed route (e.g. [SalesScreen]) ask [MainNavigationScreen] to switch tabs.
final class MainShellTabBus {
  MainShellTabBus._();
  static final MainShellTabBus instance = MainShellTabBus._();

  final ValueNotifier<int?> pendingIndex = ValueNotifier<int?>(null);

  void selectTab(int index) {
    pendingIndex.value = index;
  }

  void clearPending() {
    pendingIndex.value = null;
  }
}
