import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../utils/barcode_scanner_lifecycle.dart';
import '../widgets/section_page_title.dart';

const _kSaleFlowAppBarBlue = Color(0xFF5181da);

/// Full-screen camera barcode scan. Pops with the decoded string, or null if closed.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoStart: true,
  );
  bool _scannerMounted = true;
  bool _exiting = false;
  bool _cameraReleased = false;

  Future<void> _releaseCameraFully() async {
    if (_cameraReleased) return;
    _cameraReleased = true;
    await releaseMobileScannerController(_controller);
  }

  /// Unmounts preview, stops camera + native scanner, then pops.
  Future<void> _exit([String? result]) async {
    if (_exiting) return;
    _exiting = true;
    if (mounted && _scannerMounted) {
      setState(() => _scannerMounted = false);
    }
    await WidgetsBinding.instance.endOfFrame;
    await _releaseCameraFully();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _exiting = true;
    WidgetsBinding.instance.removeObserver(this);
    if (!_cameraReleased) {
      unawaited(_releaseCameraFully());
    }
    super.dispose();
  }

  @override
  void deactivate() {
    super.deactivate();
    if (!_exiting && !_cameraReleased) {
      unawaited(pauseMobileScannerIfRunning(_controller));
    }
  }

  @override
  void activate() {
    super.activate();
    if (!_exiting && !_cameraReleased && _scannerMounted) {
      unawaited(resumeMobileScannerIfPaused(_controller));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_exiting || _cameraReleased) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        unawaited(pauseMobileScannerIfRunning(_controller));
      case AppLifecycleState.resumed:
        if (_scannerMounted) {
          unawaited(resumeMobileScannerIfPaused(_controller));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          unawaited(_exit());
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: _kSaleFlowAppBarBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          leading: BackButton(
            onPressed: () => unawaited(_exit()),
          ),
          title: const SectionPageTitle(pageTitle: 'Scan barcode'),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_scannerMounted && !_cameraReleased)
              MobileScanner(
                controller: _controller,
                useAppLifecycleState: false,
                onDetect: (BarcodeCapture capture) {
                  if (_exiting || _cameraReleased) return;
                  for (final b in capture.barcodes) {
                    final v = b.rawValue;
                    if (v != null && v.trim().isNotEmpty) {
                      unawaited(_exit(v.trim()));
                      return;
                    }
                  }
                },
              ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Text(
                'Point the camera at the barcode on the product',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontSize: 16,
                  shadows: const [
                    Shadow(blurRadius: 8, color: Colors.black54),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
