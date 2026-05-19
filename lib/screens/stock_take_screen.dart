import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/barcode_utils.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';
import 'barcode_scan_screen.dart';
import 'stock_take_update_screen.dart';

class StockTakeScreen extends StatefulWidget {
  const StockTakeScreen({super.key});

  @override
  State<StockTakeScreen> createState() => _StockTakeScreenState();
}

class _StockTakeScreenState extends State<StockTakeScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _searchController = TextEditingController();
  final SpeechToText _speech = SpeechToText();
  bool _loading = true;
  bool _speechReady = false;
  bool _isListening = false;
  List<Item> _items = [];
  List<Item> _filtered = [];
  Map<int, List<String>> _itemBarcodeAliases = const {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_applyFilter);
    _loadItems();
  }

  @override
  void dispose() {
    _speech.stop();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    List<Item> items;
    Map<int, List<String>> aliases = const {};
    if (await _auth.isRemoteUser()) {
      final remote = await _auth.fetchRemoteStockTakeItems();
      if (remote.$1) {
        items = remote.$3;
        aliases = remote.$4;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(remote.$2)),
          );
        }
        items = const [];
      }
    } else {
      items = await _db.getItemsPendingStockHandCount();
      final ids = items.map((e) => e.id).whereType<int>();
      aliases = await _db.getItemBarcodesMap(itemIds: ids);
    }
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    if (!mounted) return;
    setState(() {
      _items = items;
      _itemBarcodeAliases = aliases;
      _filtered = _filterItems(items, _searchController.text);
      _loading = false;
    });
  }

  void _applyFilter() {
    setState(() {
      _filtered = _filterItems(_items, _searchController.text);
    });
  }

  Future<void> _scanBarcodeIntoSearch() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Barcode scanning works on Android and iOS devices.'),
        ),
      );
      return;
    }
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (!mounted || code == null) return;
    final trimmed = code.trim();
    if (trimmed.isEmpty) return;
    _searchController.text = trimmed;
    _applyFilter();
  }

  Future<void> _toggleVoiceSearch() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voice search is available on Android and iOS.')),
      );
      return;
    }
    if (_isListening) {
      await _speech.stop();
      if (!mounted) return;
      setState(() => _isListening = false);
      return;
    }
    final micPermission = await Permission.microphone.request();
    if (!micPermission.isGranted) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please allow microphone permission for voice search.')),
      );
      return;
    }
    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (!mounted) return;
          if (status == 'done' || status == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (_) {
          if (!mounted) return;
          setState(() => _isListening = false);
        },
      );
    }
    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start voice search on this device.')),
      );
      return;
    }
    setState(() => _isListening = true);
    await _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        _searchController.text = result.recognizedWords;
        if (result.finalResult) {
          setState(() => _isListening = false);
        } else {
          _applyFilter();
        }
      },
    );
  }

  List<Item> _filterItems(List<Item> source, String rawQuery) {
    final trimmed = rawQuery.trim();
    final query = trimmed.toLowerCase();
    return source.where((item) {
      if (query.isEmpty) return true;
      final name = item.name.toLowerCase();
      final sku = (item.sku ?? '').toLowerCase();
      final barcode = (item.barcode ?? '').toLowerCase();
      final category = (item.category ?? '').toLowerCase();
      if (barcodeScanMatchKindForItem(
            barcode: item.barcode,
            sku: item.sku,
            scanned: trimmed,
            acceptedBarcodes:
                _itemBarcodeAliases[item.id ?? -1] ?? const [],
          ) !=
          BarcodeScanMatchKind.none) {
        return true;
      }
      return name.contains(query) ||
          sku.contains(query) ||
          barcode.contains(query) ||
          category.contains(query);
    }).toList();
  }

  void _applyRemoteList(
    List<Item> items,
    Map<int, List<String>> aliases,
  ) {
    items.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    setState(() {
      _items = items;
      _itemBarcodeAliases = aliases;
      _filtered = _filterItems(items, _searchController.text);
    });
  }

  Future<void> _updateStock(Item item) async {
    if (item.id == null) return;
    final qty = await Navigator.of(context).push<double>(
      MaterialPageRoute<double>(
        builder: (_) => StockTakeUpdateScreen(item: item),
      ),
    );
    if (!mounted || qty == null) return;

    if (await _auth.isRemoteUser()) {
      final remote = await _auth.updateRemoteStockTakeQty(
        itemId: item.id!,
        stockQty: qty,
      );
      if (!remote.$1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(remote.$2)),
        );
        return;
      }
      if (!mounted) return;
      _applyRemoteList(remote.$3, remote.$4);
    } else {
      await _db.setItemStockQtyAbsolute(item.id!, qty);
      await _loadItems();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Stock updated')),
    );
  }

  Future<void> _markCounted(Item item) async {
    if (item.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as counted?'),
        content: Text(
          '${toTitleCaseWords(item.name)} will leave this list. '
          'Future sales will check stock and reduce quantity normally.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Counted'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (await _auth.isRemoteUser()) {
      final remote = await _auth.markRemoteStockTakeCounted(itemId: item.id!);
      if (!remote.$1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(remote.$2)),
        );
        return;
      }
      if (!mounted) return;
      _applyRemoteList(remote.$3, remote.$4);
    } else {
      await _db.setStockHandCounted(item.id!, true);
      await _loadItems();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${toTitleCaseWords(item.name)} marked as counted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Stock take'),
        bottom: PreferredSize(
          preferredSize: Size.fromHeight(_isListening ? 78 : 52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 36,
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          style: theme.textTheme.bodySmall,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.white,
                            prefixIcon: const Icon(Icons.search, size: 18),
                            hintText:
                                'Search items by name, barcode, SKU, or category',
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Scan barcode',
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: _scanBarcodeIntoSearch,
                            child: const SizedBox(
                              width: 36,
                              height: 36,
                              child: Icon(Icons.qr_code_scanner, size: 20),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: _isListening ? 'Stop voice search' : 'Voice search',
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: _toggleVoiceSearch,
                            child: SizedBox(
                              width: 36,
                              height: 36,
                              child: Icon(
                                _isListening ? Icons.mic : Icons.mic_none,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_isListening)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.mic, color: Colors.white, size: 14),
                              const SizedBox(width: 6),
                              Text(
                                'Listening...',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: 'Scan barcode',
            onPressed: _scanBarcodeIntoSearch,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loadItems,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _filtered.isEmpty
              ? RefreshIndicator(
                  onRefresh: _loadItems,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 120),
                      Center(
                        child: Text(
                          _items.isEmpty
                              ? 'All items are counted'
                              : 'No items match your search',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadItems,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    itemCount: _filtered.length,
                    itemBuilder: (context, index) {
                      final item = _filtered[index];
                      final unit = (item.unit ?? '').trim();
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                toTitleCaseWords(item.name),
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if ((item.category ?? '').trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    item.category!,
                                    style: theme.textTheme.bodySmall
                                        ?.copyWith(color: Colors.grey[700]),
                                  ),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                'Stock: ${formatDisplayNumber(item.stockQty)}${unit.isEmpty ? '' : ' $unit'}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed: () => _updateStock(item),
                                    icon: const Icon(Icons.edit, size: 18),
                                    label: const Text('Update stock'),
                                  ),
                                  const SizedBox(width: 8),
                                  FilledButton.icon(
                                    onPressed: () => _markCounted(item),
                                    icon: const Icon(Icons.check, size: 18),
                                    label: const Text('Counted'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
