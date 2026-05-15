import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../widgets/section_page_title.dart';

const _kSaleFlowAppBarBlue = Color(0xFF5181da);

/// Camera helper that estimates quantity by counting repeated visible barcodes.
/// Returns {'code': String, 'qty': int} or null when canceled.
class ProductQuantityCameraScreen extends StatefulWidget {
  const ProductQuantityCameraScreen({super.key});

  @override
  State<ProductQuantityCameraScreen> createState() =>
      _ProductQuantityCameraScreenState();
}

class _ProductQuantityCameraScreenState extends State<ProductQuantityCameraScreen> {
  static const int _kWindowSize = 8;
  final MobileScannerController _controller = MobileScannerController(
    facing: CameraFacing.back,
    detectionSpeed: DetectionSpeed.normal,
    autoStart: true,
  );
  final Map<String, ListQueue<int>> _recentCountsByCode = <String, ListQueue<int>>{};
  String? _selectedCode;
  int _selectedQty = 1;
  bool _frozen = false;
  String _confidenceLabel = 'Low';
  bool _scannerMounted = true;
  bool _exiting = false;

  Future<void> _releaseCamera() async {
    try {
      await _controller.stop();
    } catch (_) {}
  }

  Future<void> _exit([Map<String, Object>? result]) async {
    if (_exiting) return;
    _exiting = true;
    if (mounted && _scannerMounted) {
      setState(() => _scannerMounted = false);
    }
    await WidgetsBinding.instance.endOfFrame;
    await _releaseCamera();
    if (!mounted) return;
    Navigator.of(context).pop(result);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_exiting || _frozen) return;
    final frameCounts = <String, int>{};
    for (final barcode in capture.barcodes) {
      final raw = (barcode.rawValue ?? '').trim();
      if (raw.isEmpty) continue;
      frameCounts.update(raw, (value) => value + 1, ifAbsent: () => 1);
    }
    if (frameCounts.isEmpty) return;

    frameCounts.forEach((code, count) {
      final queue =
          _recentCountsByCode.putIfAbsent(code, () => ListQueue<int>());
      queue.add(count);
      while (queue.length > _kWindowSize) {
        queue.removeFirst();
      }
    });

    String? bestCode;
    var bestScore = -1.0;
    _recentCountsByCode.forEach((code, queue) {
      if (queue.isEmpty) return;
      final avg = queue.reduce((a, b) => a + b) / queue.length;
      final score = queue.length * 10 + avg;
      if (score > bestScore) {
        bestScore = score;
        bestCode = code;
      }
    });
    if (bestCode == null) return;

    final bestQty = _stableCountFor(bestCode!).clamp(1, 999);
    final confidence = _confidenceFor(bestCode!);

    if (_selectedCode == bestCode &&
        _selectedQty == bestQty &&
        _confidenceLabel == confidence) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _selectedCode = bestCode;
      _selectedQty = bestQty;
      _confidenceLabel = confidence;
    });
  }

  int _stableCountFor(String code) {
    final queue = _recentCountsByCode[code];
    if (queue == null || queue.isEmpty) return 1;
    final values = queue.toList()..sort();
    return values[values.length ~/ 2];
  }

  String _confidenceFor(String code) {
    final queue = _recentCountsByCode[code];
    if (queue == null || queue.isEmpty) return 'Low';
    final values = queue.toList()..sort();
    final min = values.first;
    final max = values.last;
    final spread = max - min;
    if (queue.length >= 6 && spread <= 1) return 'High';
    if (queue.length >= 4 && spread <= 2) return 'Medium';
    return 'Low';
  }

  Future<void> _applyAndClose() async {
    final code = (_selectedCode ?? '').trim();
    if (code.isEmpty) return;
    await _exit(<String, Object>{
      'code': code,
      'qty': _selectedQty.clamp(1, 999),
    });
  }

  @override
  void dispose() {
    _exiting = true;
    if (_scannerMounted) {
      unawaited(_releaseCamera());
    }
    unawaited(_controller.dispose());
    super.dispose();
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
          title: const SectionPageTitle(pageTitle: 'Detect product + quantity'),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            if (_scannerMounted)
              MobileScanner(
                controller: _controller,
                useAppLifecycleState: false,
                onDetect: _onDetect,
              ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _selectedCode == null
                            ? 'Point camera to product barcode(s)'
                            : 'Detected code: $_selectedCode',
                        textAlign: TextAlign.center,
                      ),
                      if (_selectedCode != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Stability: $_confidenceLabel',
                          style: TextStyle(
                            color: _confidenceLabel == 'High'
                                ? Colors.green.shade700
                                : _confidenceLabel == 'Medium'
                                    ? Colors.orange.shade700
                                    : Colors.red.shade700,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: _selectedCode == null
                                ? null
                                : () => setState(() {
                                      _selectedQty =
                                          (_selectedQty - 1).clamp(1, 999);
                                    }),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          Text(
                            'Qty $_selectedQty',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          IconButton(
                            onPressed: _selectedCode == null
                                ? null
                                : () => setState(() {
                                      _selectedQty =
                                          (_selectedQty + 1).clamp(1, 999);
                                    }),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _selectedCode == null
                              ? null
                              : () => setState(() => _frozen = !_frozen),
                          icon: Icon(
                            _frozen
                                ? Icons.play_circle_outline
                                : Icons.pause_circle_outline,
                          ),
                          label: Text(
                            _frozen ? 'Resume camera analysis' : 'Freeze count',
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed:
                              _selectedCode == null ? null : _applyAndClose,
                          icon: const Icon(Icons.check),
                          label: const Text('Use in sale'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
