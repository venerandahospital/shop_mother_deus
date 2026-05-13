import 'package:flutter/material.dart';

import '../models/client.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../utils/number_display.dart';
import '../widgets/section_page_title.dart';

const _kSaleFlowScaffoldBg = Color(0xFFF4F5F7);
const _kSaleFlowAppBarBlue = Color(0xFF5181da);

class SaleClientScreen extends StatefulWidget {
  const SaleClientScreen({
    super.key,
    required this.clients,
    this.selectedClient,
  });

  final List<Client> clients;
  final Client? selectedClient;

  @override
  State<SaleClientScreen> createState() => _SaleClientScreenState();
}

class _SaleClientScreenState extends State<SaleClientScreen> {
  final _db = LocalDbService.instance;
  final _authService = AuthService();
  final TextEditingController _searchController = TextEditingController();
  late List<Client> _clients;
  Map<int, double> _balancesByClientId = const {};

  @override
  void initState() {
    super.initState();
    _clients = List<Client>.from(widget.clients);
    _searchController.addListener(() => setState(() {}));
    _loadBalances();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Client> get _filteredClients {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _clients;
    return _clients.where((c) {
      final name = c.name.toLowerCase();
      final phone = (c.phone ?? '').toLowerCase();
      final address = (c.address ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q) || address.contains(q);
    }).toList();
  }

  String _clientLabel(Client client) {
    final phone = (client.phone ?? '').trim();
    if (phone.isEmpty) return client.name.toUpperCase();
    return '${client.name.toUpperCase()} ($phone)';
  }

  Future<void> _loadBalances() async {
    final ids = _clients.map((c) => c.id).whereType<int>().toList();
    if (ids.isEmpty) return;
    final isRemote = await _authService.isRemoteUser();
    final balances = <int, double>{};
    if (isRemote) {
      final futures = ids.map((id) async {
        final value = await _authService.fetchRemoteClientAccountBalance(id);
        return MapEntry(id, value ?? 0);
      }).toList();
      final entries = await Future.wait(futures);
      for (final e in entries) {
        balances[e.key] = e.value;
      }
    } else {
      final futures = ids.map((id) async {
        final value = await _db.getClientAccountBalance(id);
        return MapEntry(id, value);
      }).toList();
      final entries = await Future.wait(futures);
      for (final e in entries) {
        balances[e.key] = e.value;
      }
    }
    if (!mounted) return;
    setState(() {
      _balancesByClientId = balances;
    });
  }

  void _closeAndPop([Client? result]) {
    FocusScope.of(context).unfocus();
    Future.delayed(const Duration(milliseconds: 350), () {
      if (!context.mounted) return;
      Navigator.of(context).pop(result);
    });
  }

  Future<void> _showAddClientDialog() async {
    final nameController = TextEditingController();
    final phoneController = TextEditingController();
    final addressController = TextEditingController();

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('New client'),
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
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Client name is required')),
                  );
                  return;
                }
                final newClient = Client(
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
                      name: name,
                      phone: phoneController.text.trim(),
                      address: addressController.text.trim(),
                    );
                    if (!remote.$1) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(remote.$2)),
                      );
                      return;
                    }
                  }
                  final newId = await _db.upsertClient(newClient);
                  if (!mounted) return;
                  final saved = newClient.copyWith(id: newId);
                  setState(() {
                    _clients.insert(0, saved);
                    _balancesByClientId = {
                      ..._balancesByClientId,
                      if (newId > 0) newId: 0,
                    };
                  });
                  if (!dialogContext.mounted) return;
                  Navigator.of(dialogContext).pop();
                  _closeAndPop(saved);
                } catch (e) {
                  if (!mounted) return;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredClients;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _closeAndPop();
      },
      child: Scaffold(
        backgroundColor: _kSaleFlowScaffoldBg,
        appBar: AppBar(
          backgroundColor: _kSaleFlowAppBarBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const SectionPageTitle(pageTitle: 'Select client'),
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search clients',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Expanded(
                child: _clients.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'No clients yet. Tap + below to add a client.',
                            style: theme.textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              'No clients match your search.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final client = filtered[index];
                              final selected =
                                  widget.selectedClient?.id == client.id;
                              return ListTile(
                                title: Text(
                                  _clientLabel(client),
                                  style: TextStyle(
                                    fontWeight:
                                        selected ? FontWeight.w600 : null,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Balance: USh ${formatMoney(_balancesByClientId[client.id] ?? 0)}',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: const Color(0xFF166534),
                                      ),
                                    ),
                                    if (client.address != null &&
                                        client.address!.trim().isNotEmpty)
                                      Text(
                                        client.address!,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.bodySmall,
                                      ),
                                  ],
                                ),
                                selected: selected,
                                onTap: () => _closeAndPop(client),
                              );
                            },
                            separatorBuilder: (context, index) => Divider(
                              height: 1,
                              thickness: 1,
                              color: theme.dividerColor.withOpacity(0.45),
                            ),
                          ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          mini: true,
          onPressed: _showAddClientDialog,
          tooltip: 'Add new client',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
