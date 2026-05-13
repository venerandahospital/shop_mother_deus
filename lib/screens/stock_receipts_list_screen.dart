import 'package:flutter/material.dart';

import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import 'receive_stock_screen.dart';

class StockReceiptsListScreen extends StatefulWidget {
  const StockReceiptsListScreen({
    super.key,
    this.itemId,
    this.itemName,
    this.adjustmentOnly = false,
  });

  final int? itemId;
  final String? itemName;
  final bool adjustmentOnly;

  @override
  State<StockReceiptsListScreen> createState() => _StockReceiptsListScreenState();
}

class _StockReceiptsListScreenState extends State<StockReceiptsListScreen> {
  final _db = LocalDbService.instance;
  final _authService = AuthService();
  final _appSettings = AppSettingsService.instance;
  bool _loading = true;
  List<Map<String, Object?>> _rows = [];
  String _currencySymbol = 'USh';

  @override
  void initState() {
    super.initState();
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _load();
  }

  @override
  void dispose() {
    _appSettings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() {
      _currencySymbol = _appSettings.currencySymbol;
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _authService.isRemoteUser()
        ? await _authService.fetchRemoteStockReceipts()
        : await _db.getStockReceiptsWithDetails();
    final byItem = widget.itemId == null
        ? data
        : data.where((row) => row['item_id'] == widget.itemId).toList();
    final filtered = widget.adjustmentOnly
        ? byItem.where((row) {
            final brand = (row['brand'] ?? '').toString().trim();
            return brand.startsWith('ADJ|');
          }).toList()
        : byItem;
    if (!mounted) return;
    setState(() {
      _rows = filtered;
      _loading = false;
    });
  }

  Future<void> _editReceipt(Map<String, Object?> row) async {
    final isRemote = await _authService.isRemoteUser();
    if (!mounted) return;
    if (isRemote) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Editing receives is available on mother/local app.')),
      );
      return;
    }
    final receiptId = row['id'] as int?;
    if (receiptId == null) return;
    final qtyController = TextEditingController(
      text: formatDisplayNumber((row['quantity'] as num?)?.toDouble() ?? 0),
    );
    final unitCostController = TextEditingController(
      text: formatDisplayNumber((row['unit_cost'] as num?)?.toDouble() ?? 0),
    );
    final totalCostController = TextEditingController(
      text: formatDisplayNumber((row['total_cost'] as num?)?.toDouble() ?? 0),
    );
    final unitSellController = TextEditingController(
      text: formatDisplayNumber((row['unit_sell'] as num?)?.toDouble() ?? 0),
    );
    final brandController = TextEditingController(
      text: (row['brand'] as String?) ?? '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit receive'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qtyController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: unitCostController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Unit cost', prefixText: '$_currencySymbol '),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: totalCostController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Total cost', prefixText: '$_currencySymbol '),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: unitSellController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Unit sell', prefixText: '$_currencySymbol '),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: brandController,
                decoration: const InputDecoration(labelText: 'Brand'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final qty = double.tryParse(qtyController.text.replaceAll(',', '.')) ?? 0;
              final unitCost =
                  double.tryParse(unitCostController.text.replaceAll(',', '.')) ?? 0;
              final totalCost =
                  double.tryParse(totalCostController.text.replaceAll(',', '.')) ?? 0;
              final unitSell =
                  double.tryParse(unitSellController.text.replaceAll(',', '.')) ?? 0;
              if (qty <= 0 || unitSell < 0) return;
              try {
                await _db.updateStockReceipt(
                  receiptId: receiptId,
                  quantity: qty,
                  unitCost: unitCost,
                  totalCost: totalCost <= 0 ? (qty * unitCost) : totalCost,
                  sellingPrice: unitSell,
                  brand: brandController.text.trim(),
                );
                if (!ctx.mounted) return;
                Navigator.of(ctx).pop(true);
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(e.toString())),
                );
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    qtyController.dispose();
    unitCostController.dispose();
    totalCostController.dispose();
    unitSellController.dispose();
    brandController.dispose();
    if (saved == true) {
      await _load();
    }
  }

  Future<void> _deleteReceipt(
    Map<String, Object?> row, {
    bool popDetailOnSuccess = false,
  }) async {
    final receiptId = row['id'] as int?;
    if (receiptId == null) return;
    final itemName = (row['item_name'] as String?) ?? 'Item';
    final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
    final isRemote = await _authService.isRemoteUser();
    if (!mounted) return;
    final qtyLabel = formatDisplayNumber(qty.abs());
    final body = qty >= 0
        ? 'This deletes the record and reduces stock for $itemName by $qtyLabel '
            '(receive reversed / goods returned). Stock at hand must still be '
            'at least $qtyLabel.'
        : 'This deletes the adjustment record and adds $qtyLabel back to '
            'stock for $itemName.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete receive record?'),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      if (isRemote) {
        final r = await _authService.deleteRemoteStockReceipt(receiptId);
        if (!r.$1) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(r.$2)),
          );
          return;
        }
      } else {
        await _db.deleteStockReceipt(receiptId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receive record deleted')),
      );
      await _load();
      if (!mounted) return;
      if (popDetailOnSuccess && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  static String _formatDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = widget.itemName == null || widget.itemName!.trim().isEmpty
        ? (widget.adjustmentOnly ? 'Stock adjustments' : 'Receive records')
        : '${toTitleCaseWords(widget.itemName!.trim())} records';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 120),
                      Center(
                        child: Text('No receive records yet. Receive stock from the Receive stock page.'),
                      ),
                    ],
                  )
                : Builder(
                    builder: (context) {
                      final grouped = <String, List<Map<String, Object?>>>{};
                      for (final row in _rows) {
                        final receivedAt = row['received_at'] as String? ?? '';
                        final dt = DateTime.tryParse(receivedAt);
                        final dayKey = dt == null
                            ? 'Unknown date'
                            : '${dt.year.toString().padLeft(4, '0')}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
                        grouped.putIfAbsent(dayKey, () => []).add(row);
                      }

                      return ListView(
                        padding: const EdgeInsets.all(12),
                        children: grouped.entries.map((entry) {
                          final day = entry.key;
                          final dayRows = entry.value;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    day,
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  ...dayRows.map((row) {
                                    final receivedAt = row['received_at'] as String?;
                                    final itemName = toTitleCaseWords((row['item_name'] as String?) ?? '—');
                                    final qty =
                                        (row['quantity'] as num?)?.toDouble() ?? 0;
                                    final oldQty =
                                        (row['old_qty'] as num?)?.toDouble() ?? 0;
                                    final newQty =
                                        (row['new_qty'] as num?)?.toDouble() ?? 0;
                                    final brand = (row['brand'] ?? '').toString().trim();
                                    final isAdjustment = brand.startsWith('ADJ|');
                                    final reason = isAdjustment
                                        ? brand.substring(4).trim()
                                        : '';
                                    return ListTile(
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 0,
                                        vertical: 4,
                                      ),
                                      title: Text(
                                        itemName,
                                        style: theme.textTheme.titleSmall?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      subtitle: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${isAdjustment ? 'Quantity adjusted' : 'Quantity received'}: ${formatDisplayNumber(qty)}',
                                          ),
                                          Text(
                                            'Previous quantity: ${formatDisplayNumber(oldQty)}',
                                          ),
                                          Text(
                                            'New quantity: ${formatDisplayNumber(newQty)}',
                                          ),
                                          Text(
                                            'Receive date: ${_formatDate(receivedAt)}',
                                          ),
                                          if (isAdjustment && reason.isNotEmpty)
                                            Text('Reason: $reason'),
                                        ],
                                      ),
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                            tooltip: 'Edit receive',
                                            icon: const Icon(Icons.edit_outlined),
                                            onPressed: () => _editReceipt(row),
                                          ),
                                          IconButton(
                                            tooltip: 'Delete receive',
                                            icon: Icon(
                                              Icons.delete_outline,
                                              color: theme.colorScheme.error,
                                            ),
                                            onPressed: () => _deleteReceipt(row),
                                          ),
                                          const Icon(Icons.chevron_right),
                                        ],
                                      ),
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                _StockReceiptDetailsScreen(
                                              row: row,
                                              currencySymbol: _currencySymbol,
                                              onDelete: () => _deleteReceipt(
                                                row,
                                                popDetailOnSuccess: true,
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  }),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  ),
      ),
      floatingActionButton: widget.adjustmentOnly
          ? null
          : FloatingActionButton(
              tooltip: 'Receive stock',
              onPressed: () async {
                final changed = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => ReceiveStockScreen(initialItemId: widget.itemId),
                  ),
                );
                if (changed == true) {
                  await _load();
                }
              },
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _StockReceiptDetailsScreen extends StatelessWidget {
  const _StockReceiptDetailsScreen({
    required this.row,
    required this.currencySymbol,
    required this.onDelete,
  });

  final Map<String, Object?> row;
  final String currencySymbol;
  final VoidCallback onDelete;

  static String _formatDate(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _formatDateOnly(String? iso) {
    if (iso == null) return '—';
    final d = DateTime.tryParse(iso);
    if (d == null) return '—';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final itemName = toTitleCaseWords((row['item_name'] as String?) ?? '—');
    final expiry = row['expiry_date'] as String?;
    final receivedAt = row['received_at'] as String?;
    final totalCost = (row['total_cost'] as num?)?.toDouble() ?? 0;
    final unitCost = (row['unit_cost'] as num?)?.toDouble() ?? 0;
    final unitSell = (row['unit_sell'] as num?)?.toDouble() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive record details'),
        actions: [
          IconButton(
            tooltip: 'Delete receive record',
            icon: const Icon(Icons.delete_outline),
            onPressed: onDelete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            itemName,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _DetailTile(label: 'Expiry date', value: _formatDateOnly(expiry)),
          _DetailTile(
            label: 'Total cost',
            value: '$currencySymbol${formatMoney(totalCost)}',
          ),
          _DetailTile(
            label: 'Unit cost',
            value: '$currencySymbol${formatMoney(unitCost)}',
          ),
          _DetailTile(label: 'Receive date', value: _formatDate(receivedAt)),
          _DetailTile(
            label: 'Unit sell',
            value: '$currencySymbol${formatMoney(unitSell)}',
          ),
        ],
      ),
    );
  }
}

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          const SizedBox(width: 12),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
