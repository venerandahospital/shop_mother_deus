import 'package:flutter/material.dart';

import '../models/item.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';
import 'stock_take_screen.dart';

class ItemDetailsScreen extends StatefulWidget {
  const ItemDetailsScreen({
    super.key,
    required this.item,
    required this.currencySymbol,
  });

  final Item item;
  final String currencySymbol;

  @override
  State<ItemDetailsScreen> createState() => _ItemDetailsScreenState();
}

class _ItemDetailsScreenState extends State<ItemDetailsScreen> {
  final _db = LocalDbService.instance;
  final _authService = AuthService();
  late Item _item;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  String _saleCategoryLabel(String? category) {
    final raw = (category ?? '').trim();
    if (raw.isEmpty) return '';
    final parts = raw.split('|').map((p) => p.trim());
    for (final part in parts) {
      if (part.toLowerCase().startsWith('sale:')) {
        return toTitleCaseWords(part.substring(5).trim());
      }
    }
    return '';
  }

  String _businessCategoryLabel(String? category) {
    final raw = (category ?? '').trim();
    if (raw.isEmpty) return '';
    final parts = raw.split('|').map((p) => p.trim());
    for (final part in parts) {
      if (part.toLowerCase().startsWith('business:')) {
        return toTitleCaseWords(part.substring(9).trim());
      }
    }
    return '';
  }

  bool get _isServiceItem {
    final raw = (_item.category ?? '').trim().toLowerCase();
    return raw.contains('sale: service');
  }

  Future<void> _markNotCounted() async {
    if (_item.id == null || _busy) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark for re-count?'),
        content: Text(
          '${toTitleCaseWords(_item.name)} will appear on Stock take. '
          'Sales will not check stock until you count and mark it counted again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Not counted'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    if (await _authService.isRemoteUser()) {
      final remote = await _authService.saveRemoteItem({
        'id': _item.id,
        'name': _item.name,
        'stockHandCounted': false,
      });
      if (!remote.$1) {
        if (mounted) {
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(remote.$2)),
          );
        }
        return;
      }
    }

    await _db.setStockHandCounted(_item.id!, false);
    final fresh = await _db.getItemById(_item.id!);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (fresh != null) _item = fresh;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${toTitleCaseWords(_item.name)} marked not counted'),
        action: SnackBarAction(
          label: 'Open list',
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const StockTakeScreen(),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _detailRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final saleCategory = _saleCategoryLabel(_item.category);
    final businessCategory = _businessCategoryLabel(_item.category);
    final unitLabel = (_item.unitShort ?? _item.unit ?? '').trim();
    final imageUrls = <String>[
      (_item.imageUrl ?? '').trim(),
      (_item.imageUrl2 ?? '').trim(),
      (_item.imageUrl3 ?? '').trim(),
    ].where((e) => e.isNotEmpty).toList();

    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Item details'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Container(
                color: Colors.grey.shade100,
                child: imageUrls.isEmpty
                    ? const Icon(Icons.image_outlined, size: 42)
                    : PageView.builder(
                        itemCount: imageUrls.length,
                        itemBuilder: (context, index) {
                          return Image.network(
                            imageUrls[index],
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                              Icons.broken_image_outlined,
                              size: 42,
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            toTitleCaseWords(_item.name),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _detailRow(
                    context,
                    'Stock',
                    '${formatDisplayNumber(_item.stockQty)} ${unitLabel.isEmpty ? '' : unitLabel}',
                  ),
                  if (!_isServiceItem)
                    _detailRow(
                      context,
                      'Stock at hand',
                      _item.stockHandCounted ? 'Counted' : 'Not counted',
                    ),
                  _detailRow(
                    context,
                    'Selling price',
                    '${widget.currencySymbol}${formatMoney(_item.sellingPrice)}',
                  ),
                  _detailRow(
                    context,
                    'Cost price',
                    '${widget.currencySymbol}${formatMoney(_item.costPrice)}',
                  ),
                  _detailRow(
                    context,
                    'Reorder level',
                    formatDisplayNumber(_item.reorderLevel),
                  ),
                  _detailRow(
                    context,
                    'Sale category',
                    saleCategory.isEmpty ? '-' : saleCategory,
                  ),
                  _detailRow(
                    context,
                    'Business category',
                    businessCategory.isEmpty ? '-' : businessCategory,
                  ),
                  _detailRow(
                    context,
                    'Barcode',
                    (_item.barcode ?? '').trim().isEmpty
                        ? '-'
                        : _item.barcode!.trim(),
                  ),
                  _detailRow(
                    context,
                    'SKU',
                    (_item.sku ?? '').trim().isEmpty ? '-' : _item.sku!.trim(),
                  ),
                ],
              ),
            ),
          ),
          if (!_isServiceItem && _item.stockHandCounted) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _markNotCounted,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.fact_check_outlined),
              label: const Text('Mark not counted (re-count)'),
            ),
          ],
        ],
      ),
    );
  }
}
