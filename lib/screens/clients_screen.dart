import 'package:flutter/material.dart';

import '../models/client.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../widgets/section_page_title.dart';
import 'client_account_screen.dart';
import 'client_details_screen.dart';
import 'pay_debt_screen.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _db = LocalDbService.instance;
  final _authService = AuthService();
  final _appSettings = AppSettingsService.instance;
  final _searchController = TextEditingController();

  bool _loading = true;
  List<Client> _clients = [];
  Map<String, double> _debtByClientName = {};
  Map<int, double> _accountBalanceByClientId = {};
  String _currencySymbol = 'USh';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _currencySymbol = _appSettings.currencySymbol;
    _appSettings.currencySymbolNotifier.addListener(_onCurrencyChanged);
    _loadClients();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _appSettings.currencySymbolNotifier.removeListener(_onCurrencyChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onCurrencyChanged() {
    if (!mounted) return;
    setState(() {
      _currencySymbol = _appSettings.currencySymbol;
    });
  }

  Future<void> _loadClients() async {
    setState(() => _loading = true);
    try {
      final isRemote = await _authService.isRemoteUser();
      final clients = isRemote
          ? await _authService.fetchRemoteClients()
          : await _db.getClients();
      final debts = isRemote
          ? await _authService.fetchRemoteDebts(isPaid: false)
          : await _db.getDebts(isPaid: false);
      final debtByName = <String, double>{};
      for (final debt in debts) {
        final key = debt.customerName.trim().toLowerCase();
        debtByName[key] = (debtByName[key] ?? 0) + debt.amount;
      }
      if (!mounted) return;
      final balances = <int, double>{};
      for (final c in clients) {
        if (c.id == null) continue;
        if (isRemote) {
          final value = await _authService.fetchRemoteClientAccountBalance(c.id!);
          balances[c.id!] = value ?? 0;
        } else {
          balances[c.id!] = await _db.getClientAccountBalance(c.id!);
        }
      }
      setState(() {
        _clients = clients;
        _debtByClientName = debtByName;
        _accountBalanceByClientId = balances;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load clients: $e')),
      );
    }
  }

  List<Client> get _visibleClients {
    if (_searchQuery.isEmpty) return _clients;
    return _clients.where((client) {
      final name = client.name.toLowerCase();
      final phone = (client.phone ?? '').toLowerCase();
      final address = (client.address ?? '').toLowerCase();
      return name.contains(_searchQuery) ||
          phone.contains(_searchQuery) ||
          address.contains(_searchQuery);
    }).toList();
  }

  Future<void> _showClientDialog({Client? client}) async {
    final nameController = TextEditingController(text: client?.name ?? '');
    final phoneController = TextEditingController(text: client?.phone ?? '');
    final addressController =
        TextEditingController(text: client?.address ?? '');

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(client == null ? 'New client' : 'Edit client'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Client name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: addressController,
                  maxLines: 2,
                  decoration: const InputDecoration(labelText: 'Address'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                final newClient = Client(
                  id: client?.id,
                  storeId: client?.storeId,
                  name: name,
                  phone: phoneController.text.trim().isEmpty
                      ? null
                      : phoneController.text.trim(),
                  address: addressController.text.trim().isEmpty
                      ? null
                      : addressController.text.trim(),
                );
                try {
                  if (await _authService.isRemoteUser()) {
                    final remote = await _authService.saveRemoteClient(
                      id: client?.id,
                      storeId: client?.storeId,
                      name: name,
                      phone: phoneController.text.trim(),
                      address: addressController.text.trim(),
                    );
                    if (!remote.$1) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(remote.$2)),
                      );
                      return;
                    }
                  }
                  await _db.upsertClient(newClient);
                  if (!mounted) return;
                  Navigator.of(context).pop();
                  await _loadClients();
                } catch (e) {
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to save client: $e')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openPayDebtPage({
    required Client client,
    required String customerName,
    required double amountOwed,
  }) async {
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
    await _loadClients();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const SectionPageTitle(pageTitle: 'Clients'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadClients,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search clients by name, phone, or address',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Row(
              children: [
                _smallStatChip(
                  label: 'Clients',
                  value: '${_clients.length}',
                  color: Colors.blue,
                ),
                const SizedBox(width: 8),
                _smallStatChip(
                  label: 'With debt',
                  value:
                      '${_clients.where((c) => (_debtByClientName[c.name.trim().toLowerCase()] ?? 0) > 0).length}',
                  color: Colors.red,
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _loadClients,
              child: _loading
                  ? ListView(
                      children: const [
                        SizedBox(height: 160),
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : _clients.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(
                              child: Text('No clients yet. Add your first client.'),
                            ),
                          ],
                        )
                      : _visibleClients.isEmpty
                          ? ListView(
                              children: const [
                                SizedBox(height: 120),
                                Center(
                                  child: Text('No clients match your search.'),
                                ),
                              ],
                            )
                          : ListView(
                              padding: const EdgeInsets.only(bottom: 12),
                              children: _visibleClients.map((client) {
                                final debtAmount =
                                    _debtByClientName[client.name.trim().toLowerCase()] ?? 0;
                                final accountBalance = client.id == null
                                    ? 0.0
                                    : (_accountBalanceByClientId[client.id!] ?? 0);
                                return Card(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  elevation: 1,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => ClientDetailsScreen(client: client),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor:
                                                theme.colorScheme.primaryContainer.withOpacity(0.55),
                                            child: Text(
                                              client.name.isNotEmpty
                                                  ? client.name[0].toUpperCase()
                                                  : '?',
                                              style: const TextStyle(fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  client.name.toUpperCase(),
                                                  style: theme.textTheme.titleSmall?.copyWith(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                if (client.phone != null &&
                                                    client.phone!.trim().isNotEmpty)
                                                  Text(
                                                    client.phone!,
                                                    style: theme.textTheme.bodySmall,
                                                  ),
                                                if (client.address != null &&
                                                    client.address!.trim().isNotEmpty)
                                                  Text(
                                                    client.address!,
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: Colors.grey[700],
                                                    ),
                                                  ),
                                                if (debtAmount > 0) ...[
                                                  const SizedBox(height: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 3,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.red.withOpacity(0.12),
                                                      borderRadius: BorderRadius.circular(999),
                                                    ),
                                                    child: Text(
                                                      'Debt $_currencySymbol${formatMoney(debtAmount)}',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: Colors.red,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                                const SizedBox(height: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.green.withOpacity(0.12),
                                                    borderRadius: BorderRadius.circular(999),
                                                  ),
                                                  child: Text(
                                                    'Account $_currencySymbol${formatMoney(accountBalance)}',
                                                    style: theme.textTheme.bodySmall?.copyWith(
                                                      color: Colors.green.shade800,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.edit),
                                                onPressed: () => _showClientDialog(client: client),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.payments_outlined),
                                                tooltip: 'Pay debt',
                                                onPressed: debtAmount > 0
                                                    ? () => _openPayDebtPage(
                                                          client: client,
                                                          customerName: client.name,
                                                          amountOwed: debtAmount,
                                                        )
                                                    : null,
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.account_balance_wallet_outlined),
                                                tooltip: 'Open account',
                                                onPressed: client.id == null
                                                    ? null
                                                    : () async {
                                                        await Navigator.of(context).push(
                                                          MaterialPageRoute(
                                                            builder: (_) => ClientAccountScreen(
                                                              client: client,
                                                            ),
                                                          ),
                                                        );
                                                        await _loadClients();
                                                      },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showClientDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add client'),
      ),
    );
  }

  Widget _smallStatChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label),
            Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

