import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation/app_router.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../services/subscription_service.dart';
import '../widgets/section_page_title.dart';

class SubscriptionActivationScreen extends StatefulWidget {
  const SubscriptionActivationScreen({super.key});

  @override
  State<SubscriptionActivationScreen> createState() =>
      _SubscriptionActivationScreenState();
}

class _SubscriptionActivationScreenState extends State<SubscriptionActivationScreen> {
  final _codeController = TextEditingController();
  final _db = LocalDbService.instance;
  final _authService = AuthService();
  bool _loading = true;
  bool _activating = false;
  SubscriptionStatus? _status;
  String _businessCode = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final status = await SubscriptionService.instance.getStatus();
    final business = await _db.getBusinessProfile();
    if (!mounted) return;
    setState(() {
      _status = status;
      _businessCode = (business['code'] ?? '').trim().toUpperCase();
      _loading = false;
    });
  }

  Future<void> _activate() async {
    final code = _codeController.text.trim();
    final businessCode = _businessCode.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter activation code.')),
      );
      return;
    }
    if (businessCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business code not found. Create business first.')),
      );
      return;
    }
    setState(() => _activating = true);
    final result = await SubscriptionService.instance.activateWithCode(
      code: code,
      businessCode: businessCode,
    );
    if (!mounted) return;
    setState(() => _activating = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.message)),
    );
    if (!result.ok) return;
    await _load();
    if (!mounted) return;
    final isLoggedIn = await _authService.isLoggedIn();
    if (!mounted) return;
    if (isLoggedIn) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(AppRouter.main, (_) => false);
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil(AppRouter.splash, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const SectionPageTitle(pageTitle: 'Subscription renewal'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          status != null && status.expired
                              ? 'Subscription expired'
                              : 'Subscription status',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(height: 8),
                        if (status != null) ...[
                          Text('Days used: ${status.daysUsed}'),
                          Text('Days left: ${status.daysLeft}'),
                          Text(
                            'Expires on: ${status.expiresAt.toLocal().toString().split('.').first}',
                          ),
                        ],
                        const SizedBox(height: 8),
                        const Text(
                          'Pay monthly subscription to the mobile money number shared by the owner, then enter your activation code below.',
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Support contact for activation code: 0784411848',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(labelText: 'Business code'),
                  child: Text(
                    _businessCode.isEmpty ? '-' : _businessCode,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _businessCode.isEmpty
                        ? null
                        : () async {
                            await Clipboard.setData(ClipboardData(text: _businessCode));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Business code copied.')),
                            );
                          },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy business code'),
                  ),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: _codeController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Activation code',
                    hintText: 'Paste code here',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: _activating ? null : _activate,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2563EB),
                      foregroundColor: Colors.white,
                    ),
                    icon: _activating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.verified_outlined),
                    label: Text(_activating ? 'Activating...' : 'Activate subscription'),
                  ),
                ),
              ],
            ),
    );
  }
}

