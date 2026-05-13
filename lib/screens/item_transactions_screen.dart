import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/app_settings_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';

class ItemTransactionsScreen extends StatefulWidget {
  const ItemTransactionsScreen({super.key, required this.item});

  final Item item;

  @override
  State<ItemTransactionsScreen> createState() => _ItemTransactionsScreenState();
}

class _ItemEvent {
  const _ItemEvent({
    required this.type,
    required this.dateTime,
    required this.stockDelta,
    required this.label,
    required this.reference,
  });

  final String type;
  final DateTime dateTime;
  /// Signed change to on-hand stock (+ adds, − removes).
  final double stockDelta;
  final String label;
  final String reference;
}

class _ItemTransactionsScreenState extends State<ItemTransactionsScreen> {
  final _db = LocalDbService.instance;
  final _auth = AuthService();
  final _settings = AppSettingsService.instance;
  bool _loading = true;
  String _currencySymbol = 'USh';
  List<_ItemEvent> _events = [];

  @override
  void initState() {
    super.initState();
    _currencySymbol = _settings.currencySymbol;
    _settings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _load();
  }

  @override
  void dispose() {
    _settings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() => _currencySymbol = _settings.currencySymbol);
  }

  static bool _isAdjustmentReceipt(Map<String, Object?> row) {
    final brand = (row['brand'] ?? '').toString().trim();
    return brand.startsWith('ADJ|');
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final events = <_ItemEvent>[];
    final itemId = widget.item.id;
    if (itemId == null || itemId <= 0) {
      if (!mounted) return;
      setState(() {
        _events = const <_ItemEvent>[];
        _loading = false;
      });
      return;
    }

    final isRemote = await _auth.isRemoteUser();
    if (isRemote) {
      final rows = await _auth.fetchRemoteItemTransactions(itemId);
      for (final row in rows) {
        final dt = DateTime.tryParse((row['date'] ?? '').toString());
        if (dt == null) continue;
        final type = (row['type'] ?? '').toString().trim();
        final reference = (row['reference'] ?? '-').toString();
        final quantity = (row['quantity'] as num?)?.toDouble() ?? 0;

        final stockDelta = switch (type) {
          'receive' || 'adjustment' => quantity,
          'sale' => -quantity.abs(),
          'transfer_in' => quantity.abs(),
          'transfer_out' => -quantity.abs(),
          _ => quantity,
        };

        final label = switch (type) {
          'receive' => 'Stock received',
          'adjustment' => 'Stock adjustment',
          'sale' => 'Sold',
          'transfer_in' => 'Transferred in',
          'transfer_out' => 'Transferred out',
          _ => 'Transaction',
        };
        final refLabel = switch (type) {
          'receive' => 'Receipt #$reference',
          'adjustment' => 'Adjustment #$reference',
          'sale' => 'Sale #$reference',
          'transfer_in' || 'transfer_out' => 'Transfer #$reference',
          _ => 'Ref #$reference',
        };
        events.add(
          _ItemEvent(
            type: type,
            dateTime: dt,
            stockDelta: stockDelta,
            label: label,
            reference: refLabel,
          ),
        );
      }
    } else {
      final receipts = await _db.getStockReceiptsForItemWithDetails(itemId);
      final sales = await _db.getSaleRowsForItem(itemId);
      final transfers = await _db.getTransferRowsForItem(itemId);

      for (final row in receipts) {
        final dt = DateTime.tryParse((row['received_at'] as String?) ?? '');
        if (dt == null) continue;
        final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
        final isAdj = _isAdjustmentReceipt(row);
        events.add(
          _ItemEvent(
            type: isAdj ? 'adjustment' : 'receive',
            dateTime: dt,
            stockDelta: qty,
            label: isAdj ? 'Stock adjustment' : 'Stock received',
            reference: isAdj
                ? 'Adjustment #${row['id'] ?? '-'}'
                : 'Receipt #${row['id'] ?? '-'}',
          ),
        );
      }
      for (final row in sales) {
        final dt = DateTime.tryParse((row['sold_at'] as String?) ?? '');
        if (dt == null) continue;
        final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
        events.add(
          _ItemEvent(
            type: 'sale',
            dateTime: dt,
            stockDelta: -qty.abs(),
            label: 'Sold',
            reference: 'Sale #${row['sale_id'] ?? '-'}',
          ),
        );
      }
      for (final row in transfers) {
        final dt = DateTime.tryParse((row['created_at'] as String?) ?? '');
        if (dt == null) continue;
        final isSource = row['from_item_id'] == itemId;
        final fromQty =
            (row['from_quantity'] as num?)?.toDouble() ?? 0;
        if (isSource && fromQty <= 0) continue;
        final q = ((isSource ? row['from_quantity'] : row['to_quantity']) as num?)
                ?.toDouble() ??
            0;
        final newFrom = (row['new_from_qty'] as num?)?.toDouble();
        final unit = _unitLabel();
        final ref = isSource && newFrom != null
            ? 'Transfer #${row['id'] ?? '-'} (stock left ${formatDisplayNumber(newFrom)} $unit)'
            : 'Transfer #${row['id'] ?? '-'}';
        events.add(
          _ItemEvent(
            type: isSource ? 'transfer_out' : 'transfer_in',
            dateTime: dt,
            stockDelta: isSource ? -q.abs() : q.abs(),
            label: isSource ? 'Transferred out' : 'Transferred in',
            reference: ref,
          ),
        );
      }
    }

    events.sort((a, b) => b.dateTime.compareTo(a.dateTime));
    if (!mounted) return;
    setState(() {
      _events = events;
      _loading = false;
    });
  }

  String _fmtDate(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _unitLabel() {
    final u = (widget.item.unit ?? widget.item.unitShort ?? '').trim();
    return u.isEmpty ? 'units' : u;
  }

  String _directionLabel(double stockDelta) {
    if (stockDelta > 0) return 'In';
    if (stockDelta < 0) return 'Out';
    return '—';
  }

  IconData _iconFor(_ItemEvent e) {
    return switch (e.type) {
      'receive' => Icons.move_to_inbox_outlined,
      'adjustment' => Icons.tune_outlined,
      'sale' => Icons.shopping_cart_checkout,
      'transfer_in' || 'transfer_out' => Icons.swap_horiz,
      _ => Icons.receipt_long_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unitLabel = _unitLabel();

    return Scaffold(
      appBar: AppBar(
        title: Text('${toTitleCaseWords(widget.item.name)} transactions'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _events.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No stock transactions found for this item yet.')),
                    ],
                  )
                : Builder(
                    builder: (context) {
                      double runningAfter = widget.item.stockQty;
                      return ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _events.length,
                        itemBuilder: (context, index) {
                          final e = _events[index];
                          final d = e.stockDelta;
                          final isIn = d > 0;
                          final isOut = d < 0;
                          final color =
                              isIn ? Colors.green : (isOut ? Colors.red : Colors.grey);
                          final before = runningAfter - d;
                          final after = runningAfter;
                          runningAfter = before;

                          final direction = _directionLabel(d);
                          final qtyText =
                              '${d >= 0 ? '+' : ''}${formatDisplayNumber(d)} $unitLabel';

                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        _iconFor(e),
                                        color: color,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              e.label,
                                              style: theme.textTheme.titleSmall?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Direction: $direction',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: Colors.grey[700],
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        qtyText,
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          color: color,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${e.reference}  •  ${_fmtDate(e.dateTime)}',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Stock: ${formatDisplayNumber(before)} → ${formatDisplayNumber(after)} $unitLabel',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (isOut) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Value moved: $_currencySymbol${formatMoney(d.abs() * widget.item.sellingPrice)}',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}
