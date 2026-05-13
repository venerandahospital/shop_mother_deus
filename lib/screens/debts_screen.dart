import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/debt.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../widgets/bottom_nav.dart';
import '../widgets/section_page_title.dart';
import 'client_details_screen.dart';
import 'debt_payments_screen.dart';
import 'main_navigation_screen.dart';
import 'pay_debt_screen.dart';

enum _DebtsQuickRange { today, lastWeek, lastMonth, all }

class DebtsScreen extends StatefulWidget {
  const DebtsScreen({super.key});

  @override
  State<DebtsScreen> createState() => _DebtsScreenState();
}

class _DebtsScreenState extends State<DebtsScreen> {
  final _db = LocalDbService.instance;
  final _authService = AuthService();
  final _appSettings = AppSettingsService.instance;

  bool _loading = true;
  List<Debt> _allDebts = [];
  List<Map<String, Object?>> _clientDebts = [];
  String _currencySymbol = 'USh';
  _DebtsQuickRange _quickRange = _DebtsQuickRange.all;

  @override
  void initState() {
    super.initState();
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _loadDebts();
  }

  Future<void> _goToNavTab(int index) async {
    if (index == 0) {
      final popped = await Navigator.of(context).maybePop();
      if (popped) return;
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MainNavigationScreen(initialIndex: index),
      ),
    );
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

  bool _inQuickRange(DateTime createdAt) {
    if (_quickRange == _DebtsQuickRange.all) return true;
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    late final DateTime start;
    switch (_quickRange) {
      case _DebtsQuickRange.today:
        start = startOfToday;
        break;
      case _DebtsQuickRange.lastWeek:
        start = startOfToday.subtract(const Duration(days: 6));
        break;
      case _DebtsQuickRange.lastMonth:
        start = DateTime(now.year, now.month - 1, now.day);
        break;
      case _DebtsQuickRange.all:
        start = DateTime(2000);
        break;
    }
    final end = DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
    return !createdAt.isBefore(start) && !createdAt.isAfter(end);
  }

  List<Map<String, Object?>> _aggregateClientDebts(List<Debt> debts) {
    final clientDebts = <String, Map<String, Object?>>{};
    for (final debt in debts) {
      if (!_inQuickRange(debt.createdAt)) continue;
      final key = debt.customerName.trim().toLowerCase();
      final existing = clientDebts[key];
      if (existing == null) {
        clientDebts[key] = {
          'customer_name': debt.customerName.trim(),
          'phone': debt.phone,
          'address': debt.address,
          'amount': debt.amount,
          'entries': 1,
          'oldest_date': debt.createdAt,
        };
      } else {
        existing['amount'] = ((existing['amount'] as double?) ?? 0) + debt.amount;
        existing['entries'] = ((existing['entries'] as int?) ?? 0) + 1;
        final old = existing['oldest_date'] as DateTime?;
        if (old == null || debt.createdAt.isBefore(old)) {
          existing['oldest_date'] = debt.createdAt;
        }
      }
    }
    final list = clientDebts.values.toList();
    list.sort((a, b) => ((b['amount'] as double?) ?? 0).compareTo((a['amount'] as double?) ?? 0));
    return list;
  }

  void _setQuickRange(_DebtsQuickRange range) {
    if (_quickRange == range) return;
    setState(() {
      _quickRange = range;
      _clientDebts = _aggregateClientDebts(_allDebts);
    });
  }

  Future<void> _loadDebts() async {
    setState(() => _loading = true);
    final debts = await _authService.isRemoteUser()
        ? await _authService.fetchRemoteDebts(isPaid: false)
        : await _db.getDebts(isPaid: false);
    final list = _aggregateClientDebts(debts);
    if (!mounted) return;
    setState(() {
      _allDebts = debts;
      _clientDebts = list;
      _loading = false;
    });
  }

  Future<void> _openPayDebtPage({
    required String customerName,
    required double amountOwed,
  }) async {
    final client = await _db.getClientByNormalizedName(customerName);
    final msg = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => PayDebtScreen(
          customerName: customerName,
          amountOwed: amountOwed,
          client: client,
        ),
      ),
    );
    if (msg == null) return;
    if (!mounted) return;
    await _loadDebts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Debts'),
        actions: [
          IconButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const DebtPaymentsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.history),
            tooltip: 'Payment history',
          ),
          IconButton(
            onPressed: _loadDebts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDebts,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            selected: _quickRange == _DebtsQuickRange.today,
                            selectedColor: Colors.lightGreen.shade100,
                            label: const Text('Today'),
                            onSelected: (_) => _setQuickRange(_DebtsQuickRange.today),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            selected: _quickRange == _DebtsQuickRange.lastWeek,
                            selectedColor: Colors.lightGreen.shade100,
                            label: const Text('Last week'),
                            onSelected: (_) => _setQuickRange(_DebtsQuickRange.lastWeek),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            selected: _quickRange == _DebtsQuickRange.lastMonth,
                            selectedColor: Colors.lightGreen.shade100,
                            label: const Text('Last month'),
                            onSelected: (_) => _setQuickRange(_DebtsQuickRange.lastMonth),
                          ),
                          const SizedBox(width: 6),
                          ChoiceChip(
                            showCheckmark: false,
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            selected: _quickRange == _DebtsQuickRange.all,
                            selectedColor: Colors.lightGreen.shade100,
                            label: const Text('All'),
                            onSelected: (_) => _setQuickRange(_DebtsQuickRange.all),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total debts',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$_currencySymbol${formatMoney(_clientDebts.fold<double>(0, (s, v) => s + ((v['amount'] as double?) ?? 0)))}',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_clientDebts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 80),
                      child: Center(
                        child: Text('No active debts'),
                      ),
                    )
                  else
                    ..._clientDebts.map((debt) {
                      final customerName = (debt['customer_name'] as String?) ?? 'Client';
                      final amount = (debt['amount'] as double?) ?? 0;
                      final phone = debt['phone'] as String?;
                      final address = debt['address'] as String?;
                      final oldestDate = debt['oldest_date'] as DateTime?;
                      final entries = (debt['entries'] as int?) ?? 0;
                      final client = Client(
                        name: customerName,
                        phone: phone?.trim().isEmpty ?? true ? null : phone?.trim(),
                        address: address?.trim().isEmpty ?? true ? null : address?.trim(),
                      );
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        child: ListTile(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => ClientDetailsScreen(client: client),
                              ),
                            ).then((_) => _loadDebts());
                          },
                          title: Text(customerName.toUpperCase()),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$_currencySymbol${formatMoney(amount)}',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (phone != null && phone.trim().isNotEmpty)
                                Text(
                                  phone,
                                  style: theme.textTheme.bodySmall,
                                ),
                              if (address != null && address.trim().isNotEmpty)
                                Text(
                                  address,
                                  style: theme.textTheme.bodySmall,
                                ),
                              Text(
                                '${entries == 1 ? '1 debt entry' : '$entries debt entries'}'
                                '${oldestDate == null ? '' : '  •  Since ${oldestDate.toLocal().toString().split('.').first}'}',
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: Colors.grey),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.payments_outlined),
                            tooltip: 'Pay debt',
                            onPressed: amount > 0
                                ? () => _openPayDebtPage(
                                      customerName: customerName,
                                      amountOwed: amount,
                                    )
                                : null,
                          ),
                        ),
                      );
                    }),
                ],
              ),
      ),
      bottomNavigationBar: BottomNav(
        currentIndex: 0,
        onTap: _goToNavTab,
        showSettings: true,
      ),
    );
  }

}



