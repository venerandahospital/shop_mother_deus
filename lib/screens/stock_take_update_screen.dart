import 'package:flutter/material.dart';

import '../models/item.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';
import '../widgets/section_page_title.dart';

/// Full-page editor for setting absolute stock qty during stock take.
/// Pops with the entered quantity on save, or null if cancelled.
class StockTakeUpdateScreen extends StatefulWidget {
  const StockTakeUpdateScreen({super.key, required this.item});

  final Item item;

  @override
  State<StockTakeUpdateScreen> createState() => _StockTakeUpdateScreenState();
}

class _StockTakeUpdateScreenState extends State<StockTakeUpdateScreen> {
  final _qtyController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _qtyController.text = formatDisplayNumber(widget.item.stockQty);
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final qty =
        double.tryParse(_qtyController.text.replaceAll(',', '.')) ?? -1;
    if (qty < 0) return;
    Navigator.of(context).pop(qty);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unit = (widget.item.unit ?? widget.item.unitShort ?? '').trim();

    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Update stock'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              toTitleCaseWords(widget.item.name),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if ((widget.item.category ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.item.category!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade700,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Current stock',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatDisplayNumber(widget.item.stockQty)}${unit.isEmpty ? '' : ' $unit'}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _qtyController,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: unit.isEmpty ? 'New stock quantity' : 'New stock ($unit)',
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                final raw = (value ?? '').trim();
                if (raw.isEmpty) return 'Enter a quantity';
                final qty = double.tryParse(raw.replaceAll(',', '.'));
                if (qty == null || qty < 0) return 'Enter a valid quantity';
                return null;
              },
              onFieldSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: _save,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Text('Save stock'),
            ),
          ),
        ),
      ),
    );
  }
}
