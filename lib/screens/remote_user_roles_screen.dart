import 'package:flutter/material.dart';

import '../services/local_db_service.dart';

class RemoteUserRolesScreen extends StatefulWidget {
  const RemoteUserRolesScreen({super.key});

  @override
  State<RemoteUserRolesScreen> createState() => _RemoteUserRolesScreenState();
}

class _RemoteUserRolesScreenState extends State<RemoteUserRolesScreen> {
  final _db = LocalDbService.instance;
  List<Map<String, Object?>> _pending = const [];
  List<Map<String, Object?>> _approved = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pendingRows = await _db.getPendingRemoteUsers();
    final approvedRows = await _db.getApprovedRemoteUsers();
    if (!mounted) return;
    setState(() {
      _pending = pendingRows;
      _approved = approvedRows;
      _loading = false;
    });
  }

  Future<void> _approve(int userId, String role) async {
    await _db.approveRemoteUser(userId: userId, role: role);
    await _load();
  }

  Future<void> _updateRole(int userId, String role) async {
    await _db.updateRemoteUserRole(userId: userId, role: role);
    await _load();
  }

  PopupMenuButton<String> _roleMenu({
    required void Function(String role) onSelected,
  }) {
    return PopupMenuButton<String>(
      onSelected: onSelected,
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'ADMIN', child: Text('Set as Admin')),
        PopupMenuItem(value: 'CASHIER', child: Text('Set as Cashier')),
        PopupMenuItem(value: 'CLERK', child: Text('Set as Clerk')),
        PopupMenuItem(value: 'STAFF', child: Text('Set as Staff')),
      ],
      child: const Icon(Icons.more_vert),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Child User Roles')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                children: [
                  const Text(
                    'Pending invitations',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (_pending.isEmpty)
                    const Card(
                      child: ListTile(
                        title: Text('No pending signups'),
                      ),
                    )
                  else
                    ..._pending.map((item) {
                      final userId = item['id'] as int;
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text((item['name'] ?? '').toString()),
                          subtitle: Text((item['email'] ?? '').toString()),
                          trailing: _roleMenu(
                            onSelected: (role) => _approve(userId, role),
                          ),
                        ),
                      );
                    }),
                  const SizedBox(height: 18),
                  const Text(
                    'Approved children',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (_approved.isEmpty)
                    const Card(
                      child: ListTile(
                        title: Text('No approved child users yet'),
                      ),
                    )
                  else
                    ..._approved.map((item) {
                      final userId = item['id'] as int;
                      final role = (item['role'] ?? 'STAFF').toString().toUpperCase();
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        child: ListTile(
                          title: Text((item['name'] ?? '').toString()),
                          subtitle: Text((item['email'] ?? '').toString()),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  role,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.blue,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              _roleMenu(
                                onSelected: (newRole) => _updateRole(userId, newRole),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
