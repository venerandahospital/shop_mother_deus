import 'package:flutter/material.dart';

import '../models/item.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';

class ItemDetailsScreen extends StatelessWidget {
  const ItemDetailsScreen({
    super.key,
    required this.item,
    required this.currencySymbol,
  });

  final Item item;
  final String currencySymbol;

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
    final saleCategory = _saleCategoryLabel(item.category);
    final businessCategory = _businessCategoryLabel(item.category);
    final unitLabel = (item.unitShort ?? item.unit ?? '').trim();
    final imageUrls = <String>[
      (item.imageUrl ?? '').trim(),
      (item.imageUrl2 ?? '').trim(),
      (item.imageUrl3 ?? '').trim(),
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
            toTitleCaseWords(item.name),
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
                    '${formatDisplayNumber(item.stockQty)} ${unitLabel.isEmpty ? '' : unitLabel}',
                  ),
                  _detailRow(
                    context,
                    'Selling price',
                    '$currencySymbol${formatMoney(item.sellingPrice)}',
                  ),
                  _detailRow(
                    context,
                    'Cost price',
                    '$currencySymbol${formatMoney(item.costPrice)}',
                  ),
                  _detailRow(
                    context,
                    'Reorder level',
                    formatDisplayNumber(item.reorderLevel),
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
                    (item.barcode ?? '').trim().isEmpty
                        ? '-'
                        : item.barcode!.trim(),
                  ),
                  _detailRow(
                    context,
                    'SKU',
                    (item.sku ?? '').trim().isEmpty ? '-' : item.sku!.trim(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
