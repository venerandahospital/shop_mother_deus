import 'package:mobile_scanner/mobile_scanner.dart';

/// Stops and disposes a [MobileScannerController] so Camera2 releases on Android.
///
/// Call after removing [MobileScanner] from the widget tree (e.g. after [endOfFrame]).
Future<void> releaseMobileScannerController(
  MobileScannerController controller,
) async {
  try {
    if (controller.value.isRunning) {
      await controller.stop();
    }
  } catch (_) {}
  try {
    await controller.dispose();
  } catch (_) {}
}

/// Pauses frame analysis while the route is covered or the app is backgrounded.
Future<void> pauseMobileScannerIfRunning(MobileScannerController controller) async {
  try {
    if (controller.value.isRunning) {
      await controller.pause();
    }
  } catch (_) {}
}

/// Resumes after [pauseMobileScannerIfRunning] when the scan screen is visible again.
Future<void> resumeMobileScannerIfPaused(MobileScannerController controller) async {
  try {
    if (controller.value.isInitialized && !controller.value.isRunning) {
      await controller.start();
    }
  } catch (_) {}
}
