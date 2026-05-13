import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../utils/text_format.dart';

class StockTransfersListScreen extends StatefulWidget {
  const StockTransfersListScreen({super.key});

  @override
  State<StockTransfersListScreen> createState() => _StockTransfersListScreenState();
}

class _StockTransfersListScreenState extends State<StockTransfersListScreen> {
  final _db = LocalDbService.instance;
  final _authService = AuthService();
  bool _loading = true;
  List<Map<String, Object?>> _rows = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _authService.isRemoteUser()
        ? await _authService.fetchRemoteStockTransfers()
        : await _db.getStockTransfersWithDetails();
    if (!mounted) return;
    setState(() {
      _rows = data
          .where((r) {
            final fq = (r['from_quantity'] as num?)?.toDouble() ?? 0;
            return fq > 0;
          })
          .toList();
      _loading = false;
    });
  }

  String _fmtDate(String? iso) {
    final d = DateTime.tryParse(iso ?? '');
    if (d == null) return '—';
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock transfers'),
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
                      Center(child: Text('No transfers found yet.')),
                    ],
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _rows.length,
                    itemBuilder: (context, index) {
                      final row = _rows[index];
                      final fromName = toTitleCaseWords((row['from_item_name'] as String?) ?? '—');
                      final toName = toTitleCaseWords((row['to_item_name'] as String?) ?? '—');
                      final fromQty = (row['from_quantity'] as num?)?.toDouble() ?? 0;
                      final toQty = (row['to_quantity'] as num?)?.toDouble() ?? 0;
                      final newFrom =
                          (row['new_from_qty'] as num?)?.toDouble();
                      final fromUnit = ((row['from_item_unit'] as String?) ?? '').trim();
                      final toUnit = ((row['to_item_unit'] as String?) ?? '').trim();
                      final note = ((row['notes'] as String?) ?? '').trim();
                      final fromUnitSuffix = fromUnit.isEmpty ? '' : ' $fromUnit';
                      final toUnitSuffix = toUnit.isEmpty ? '' : ' $toUnit';
                      final leftLine = newFrom == null
                          ? ''
                          : ' • Source stock left ${formatDisplayNumber(newFrom)}$fromUnitSuffix';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$fromName  ->  $toName',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Transferred out ${formatDisplayNumber(fromQty)}$fromUnitSuffix from source$leftLine',
                                style: theme.textTheme.bodyMedium,
                              ),
                              Text(
                                'Added ${formatDisplayNumber(toQty)}$toUnitSuffix on destination',
                                style: theme.textTheme.bodyMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Transfer #${row['id'] ?? '-'}  •  ${_fmtDate(row['created_at'] as String?)}',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey[700]),
                              ),
                              if (note.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Notes: $note',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ],
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
