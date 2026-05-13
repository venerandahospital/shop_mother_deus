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
  final Map<String, ListQueue<int>> _recentCountsByCode = <String, ListQueue<int>>{};
  String? _selectedCode;
  int _selectedQty = 1;
  bool _frozen = false;
  String _confidenceLabel = 'Low';

  void _onDetect(BarcodeCapture capture) {
    if (_frozen) return;
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

  void _applyAndClose() {
    final code = (_selectedCode ?? '').trim();
    if (code.isEmpty) return;
    Navigator.of(context).pop(<String, Object>{
      'code': code,
      'qty': _selectedQty.clamp(1, 999),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: _kSaleFlowAppBarBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const SectionPageTitle(pageTitle: 'Detect product + quantity'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(onDetect: _onDetect),
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
                                    _selectedQty = (_selectedQty - 1).clamp(1, 999);
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
                                    _selectedQty = (_selectedQty + 1).clamp(1, 999);
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
                        onPressed: _selectedCode == null ? null : _applyAndClose,
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
    );
  }
}
