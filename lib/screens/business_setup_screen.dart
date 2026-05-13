import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../navigation/app_router.dart';
import '../services/app_settings_service.dart';
import '../services/auth_service.dart';
import '../services/local_db_service.dart';
import '../widgets/section_page_title.dart';

class BusinessSetupScreen extends StatefulWidget {
  const BusinessSetupScreen({super.key});

  @override
  State<BusinessSetupScreen> createState() => _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends State<BusinessSetupScreen> {
  final _nameController = TextEditingController();
  final _db = LocalDbService.instance;
  final _appSettings = AppSettingsService.instance;
  final _auth = AuthService();
  bool _saving = false;
  String _businessCode = '';

  @override
  void initState() {
    super.initState();
    _businessCode = _generateBusinessCode();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _generateBusinessCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rnd = Random.secure();
    final suffix = List.generate(6, (_) => alphabet[rnd.nextInt(alphabet.length)]).join();
    return 'BUS-$suffix';
  }

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: _businessCode));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Business code copied.')),
    );
  }

  Future<void> _save() async {
    final businessName = _nameController.text.trim();
    if (businessName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business name is required.')),
      );
      return;
    }

    setState(() => _saving = true);
    final profile = await _auth.getCurrentProfile();
    final ownerName = (profile['name'] ?? 'Owner').trim();
    final ownerEmail = (profile['email'] ?? '').trim();
    await _db.createBusinessProfile(
      businessName: businessName,
      businessCode: _businessCode,
      ownerName: ownerName,
      ownerEmail: ownerEmail,
    );
    await _appSettings.setShopName(businessName);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRouter.subscriptionActivation,
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const SectionPageTitle(pageTitle: 'Create business'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Set up your business once to continue.',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Business name',
              hintText: 'e.g. Veneranda Hardware',
            ),
          ),
          const SizedBox(height: 12),
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Business code',
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _businessCode,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: _copyCode,
                  icon: const Icon(Icons.copy),
                  label: const Text('Copy'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Send this business code to customer care for activation code generation.',
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_saving ? 'Saving...' : 'Continue'),
            ),
          ),
        ],
      ),
    );
  }
}

