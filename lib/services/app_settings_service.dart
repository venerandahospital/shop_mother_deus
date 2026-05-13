import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'local_db_service.dart';

class AppSettingsService {
  AppSettingsService._();

  static final AppSettingsService instance = AppSettingsService._();

  static const _kCurrencyKey = 'settings_currency_symbol';
  static const _kShowFixedDecimalsKey = 'settings_show_fixed_decimals';
  static const _kShopNameKey = 'settings_shop_name';
  static const _metaShopNameKey = 'settings_shop_name';
  static const _metaCurrencyKey = 'settings_currency_symbol';
  static const _metaShowFixedDecimalsKey = 'settings_show_fixed_decimals';
  static const _kExpensePaidByOptionsKey = 'settings_expense_paid_by_options';
  static const _kExpenseReceivedByOptionsKey = 'settings_expense_received_by_options';

  final ValueNotifier<String> currencySymbolNotifier = ValueNotifier<String>(
    'USh',
  );
  final ValueNotifier<String> shopNameNotifier = ValueNotifier<String>('My Shop');
  final ValueNotifier<bool> showFixedDecimalsNotifier = ValueNotifier<bool>(
    false,
  );

  String get currencySymbol => currencySymbolNotifier.value;
  String get shopName => shopNameNotifier.value;
  bool get showFixedDecimals => showFixedDecimalsNotifier.value;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final dbCurrency =
        (await LocalDbService.instance.getAppMeta(_metaCurrencyKey) ?? '').trim();
    final prefsCurrency = (prefs.getString(_kCurrencyKey) ?? '').trim();
    final resolvedCurrency = dbCurrency.isNotEmpty
        ? dbCurrency
        : (prefsCurrency.isNotEmpty ? prefsCurrency : 'USh');
    await LocalDbService.instance.setAppMeta(_metaCurrencyKey, resolvedCurrency);
    await prefs.setString(_kCurrencyKey, resolvedCurrency);
    currencySymbolNotifier.value = resolvedCurrency;

    final dbShopName =
        (await LocalDbService.instance.getAppMeta(_metaShopNameKey) ?? '').trim();
    final prefsShopName = (prefs.getString(_kShopNameKey) ?? '').trim();
    final resolvedShopName = dbShopName.isNotEmpty
        ? dbShopName
        : (prefsShopName.isNotEmpty ? prefsShopName : 'My Shop');
    // Keep DB as source of truth for backup/restore while preserving prefs fallback.
    await LocalDbService.instance.setAppMeta(_metaShopNameKey, resolvedShopName);
    await prefs.setString(_kShopNameKey, resolvedShopName);
    shopNameNotifier.value = resolvedShopName;

    final dbFixedRaw =
        (await LocalDbService.instance.getAppMeta(_metaShowFixedDecimalsKey) ?? '')
            .trim()
            .toLowerCase();
    final dbFixed = dbFixedRaw == '1' || dbFixedRaw == 'true' || dbFixedRaw == 'yes';
    final prefsFixed = prefs.getBool(_kShowFixedDecimalsKey);
    final resolvedFixed = dbFixedRaw.isNotEmpty ? dbFixed : (prefsFixed ?? false);
    await LocalDbService.instance.setAppMeta(
      _metaShowFixedDecimalsKey,
      resolvedFixed ? '1' : '0',
    );
    await prefs.setBool(_kShowFixedDecimalsKey, resolvedFixed);
    showFixedDecimalsNotifier.value = resolvedFixed;
  }

  Future<void> setShopName(String name) async {
    final normalized = name.trim().isEmpty ? 'My Shop' : name.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kShopNameKey, normalized);
    await LocalDbService.instance.setAppMeta(_metaShopNameKey, normalized);
    if (shopNameNotifier.value != normalized) {
      shopNameNotifier.value = normalized;
    }
  }

  Future<void> setCurrencySymbol(String symbol) async {
    final normalized = symbol.trim().isEmpty ? 'USh' : symbol.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCurrencyKey, normalized);
    await LocalDbService.instance.setAppMeta(_metaCurrencyKey, normalized);
    if (currencySymbolNotifier.value != normalized) {
      currencySymbolNotifier.value = normalized;
    }
  }

  Future<void> setShowFixedDecimals(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kShowFixedDecimalsKey, value);
    await LocalDbService.instance.setAppMeta(
      _metaShowFixedDecimalsKey,
      value ? '1' : '0',
    );
    if (showFixedDecimalsNotifier.value != value) {
      showFixedDecimalsNotifier.value = value;
    }
  }

  Future<List<String>> getExpensePaidByOptions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kExpensePaidByOptionsKey) ?? <String>[];
  }

  Future<void> setExpensePaidByOptions(List<String> options) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kExpensePaidByOptionsKey, options);
  }

  Future<List<String>> getExpenseReceivedByOptions() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_kExpenseReceivedByOptionsKey) ?? <String>[];
  }

  Future<void> setExpenseReceivedByOptions(List<String> options) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kExpenseReceivedByOptionsKey, options);
  }

}

