import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/item.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';

class BarcodeLabelsScreen extends StatefulWidget {
  const BarcodeLabelsScreen({
    super.key,
    required this.items,
    this.barcodeAliasesByItemId = const {},
    this.initialCustomItems = const [],
    this.initialTabIndex = 0,
  });

  final List<Item> items;
  final Map<int, List<String>> barcodeAliasesByItemId;
  final List<Item> initialCustomItems;
  final int initialTabIndex;

  @override
  State<BarcodeLabelsScreen> createState() => _BarcodeLabelsScreenState();
}

class _BarcodeLabelsScreenState extends State<BarcodeLabelsScreen>
    with SingleTickerProviderStateMixin {
  static final RegExp _autoSkuPattern = RegExp(r'^ITM\d{6}$');

  late final TabController _tabController;
  final Map<int, int> _copiesByItemId = <int, int>{};
  final List<Item> _customItems = [];
  final TextEditingController _customSearchController = TextEditingController();
  String _customSearchQuery = '';

  @override
  void initState() {
    super.initState();
    final startTab = widget.initialTabIndex.clamp(0, 2);
    _tabController = TabController(length: 3, vsync: this, initialIndex: startTab);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
    for (final item in widget.initialCustomItems) {
      _addToCustomList(item, showSnack: false);
    }
    _customSearchController.addListener(() {
      setState(() => _customSearchQuery = _customSearchController.text);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customSearchController.dispose();
    super.dispose();
  }

  String _saleCategoryLabel(Item item) {
    final raw = (item.category ?? '').trim();
    if (raw.isEmpty) return 'Uncategorized';
    for (final part in raw.split('|').map((e) => e.trim())) {
      if (part.toLowerCase().startsWith('sale:')) {
        return toTitleCaseWords(part.substring(part.indexOf(':') + 1).trim());
      }
    }
    return toTitleCaseWords(raw);
  }

  String _labelTitle(Item item) {
    final name = toTitleCaseWords(item.name);
    final saleCategory = _saleCategoryLabel(item);
    final unitName =
        ((item.unit ?? '').trim().isEmpty ? 'Unit' : item.unit!.trim());
    return '$name - $saleCategory - $unitName';
  }

  String _primaryCode(Item item) {
    final sku = (item.sku ?? '').trim().toUpperCase();
    if (_autoSkuPattern.hasMatch(sku)) return sku;
    return '';
  }

  List<Item> _sortPrintable(Iterable<Item> source) {
    return source
        .where((item) => _primaryCode(item).isNotEmpty)
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  List<Item> get _allTabItems => _sortPrintable(widget.items);

  bool _hasExtraAcceptedCodes(Item item) {
    final id = item.id;
    if (id == null) return false;
    final primary = _primaryCode(item).toLowerCase();
    final aliases = widget.barcodeAliasesByItemId[id] ?? const <String>[];
    for (final raw in aliases) {
      final code = raw.trim().toLowerCase();
      if (code.isEmpty) continue;
      if (code != primary) return true;
    }
    return false;
  }

  List<Item> get _primaryOnlyTabItems =>
      _allTabItems.where((item) => !_hasExtraAcceptedCodes(item)).toList();

  List<Item> get _activeTabItems {
    switch (_tabController.index) {
      case 1:
        return _primaryOnlyTabItems;
      case 2:
        return _sortPrintable(_customItems);
      case 0:
      default:
        return _allTabItems;
    }
  }

  List<Item> get _customSearchResults {
    final q = _customSearchQuery.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final inCustom = _customItems.map((e) => e.id).whereType<int>().toSet();
    return widget.items.where((item) {
      if (_primaryCode(item).isEmpty) return false;
      if (item.id != null && inCustom.contains(item.id)) return false;
      final name = item.name.toLowerCase();
      final sku = (item.sku ?? '').toLowerCase();
      final barcode = (item.barcode ?? '').toLowerCase();
      final category = (item.category ?? '').toLowerCase();
      return name.contains(q) ||
          sku.contains(q) ||
          barcode.contains(q) ||
          category.contains(q);
    }).take(20).toList();
  }

  int _itemKey(Item item) => item.id ?? item.hashCode;

  int _copiesFor(Item item) => _copiesByItemId[_itemKey(item)] ?? 1;

  void _setCopies(Item item, int value) {
    setState(() {
      _copiesByItemId[_itemKey(item)] = value.clamp(1, 99);
    });
  }

  void _addToCustomList(Item item, {bool showSnack = true}) {
    if (_primaryCode(item).isEmpty) {
      if (showSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This item has no primary ITM barcode to print.'),
          ),
        );
      }
      return;
    }
    final id = item.id;
    if (id != null && _customItems.any((e) => e.id == id)) {
      if (showSnack && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Item is already in the custom list.')),
        );
      }
      return;
    }
    setState(() => _customItems.add(item));
    if (showSnack && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added ${toTitleCaseWords(item.name)}')),
      );
    }
  }

  void _removeFromCustomList(Item item) {
    setState(() {
      _customItems.removeWhere((e) => _itemKey(e) == _itemKey(item));
    });
  }

  List<({Item item, String code})> _expandedLabelsFor(List<Item> items) {
    final labels = <({Item item, String code})>[];
    for (final item in items) {
      final code = _primaryCode(item);
      if (code.isEmpty) continue;
      final copies = _copiesFor(item);
      for (var i = 0; i < copies; i++) {
        labels.add((item: item, code: code));
      }
    }
    return labels;
  }

  List<({Item item, String code})> _expandedLabelsForActiveTab() =>
      _expandedLabelsFor(_activeTabItems);

  static const int _pdfCols = 3;
  static const int _pdfRows = 8;
  static const double _pdfMargin = 14;

  pw.Widget _buildLabelPdfCell(({Item item, String code}) entry) {
    return pw.Container(
      margin: const pw.EdgeInsets.all(4),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.6),
        borderRadius: pw.BorderRadius.circular(3),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            _labelTitle(entry.item),
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 1),
          pw.Text(
            'Sell: ${formatMoney(entry.item.sellingPrice)}',
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
            style: const pw.TextStyle(fontSize: 7),
          ),
          pw.SizedBox(height: 2),
          pw.Expanded(
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: entry.code,
              drawText: false,
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            entry.code,
            textAlign: pw.TextAlign.center,
            style: const pw.TextStyle(fontSize: 8),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfGridSlot(
    List<({Item item, String code})> pageLabels,
    int row,
    int col,
  ) {
    final index = row * _pdfCols + col;
    if (index >= pageLabels.length) return pw.SizedBox();
    return _buildLabelPdfCell(pageLabels[index]);
  }

  pw.Widget _buildPdfLabelGrid(List<({Item item, String code})> pageLabels) {
    const pageFormat = PdfPageFormat.a4;
    final cellWidth = (pageFormat.width - _pdfMargin * 2) / _pdfCols;
    final cellHeight = (pageFormat.height - _pdfMargin * 2) / _pdfRows;

    return pw.Column(
      children: [
        for (var row = 0; row < _pdfRows; row++)
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              for (var col = 0; col < _pdfCols; col++)
                pw.SizedBox(
                  width: cellWidth,
                  height: cellHeight,
                  child: _pdfGridSlot(pageLabels, row, col),
                ),
            ],
          ),
      ],
    );
  }

  Future<Uint8List> _buildPdf(List<({Item item, String code})> labels) async {
    final doc = pw.Document();

    const perPage = _pdfCols * _pdfRows;
    final pageCount = labels.isEmpty ? 0 : (labels.length / perPage).ceil();

    for (var pageIndex = 0; pageIndex < pageCount; pageIndex++) {
      final start = pageIndex * perPage;
      final end = (start + perPage).clamp(0, labels.length);
      final pageLabels = labels.sublist(start, end);

      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(_pdfMargin),
          build: (context) => _buildPdfLabelGrid(pageLabels),
        ),
      );
    }

    return doc.save();
  }

  Future<void> _printLabels() async {
    final labels = _expandedLabelsForActiveTab();
    if (labels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No barcode labels to print on this tab.')),
      );
      return;
    }

    final pdf = await _buildPdf(labels);
    await Printing.layoutPdf(
      name: 'barcode-labels',
      onLayout: (_) async => pdf,
    );
  }

  Widget _buildCopyControls(Item item) {
    final copies = _copiesFor(item);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Less copies',
          onPressed: () => _setCopies(item, copies - 1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 28,
          child: Text(
            '$copies',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton(
          tooltip: 'More copies',
          onPressed: () => _setCopies(item, copies + 1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    );
  }

  Widget _buildItemsList(List<Item> items, {bool allowRemove = false}) {
    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No items in this list.'),
        ),
      );
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = items[index];
        final code = _primaryCode(item);
        return ListTile(
          title: Text(toTitleCaseWords(item.name)),
          subtitle: Text(code),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (allowRemove)
                IconButton(
                  tooltip: 'Remove from list',
                  onPressed: () => _removeFromCustomList(item),
                  icon: const Icon(Icons.close),
                ),
              _buildCopyControls(item),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCustomTab() {
    final results = _customSearchResults;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _customSearchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search items to add to print list',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
            ),
          ),
        ),
        if (results.isNotEmpty)
          Material(
            elevation: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: results.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = results[index];
                  return ListTile(
                    dense: true,
                    title: Text(toTitleCaseWords(item.name)),
                    subtitle: Text(_primaryCode(item)),
                    trailing: IconButton(
                      tooltip: 'Add to print list',
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => _addToCustomList(item),
                    ),
                  );
                },
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Custom list (${_customItems.length})',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
        Expanded(
          child: _buildItemsList(_sortPrintable(_customItems), allowRemove: true),
        ),
      ],
    );
  }

  String get _tabSummary {
    final items = _activeTabItems;
    final labels = _expandedLabelsForActiveTab().length;
    return '${items.length} items • $labels labels';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Print barcode labels'),
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: ColoredBox(
            color: const Color(0xFF5181da),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white70,
              indicatorColor: Colors.white,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(text: 'All items'),
                Tab(text: 'Primary only'),
                Tab(text: 'Custom list'),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _tabSummary,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _printLabels,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Print'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildItemsList(_allTabItems),
                _buildItemsList(_primaryOnlyTabItems),
                _buildCustomTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
