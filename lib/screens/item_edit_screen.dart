import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../models/item.dart';
import '../models/unit.dart';
import '../services/auth_service.dart';
import '../services/item_image_upload_service.dart';
import '../services/local_db_service.dart';
import '../utils/meter_fixed_stock_items.dart';
import '../widgets/section_page_title.dart';
import 'barcode_scan_screen.dart';

class ItemEditScreen extends StatefulWidget {
  final Item? item;

  const ItemEditScreen({super.key, this.item});

  @override
  State<ItemEditScreen> createState() => _ItemEditScreenState();
}

class _ItemEditScreenState extends State<ItemEditScreen> {
  final _db = LocalDbService.instance;
  final _authService = AuthService();
  final _formKey = GlobalKey<FormState>();
  static const String _saleCategoriesMetaKey = 'item_sale_categories';
  static const String _businessCategoriesMetaKey = 'item_business_categories';
  static const List<String> _defaultSaleCategories = [
    'Retail',
    'Wholesale',
    'Service',
  ];
  static const List<String> _defaultBusinessCategories = [
    'Supermarket',
    'Hardware',
  ];

  late final TextEditingController _nameController;
  late final TextEditingController _barcodeController;
  late final TextEditingController _skuController;
  late final TextEditingController _shelfNumberController;
  late final TextEditingController _costController;
  late final TextEditingController _priceController;
  late final TextEditingController _stockController;
  late final TextEditingController _reorderController;
  late final TextEditingController _restockToController;

  bool _saving = false;
  bool _uploadingImage = false;
  List<Unit> _units = [];
  bool _unitsLoading = true;
  bool _categoryListsLoading = true;
  Unit? _selectedUnit;
  List<String> _saleCategories = List<String>.from(_defaultSaleCategories);
  List<String> _businessCategories = List<String>.from(_defaultBusinessCategories);
  String? _selectedSaleCategory;
  String? _selectedBusinessCategory;
  final List<String?> _imageUrls = <String?>[null, null, null];
  List<String> _recentImageUrls = const [];

  String _initialNumberText(double? value) {
    final v = value ?? 0;
    if (v == 0) return '';
    return v.toString();
  }

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _nameController = TextEditingController(text: item?.name ?? '');
    _barcodeController = TextEditingController(text: item?.barcode ?? '');
    _skuController = TextEditingController(text: item?.sku ?? '');
    _shelfNumberController =
        TextEditingController(text: item?.shelfNumber ?? '');
    _costController =
        TextEditingController(text: _initialNumberText(item?.costPrice));
    _priceController =
        TextEditingController(text: _initialNumberText(item?.sellingPrice));
    _stockController =
        TextEditingController(text: _initialNumberText(item?.stockQty));
    _reorderController =
        TextEditingController(text: _initialNumberText(item?.reorderLevel));
    _restockToController =
        TextEditingController(text: _initialNumberText(item?.restockTo));
    _imageUrls[0] = item?.imageUrl;
    _imageUrls[1] = item?.imageUrl2;
    _imageUrls[2] = item?.imageUrl3;
    _nameController.addListener(_onNameChanged);
    _loadCategoryOptions(item?.category);
    _loadUnits();
    _loadRecentImageUrls();
    _loadAcceptedBarcodes();
  }

  void _onNameChanged() {
    _loadRecentImageUrls();
  }

  List<String> _enteredBarcodes() {
    return _parseAcceptedBarcodes(_barcodeController.text);
  }

  void _setEnteredBarcodes(Iterable<String> values) {
    _barcodeController.text = _db.normalizeBarcodeList(values).join(', ');
  }

  Future<void> _tryAddBarcodeCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.isEmpty || !mounted) return;
    final normalized = _norm(trimmed);
    final current = _enteredBarcodes();
    final alreadyAdded = current.any((e) => _norm(e) == normalized);
    if (alreadyAdded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Code "$trimmed" is already added to this item.')),
      );
      return;
    }
    if (_isEditingItem && _isPrimaryCodeOfThisItem(trimmed)) {
      return;
    }

    final existingItems = await _loadItemsForBarcodeChecks();
    final conflictInLoaded = existingItems.firstWhere(
      (item) =>
          !_isSameItemRecord(item, widget.item) &&
          (_norm(item.sku) == normalized || _norm(item.barcode) == normalized),
      orElse: () => Item(name: ''),
    );
    if (conflictInLoaded.name.trim().isNotEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Code "$trimmed" is already used by item "${conflictInLoaded.name}".',
          ),
        ),
      );
      return;
    }

    if (!await _authService.isRemoteUser()) {
      final localConflict = await _db.findItemByAnyCode(
        trimmed,
        excludingItemId: widget.item?.id,
      );
      if (localConflict != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Code "$trimmed" is already used by item "${localConflict.name}".',
            ),
          ),
        );
        return;
      }
    }

    final merged = _db.normalizeBarcodeList([...current, trimmed]);
    if (!mounted) return;
    setState(() => _setEnteredBarcodes(merged));
  }

  Future<void> _scanAndAppendBarcode() async {
    if (kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Barcode scanning works on Android and iOS devices.'),
        ),
      );
      return;
    }
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (!mounted || code == null) return;
    final scanned = code.trim();
    if (scanned.isEmpty) return;
    await _tryAddBarcodeCode(scanned);
  }

  Future<void> _promptAndAddBarcode() async {
    final controller = TextEditingController();
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add barcode'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Barcode',
            hintText: 'Type barcode and save',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final code = (raw ?? '').trim();
    if (code.isEmpty || !mounted) return;
    await _tryAddBarcodeCode(code);
  }

  List<String> _parseAcceptedBarcodes(String raw) {
    final segments = raw
        .split(RegExp(r'[\n,;|]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
    return _db.normalizeBarcodeList(segments);
  }

  Future<void> _loadAcceptedBarcodes() async {
    final itemId = widget.item?.id;
    if (itemId == null) return;
    final aliases = await _db.getItemBarcodes(itemId);
    if (!mounted) return;
    if (aliases.isEmpty) return;
    final allCodes = _db
        .normalizeBarcodeList([
          (_barcodeController.text).trim(),
          ...aliases,
        ])
        .where((c) => !_isPrimaryCodeOfThisItem(c))
        .toList();
    setState(() {
      _barcodeController.text = allCodes.join(', ');
    });
  }

  Future<List<Item>> _loadItemsForBarcodeChecks() async {
    if (await _authService.isRemoteUser()) {
      return _authService.fetchRemoteItems();
    }
    return _db.getItems();
  }

  Future<void> _applyItemAliasBarcodes(
    int itemId,
    String? primarySku,
    List<String> rawAcceptedBarcodes,
  ) async {
    if (itemId <= 0) return;
    final p = (primarySku ?? '').trim();
    final filtered = _db
        .normalizeBarcodeList(rawAcceptedBarcodes)
        .where((code) => p.isEmpty || _norm(code) != _norm(p))
        .toList();
    await _db.replaceItemBarcodes(itemId: itemId, barcodes: filtered);
  }

  Future<void> _loadUnits() async {
    final list = await _authService.isRemoteUser()
        ? await _authService.fetchRemoteUnits()
        : await _db.getUnits();
    if (mounted) {
      Unit? initial;
      final item = widget.item;
      final itemUnit = (item?.unit ?? '').trim().toLowerCase();
      final itemUnitShort = (item?.unitShort ?? '').trim().toLowerCase();
      if (itemUnit.isNotEmpty || itemUnitShort.isNotEmpty) {
        // Prefer exact unit + short match, then graceful fallbacks so edit always prefills unit.
        initial = list
            .where(
              (u) =>
                  u.unitName.trim().toLowerCase() == itemUnit &&
                  u.unitShortName.trim().toLowerCase() == itemUnitShort,
            )
            .firstOrNull;
        initial ??= list
            .where((u) => u.unitName.trim().toLowerCase() == itemUnit)
            .firstOrNull;
        initial ??= list
            .where((u) => u.unitShortName.trim().toLowerCase() == itemUnitShort)
            .firstOrNull;
      }
      setState(() {
        _units = list;
        _unitsLoading = false;
        if (initial != null) _selectedUnit = initial;
      });
    }
  }

  Future<void> _refreshUnitsForPicker() async {
    final list = await _authService.isRemoteUser()
        ? await _authService.fetchRemoteUnits()
        : await _db.getUnits();
    if (!mounted) return;

    final currentSelected = _selectedUnit;
    Unit? refreshedSelected;
    if (currentSelected != null) {
      refreshedSelected = list
          .where((u) => u.id != null && u.id == currentSelected.id)
          .firstOrNull;
      refreshedSelected ??= list
          .where(
            (u) =>
                _norm(u.displayLabel) == _norm(currentSelected.displayLabel),
          )
          .firstOrNull;
    }

    setState(() {
      _units = list;
      _unitsLoading = false;
      if (refreshedSelected != null) {
        _selectedUnit = refreshedSelected;
      }
    });
  }

  List<String> _decodeCategoryList(String? raw) {
    final decoded = (raw ?? '')
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    decoded.sort();
    return decoded;
  }

  Future<void> _saveCategoryLists() async {
    if (await _authService.isRemoteUser()) return;
    final sale = _saleCategories
      ..removeWhere((e) => e.trim().isEmpty)
      ..sort();
    final business = _businessCategories
      ..removeWhere((e) => e.trim().isEmpty)
      ..sort();
    await _db.setAppMeta(_saleCategoriesMetaKey, sale.join('|'));
    await _db.setAppMeta(_businessCategoriesMetaKey, business.join('|'));
  }

  Future<void> _loadCategoryOptions(String? itemCategory) async {
    final isRemote = await _authService.isRemoteUser();
    List<String> sale;
    List<String> business;
    if (isRemote) {
      sale = await _authService.fetchRemoteItemCategories(type: 'sale');
      business = await _authService.fetchRemoteItemCategories(type: 'business');
    } else {
      final saleRaw = await _db.getAppMeta(_saleCategoriesMetaKey);
      final businessRaw = await _db.getAppMeta(_businessCategoriesMetaKey);
      sale = _decodeCategoryList(saleRaw);
      business = _decodeCategoryList(businessRaw);
    }

    if (sale.isEmpty) {
      sale = List<String>.from(_defaultSaleCategories);
    } else {
      for (final value in _defaultSaleCategories) {
        if (!sale.contains(value)) sale.add(value);
      }
    }
    if (business.isEmpty) {
      business = List<String>.from(_defaultBusinessCategories);
    } else {
      for (final value in _defaultBusinessCategories) {
        if (!business.contains(value)) business.add(value);
      }
    }

    _saleCategories = sale;
    _businessCategories = business;
    _setCategorySelections(itemCategory);

    if (!mounted) return;
    setState(() => _categoryListsLoading = false);
    if (!isRemote) {
      await _saveCategoryLists();
    }
  }

  Future<void> _refreshCategoryOptionsForPicker() async {
    final isRemote = await _authService.isRemoteUser();
    List<String> sale;
    List<String> business;
    if (isRemote) {
      sale = await _authService.fetchRemoteItemCategories(type: 'sale');
      business = await _authService.fetchRemoteItemCategories(type: 'business');
    } else {
      final saleRaw = await _db.getAppMeta(_saleCategoriesMetaKey);
      final businessRaw = await _db.getAppMeta(_businessCategoriesMetaKey);
      sale = _decodeCategoryList(saleRaw);
      business = _decodeCategoryList(businessRaw);
    }

    for (final value in _defaultSaleCategories) {
      if (!sale.contains(value)) sale.add(value);
    }
    for (final value in _defaultBusinessCategories) {
      if (!business.contains(value)) business.add(value);
    }
    sale.sort();
    business.sort();

    if (!mounted) return;
    setState(() {
      _saleCategories = sale;
      _businessCategories = business;
      _categoryListsLoading = false;
    });
    if (!isRemote) {
      await _saveCategoryLists();
    }
  }

  void _setCategorySelections(String? categoryValue) {
    final raw = (categoryValue ?? '').trim();
    if (raw.isEmpty) return;
    final parts = raw.split('|').map((p) => p.trim()).toList();
    for (final part in parts) {
      if (part.startsWith('Sale:')) {
        final value = part.replaceFirst('Sale:', '').trim();
        if (_saleCategories.contains(value)) _selectedSaleCategory = value;
      }
      if (part.startsWith('Business:')) {
        final value = part.replaceFirst('Business:', '').trim();
        if (_businessCategories.contains(value)) _selectedBusinessCategory = value;
      }
    }
    if (_selectedBusinessCategory == null && _businessCategories.contains(raw)) {
      _selectedBusinessCategory = raw;
    }
    if (_selectedSaleCategory == null && _saleCategories.contains(raw)) {
      _selectedSaleCategory = raw;
    }
  }

  String? _composedCategoryValue() {
    final sale = _selectedSaleCategory?.trim();
    final business = _selectedBusinessCategory?.trim();
    if ((sale == null || sale.isEmpty) && (business == null || business.isEmpty)) {
      return null;
    }
    if (sale != null && sale.isNotEmpty && business != null && business.isNotEmpty) {
      return 'Business: $business | Sale: $sale';
    }
    if (business != null && business.isNotEmpty) return 'Business: $business';
    return 'Sale: $sale';
  }

  ({String? sale, String? business}) _extractCategories(String? categoryValue) {
    final raw = (categoryValue ?? '').trim();
    String? sale;
    String? business;
    if (raw.isNotEmpty) {
      final parts = raw.split('|').map((p) => p.trim());
      for (final part in parts) {
        if (part.startsWith('Sale:')) {
          sale = part.replaceFirst('Sale:', '').trim();
        } else if (part.startsWith('Business:')) {
          business = part.replaceFirst('Business:', '').trim();
        }
      }
      if (sale == null && _saleCategories.contains(raw)) sale = raw;
      if (business == null && _businessCategories.contains(raw)) business = raw;
    }
    return (sale: sale, business: business);
  }

  String _norm(String? value) => (value ?? '').trim().toLowerCase();

  bool get _isEditingItem => widget.item?.id != null;

  String? get _existingPrimaryCode {
    final base = widget.item;
    if (base == null) return null;
    final sku = (base.sku ?? '').trim();
    if (sku.isNotEmpty) return sku;
    final barcode = (base.barcode ?? '').trim();
    return barcode.isEmpty ? null : barcode;
  }

  bool _isSameItemRecord(Item other, Item? base) {
    if (base?.id == null || other.id == null) return false;
    return other.id == base!.id;
  }

  bool _isPrimaryCodeOfThisItem(String code) {
    final primary = _existingPrimaryCode;
    if (primary == null || primary.isEmpty) return false;
    return _norm(code) == _norm(primary);
  }

  List<String> _aliasBarcodesExcludingPrimary(String raw) {
    return _parseAcceptedBarcodes(raw)
        .where((c) => !_isPrimaryCodeOfThisItem(c))
        .toList();
  }

  bool get _isServiceSaleCategory => _norm(_selectedSaleCategory) == 'service';

  Future<void> _showAddUnitDialog() async {
    final unitNameController = TextEditingController();
    final shortNameController = TextEditingController();
    final created = await showDialog<Unit>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add unit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: unitNameController,
              decoration: const InputDecoration(labelText: 'Unit name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: shortNameController,
              decoration: const InputDecoration(labelText: 'Short name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final unitName = unitNameController.text.trim();
              final shortName = shortNameController.text.trim();
              if (unitName.isEmpty || shortName.isEmpty) return;
              Navigator.of(context).pop(
                Unit(unitName: unitName, unitShortName: shortName),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (created == null) return;
    try {
      if (await _authService.isRemoteUser()) {
        final remote = await _authService.saveRemoteUnit(
          unitName: created.unitName,
          unitShortName: created.unitShortName,
        );
        if (!remote.$1) {
          throw Exception(remote.$2);
        }
      } else {
        await _db.insertUnit(created);
      }
      await _loadUnits();
      if (!mounted) return;
      final selected = _units
          .where(
            (u) =>
                u.unitName.toLowerCase() == created.unitName.toLowerCase() &&
                u.unitShortName.toLowerCase() ==
                    created.unitShortName.toLowerCase(),
          )
          .firstOrNull;
      if (selected != null) {
        setState(() => _selectedUnit = selected);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unit added')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not add unit')),
      );
    }
  }

  Future<void> _showAddCategoryDialog({required bool isSaleCategory}) async {
    final controller = TextEditingController();
    final label = isSaleCategory ? 'sale category' : 'business category';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add $label'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: isSaleCategory ? 'Sale category name' : 'Business category name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty) return;
    final isRemote = await _authService.isRemoteUser();
    if (isRemote) {
      final remote = await _authService.saveRemoteItemCategory(
        type: isSaleCategory ? 'sale' : 'business',
        name: trimmed,
      );
      if (!remote.$1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(remote.$2)),
        );
        return;
      }
      await _loadCategoryOptions(widget.item?.category);
      if (!mounted) return;
      setState(() {
        if (isSaleCategory) {
          _selectedSaleCategory = trimmed;
        } else {
          _selectedBusinessCategory = trimmed;
        }
      });
      return;
    }
    if (mounted) {
      setState(() {
        final target = isSaleCategory ? _saleCategories : _businessCategories;
        if (!target.contains(trimmed)) target.add(trimmed);
        target.sort();
        if (isSaleCategory) {
          _selectedSaleCategory = trimmed;
        } else {
          _selectedBusinessCategory = trimmed;
        }
      });
    }
    await _saveCategoryLists();
  }

  Future<void> _showBusinessCategoryPicker() async {
    await _refreshCategoryOptionsForPicker();
    if (!mounted) return;
    await _showSearchablePicker<String>(
      title: 'Business category',
      options: _businessCategories,
      selected: _selectedBusinessCategory,
      labelOf: (v) => v,
      onAddNew: () => _showAddCategoryDialog(isSaleCategory: false),
      onEditOption: (value) =>
          _showEditCategoryDialog(isSaleCategory: false, initialValue: value),
      onDeleteOption: (value) =>
          _deleteSelectedCategory(isSaleCategory: false, targetValue: value),
      onSelected: (value) {
        if (!mounted) return;
        setState(() => _selectedBusinessCategory = value);
      },
    );
  }

  Future<void> _showSaleCategoryPicker() async {
    await _refreshCategoryOptionsForPicker();
    if (!mounted) return;
    await _showSearchablePicker<String>(
      title: 'Sale category',
      options: _saleCategories,
      selected: _selectedSaleCategory,
      labelOf: (v) => v,
      onAddNew: () => _showAddCategoryDialog(isSaleCategory: true),
      onEditOption: (value) =>
          _showEditCategoryDialog(isSaleCategory: true, initialValue: value),
      onDeleteOption: (value) =>
          _deleteSelectedCategory(isSaleCategory: true, targetValue: value),
      onSelected: (value) {
        if (!mounted) return;
        setState(() => _selectedSaleCategory = value);
      },
    );
  }

  Future<void> _showUnitPicker() async {
    await _refreshUnitsForPicker();
    if (!mounted) return;
    await _showSearchablePicker<Unit>(
      title: 'Unit',
      options: _units,
      selected: _selectedUnit,
      labelOf: (v) => v.displayLabel,
      onAddNew: _showAddUnitDialog,
      onEditOption: _showEditUnitDialog,
      onDeleteOption: _deleteSelectedUnit,
      onSelected: (value) {
        if (!mounted) return;
        setState(() => _selectedUnit = value);
      },
    );
  }

  Future<void> _showSearchablePicker<T>({
    required String title,
    required List<T> options,
    required T? selected,
    required String Function(T value) labelOf,
    required Future<void> Function() onAddNew,
    Future<void> Function(T value)? onEditOption,
    Future<void> Function(T value)? onDeleteOption,
    required void Function(T? value) onSelected,
  }) async {
    String query = '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = options.where((entry) {
              final label = labelOf(entry).toLowerCase();
              return label.contains(query.toLowerCase());
            }).toList();
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  right: 12,
                  top: 12,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: TextField(
                              autofocus: true,
                              decoration: const InputDecoration(
                                hintText: 'Search',
                                prefixIcon: Icon(Icons.search, size: 18),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              onChanged: (value) {
                                setSheetState(() => query = value.trim());
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 40,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await onAddNew();
                            },
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Add new'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      dense: true,
                      leading: Radio<bool>(
                        value: true,
                        groupValue: selected == null,
                        onChanged: (_) {
                          onSelected(null);
                          Navigator.of(context).pop();
                        },
                      ),
                      title: const Text('None'),
                      onTap: () {
                        onSelected(null);
                        Navigator.of(context).pop();
                      },
                    ),
                    const Divider(height: 1),
                    Flexible(
                      child: filtered.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 18),
                              child: Text('No matching results'),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final option = filtered[index];
                                final isSelected = selected == option;
                                return ListTile(
                                  dense: true,
                                  leading: Radio<bool>(
                                    value: true,
                                    groupValue: isSelected,
                                    onChanged: (_) {
                                      onSelected(option);
                                      Navigator.of(context).pop();
                                    },
                                  ),
                                  title: Text(labelOf(option)),
                                  trailing:
                                      (onEditOption == null && onDeleteOption == null)
                                      ? null
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (onEditOption != null)
                                              IconButton(
                                                tooltip: 'Edit',
                                                visualDensity: VisualDensity.compact,
                                                icon: const Icon(
                                                  Icons.edit_outlined,
                                                  size: 18,
                                                ),
                                                onPressed: () async {
                                                  Navigator.of(context).pop();
                                                  await onEditOption(option);
                                                },
                                              ),
                                            if (onDeleteOption != null)
                                              IconButton(
                                                tooltip: 'Delete',
                                                visualDensity: VisualDensity.compact,
                                                icon: const Icon(
                                                  Icons.delete_outline,
                                                  size: 18,
                                                ),
                                                onPressed: () async {
                                                  Navigator.of(context).pop();
                                                  await onDeleteOption(option);
                                                },
                                              ),
                                          ],
                                        ),
                                  onTap: () {
                                    onSelected(option);
                                    Navigator.of(context).pop();
                                  },
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showEditCategoryDialog({
    required bool isSaleCategory,
    String? initialValue,
  }) async {
    final selected =
        (initialValue ?? (isSaleCategory ? _selectedSaleCategory : _selectedBusinessCategory))
            ?.trim();
    if (selected == null || selected.trim().isEmpty) return;
    final controller = TextEditingController(text: selected);
    final label = isSaleCategory ? 'sale category' : 'business category';
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit $label'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: isSaleCategory ? 'Sale category name' : 'Business category name',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final trimmed = (value ?? '').trim();
    if (trimmed.isEmpty || trimmed == selected) return;
    final isRemote = await _authService.isRemoteUser();
    if (isRemote) {
      final remote = await _authService.saveRemoteItemCategory(
        type: isSaleCategory ? 'sale' : 'business',
        name: trimmed,
        oldName: selected,
      );
      if (!remote.$1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(remote.$2)),
        );
        return;
      }
      await _loadCategoryOptions(widget.item?.category);
      if (!mounted) return;
      setState(() {
        if (isSaleCategory) {
          _selectedSaleCategory = trimmed;
        } else {
          _selectedBusinessCategory = trimmed;
        }
      });
      return;
    }
    if (mounted) {
      setState(() {
        final target = isSaleCategory ? _saleCategories : _businessCategories;
        final idx = target.indexOf(selected);
        if (idx >= 0) {
          target[idx] = trimmed;
        } else if (!target.contains(trimmed)) {
          target.add(trimmed);
        }
        target.sort();
        if (isSaleCategory) {
          _selectedSaleCategory = trimmed;
        } else {
          _selectedBusinessCategory = trimmed;
        }
      });
    }
    await _saveCategoryLists();
  }

  Future<void> _deleteSelectedCategory({
    required bool isSaleCategory,
    String? targetValue,
  }) async {
    final selected =
        (targetValue ?? (isSaleCategory ? _selectedSaleCategory : _selectedBusinessCategory))
            ?.trim();
    if (selected == null || selected.trim().isEmpty) return;
    final label = isSaleCategory ? 'sale category' : 'business category';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $label?'),
        content: Text('Delete "$selected"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    final isRemote = await _authService.isRemoteUser();
    if (isRemote) {
      final remote = await _authService.deleteRemoteItemCategory(
        type: isSaleCategory ? 'sale' : 'business',
        name: selected,
      );
      if (!remote.$1) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(remote.$2)),
        );
        return;
      }
      await _loadCategoryOptions(widget.item?.category);
      if (!mounted) return;
      setState(() {
        if (isSaleCategory) {
          _selectedSaleCategory = null;
        } else {
          _selectedBusinessCategory = null;
        }
      });
      return;
    }
    if (mounted) {
      setState(() {
        final target = isSaleCategory ? _saleCategories : _businessCategories;
        target.remove(selected);
        if (isSaleCategory) {
          _selectedSaleCategory = null;
        } else {
          _selectedBusinessCategory = null;
        }
      });
    }
    await _saveCategoryLists();
  }

  Future<void> _showEditUnitDialog([Unit? selectedUnit]) async {
    final selected = selectedUnit ?? _selectedUnit;
    if (selected == null) return;
    final unitNameController = TextEditingController(text: selected.unitName);
    final shortNameController = TextEditingController(text: selected.unitShortName);
    final edited = await showDialog<Unit>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit unit'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: unitNameController,
              decoration: const InputDecoration(labelText: 'Unit name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: shortNameController,
              decoration: const InputDecoration(labelText: 'Short name'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final unitName = unitNameController.text.trim();
              final shortName = shortNameController.text.trim();
              if (unitName.isEmpty || shortName.isEmpty) return;
              Navigator.of(context).pop(
                Unit(
                  id: selected.id,
                  unitName: unitName,
                  unitShortName: shortName,
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (edited == null) return;
    try {
      if (await _authService.isRemoteUser()) {
        final remote = await _authService.saveRemoteUnit(
          id: edited.id,
          unitName: edited.unitName,
          unitShortName: edited.unitShortName,
        );
        if (!remote.$1) throw Exception(remote.$2);
      } else {
        await _db.updateUnit(edited);
      }
      await _loadUnits();
      if (!mounted) return;
      final selectedUnit = _units.where((u) => u.id == edited.id).firstOrNull;
      if (selectedUnit != null) {
        setState(() => _selectedUnit = selectedUnit);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unit updated')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not update unit')),
      );
    }
  }

  Future<void> _deleteSelectedUnit([Unit? selectedUnit]) async {
    final selected = selectedUnit ?? _selectedUnit;
    final unitId = selected?.id;
    if (selected == null || unitId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete unit?'),
        content: Text('Delete "${selected.displayLabel}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      if (await _authService.isRemoteUser()) {
        final remote = await _authService.deleteRemoteUnit(unitId);
        if (!remote.$1) throw Exception(remote.$2);
      } else {
        await _db.deleteUnit(unitId);
      }
      await _loadUnits();
      if (!mounted) return;
      setState(() => _selectedUnit = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unit deleted')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete unit')),
      );
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_onNameChanged);
    _nameController.dispose();
    _barcodeController.dispose();
    _skuController.dispose();
    _shelfNumberController.dispose();
    _costController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _reorderController.dispose();
    _restockToController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentImageUrls() async {
    final nameKey = _norm(_nameController.text);
    if (nameKey.isEmpty) {
      if (_recentImageUrls.isNotEmpty && mounted) {
        setState(() => _recentImageUrls = const []);
      }
      return;
    }
    final items = await _db.getItems();
    if (!mounted) return;
    final urls = <String>[];
    for (final item in items) {
      if (_norm(item.name) != nameKey) continue;
      final candidates = [
        (item.imageUrl ?? '').trim(),
        (item.imageUrl2 ?? '').trim(),
        (item.imageUrl3 ?? '').trim(),
      ];
      for (final url in candidates) {
        if (url.isEmpty || urls.contains(url)) continue;
        urls.add(url);
        if (urls.length >= 8) break;
      }
      if (urls.length >= 8) break;
    }
    setState(() => _recentImageUrls = urls);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
    });

    final cost =
        double.tryParse(_costController.text.replaceAll(',', '.')) ?? 0;
    final price =
        double.tryParse(_priceController.text.replaceAll(',', '.')) ?? 0;
    final base = widget.item;
    final isService = _isServiceSaleCategory;
    final isNewItem = base == null;
    final stock = isService
        ? (isNewItem ? 1.0 : 0.0)
        : (double.tryParse(_stockController.text.replaceAll(',', '.')) ?? 0);
    final reorder = isService
        ? 0.0
        : (double.tryParse(_reorderController.text.replaceAll(',', '.')) ?? 0);
    final restockTo = isService
        ? 0.0
        : (double.tryParse(_restockToController.text.replaceAll(',', '.')) ??
            0);

    final itemName = _nameController.text.trim();
    var resolvedStock = stock;
    if (isMeterSoldFixedStockItemName(itemName)) {
      resolvedStock = isNewItem
          ? kSpecialItemUnavailableStock
          : (base!.stockQty > 0
              ? kSpecialItemAvailableStock
              : kSpecialItemUnavailableStock);
    }

    final categoryValue = _composedCategoryValue();
    final enteredBarcodes =
        _aliasBarcodesExcludingPrimary(_barcodeController.text);
    final enteredSku =
        _isEditingItem ? '' : _skuController.text.trim();
    final shelfNumber = _shelfNumberController.text.trim();

    List<Item> existingItems = const [];
    existingItems = await _loadItemsForBarcodeChecks();
    final allCodesToValidate = _isEditingItem
        ? enteredBarcodes
        : [
            if (enteredSku.isNotEmpty) enteredSku,
            ...enteredBarcodes,
          ];
    String? conflictingCode;
    for (final code in allCodesToValidate) {
      final normalized = _norm(code);
      if (normalized.isEmpty) continue;
      if (_isEditingItem && _isPrimaryCodeOfThisItem(code)) continue;
      final usedByOtherItem = existingItems.any(
        (e) =>
            !_isSameItemRecord(e, base) &&
            (_norm(e.sku) == normalized || _norm(e.barcode) == normalized),
      );
      if (usedByOtherItem) {
        conflictingCode = code.trim();
        break;
      }
    }
    conflictingCode ??= await _db.findConflictingBarcode(
      allCodesToValidate,
      excludingItemId: base?.id,
    );
    if (conflictingCode != null) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Code "$conflictingCode" is already used by another item.',
          ),
        ),
      );
      return;
    }

    final String? resolvedSku = _isEditingItem
        ? _existingPrimaryCode
        : (enteredSku.isNotEmpty
            ? enteredSku
            : null);

    String? primaryBarcode;
    if (resolvedSku != null && resolvedSku.isNotEmpty) {
      primaryBarcode = resolvedSku;
    } else if (base != null) {
      final b = (base.barcode ?? '').trim();
      final s = (base.sku ?? '').trim();
      primaryBarcode = b.isNotEmpty ? b : (s.isNotEmpty ? s : null);
    } else {
      primaryBarcode = null;
    }

    // For new items: block only exact duplicates of name + unit + sale + business.
    if (base == null) {
      final selectedSale = _norm(_selectedSaleCategory);
      final selectedBusiness = _norm(_selectedBusinessCategory);
      final selectedUnit = _norm(_selectedUnit?.unitName);
      final selectedName = _norm(_nameController.text);

      final hasExactDuplicate = existingItems.any((e) {
        final parsed = _extractCategories(e.category);
        return _norm(e.name) == selectedName &&
            _norm(e.unit) == selectedUnit &&
            _norm(parsed.sale) == selectedSale &&
            _norm(parsed.business) == selectedBusiness;
      });

      if (hasExactDuplicate) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This item already exists with same name, unit, sale category and business category.',
            ),
          ),
        );
        return;
      }
    }

    final newItem = Item(
      id: base?.id,
      storeId: base?.storeId,
      name: _nameController.text.trim(),
      barcode: primaryBarcode,
      sku: resolvedSku,
      category: categoryValue,
      unit: _selectedUnit?.unitName,
      unitShort: _selectedUnit?.unitShortName,
      shelfNumber: shelfNumber.isEmpty ? null : shelfNumber,
      imageUrl: _imageUrls[0],
      imageUrl2: _imageUrls[1],
      imageUrl3: _imageUrls[2],
      packagingId: null,
      variantGroup: null,
      unitsPerPackage: null,
      costPrice: cost,
      sellingPrice: price,
      stockQty: resolvedStock,
      reorderLevel: reorder,
      restockTo: restockTo,
      createdAt: base?.createdAt,
      specialRollMetersTotal: base?.specialRollMetersTotal ?? 0,
      specialRollMetersSold: base?.specialRollMetersSold ?? 0,
    );

    if (await _authService.isRemoteUser()) {
      final payload = <String, Object?>{
        if (newItem.id != null) 'id': newItem.id,
        if (newItem.storeId != null) 'storeId': newItem.storeId,
        'name': newItem.name,
        'category': newItem.category ?? '',
        'unit': newItem.unit ?? '',
        'unitShort': newItem.unitShort ?? '',
        'shelfNumber': newItem.shelfNumber ?? '',
        'imageUrl': newItem.imageUrl ?? '',
        'imageUrl2': newItem.imageUrl2 ?? '',
        'imageUrl3': newItem.imageUrl3 ?? '',
        if (newItem.packagingId != null) 'packagingId': newItem.packagingId,
        'variantGroup': newItem.variantGroup ?? '',
        if (newItem.unitsPerPackage != null)
          'unitsPerPackage': newItem.unitsPerPackage,
        'costPrice': newItem.costPrice,
        'sellingPrice': newItem.sellingPrice,
        'stockQty': newItem.stockQty,
        'reorderLevel': newItem.reorderLevel,
        'restockTo': newItem.restockTo,
      };
      if ((newItem.sku ?? '').trim().isNotEmpty) {
        payload['sku'] = newItem.sku!.trim();
        payload['barcode'] = (newItem.barcode ?? newItem.sku)!.trim();
      }
      final remote = await _authService.saveRemoteItem(payload);
      if (!remote.$1) {
        if (!mounted) return;
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(remote.$2)),
        );
        return;
      }
      final mergedId = remote.$3 ?? newItem.id ?? base?.id;
      Item? merged;
      if (mergedId != null && mergedId > 0) {
        final list = await _authService.fetchRemoteItems();
        for (final it in list) {
          if (it.id == mergedId) {
            merged = it;
            break;
          }
        }
      }
      if (merged != null) {
        await _db.upsertItem(merged);
        await _applyItemAliasBarcodes(merged.id!, merged.sku, enteredBarcodes);
      }
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.of(context).pop(true);
      return;
    }

    final persistedItemId = base?.id ?? (await _db.upsertItem(newItem));
    if (base != null) {
      await _db.upsertItem(newItem);
    }
    final idForAliases = base?.id ?? persistedItemId;
    final savedPrimary = idForAliases > 0
        ? ((await _db.getItemById(idForAliases))?.sku ?? resolvedSku)
        : resolvedSku;
    await _applyItemAliasBarcodes(idForAliases, savedPrimary, enteredBarcodes);

    if (!mounted) return;
    setState(() {
      _saving = false;
    });
    Navigator.of(context).pop(true);
  }

  bool _hasImageAt(int index) {
    final value = _imageUrls[index];
    return value != null && value.trim().isNotEmpty;
  }

  int _nextImageSlot() {
    for (var i = 0; i < _imageUrls.length; i++) {
      if (!_hasImageAt(i)) return i;
    }
    return 0;
  }

  Future<void> _uploadImage([int? targetIndex]) async {
    if (_uploadingImage || _saving) return;
    final slot = targetIndex ?? _nextImageSlot();
    setState(() => _uploadingImage = true);
    try {
      final url = await ItemImageUploadService.instance.pickCompressAndUpload();
      if (!mounted) return;
      setState(() => _imageUrls[slot] = url);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Image ${slot + 1} uploaded.')),
      );
    } catch (e) {
      if (!mounted) return;
      final message = '$e'.contains('_UserCancelledException')
          ? 'Image selection cancelled.'
          : 'Image upload failed: $e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) {
        setState(() => _uploadingImage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.item != null;

    return Scaffold(
      appBar: AppBar(
        title: SectionPageTitle(
          pageTitle: isEditing ? 'Edit item' : 'New item',
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Item images (up to 3)',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: List.generate(_imageUrls.length, (index) {
                  final imageUrl = _imageUrls[index];
                  final hasImage = _hasImageAt(index);
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: index == _imageUrls.length - 1 ? 0 : 8,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: double.infinity,
                            height: 88,
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            child: hasImage
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.network(
                                      imageUrl!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.broken_image_outlined,
                                        size: 26,
                                      ),
                                    ),
                                  )
                                : const Icon(Icons.image_outlined, size: 26),
                          ),
                          const SizedBox(height: 6),
                          OutlinedButton(
                            onPressed: _uploadingImage
                                ? null
                                : () => _uploadImage(index),
                            child: Text(
                              _uploadingImage ? 'Uploading...' : 'Upload',
                            ),
                          ),
                          if (hasImage)
                            TextButton(
                              onPressed: _uploadingImage
                                  ? null
                                  : () => setState(() => _imageUrls[index] = null),
                              child: const Text('Remove'),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
              if (_recentImageUrls.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Recently used images for this item',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 64,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _recentImageUrls.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final url = _recentImageUrls[index];
                      final selected = _imageUrls.contains(url);
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: _saving || _uploadingImage
                            ? null
                            : () => setState(() => _imageUrls[_nextImageSlot()] = url),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected
                                  ? const Color(0xFF2563EB)
                                  : Colors.grey.shade300,
                              width: selected ? 2 : 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _barcodeController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Accepted barcodes (optional)',
                        helperText: _isEditingItem
                            ? 'Scan or add extra barcodes for this item.'
                            : 'Scan repeatedly to add many codes. Primary ITM code is assigned on first save.',
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Scan barcode with camera',
                    onPressed: _saving ? null : _scanAndAppendBarcode,
                    icon: const Icon(Icons.qr_code_scanner),
                  ),
                  IconButton(
                    tooltip: 'Type and add barcode',
                    onPressed: _saving ? null : _promptAndAddBarcode,
                    icon: const Icon(Icons.add),
                  ),
                ],
              ),
              if (_enteredBarcodes().isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _enteredBarcodes().map((code) {
                    return InputChip(
                      label: Text(code),
                      onDeleted: _saving
                          ? null
                          : () {
                              final next = _enteredBarcodes()
                                  .where((e) => _norm(e) != _norm(code))
                                  .toList();
                              setState(() => _setEnteredBarcodes(next));
                            },
                    );
                  }).toList(),
                ),
              ],
              if (!_isEditingItem) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _skuController,
                  readOnly: true,
                  keyboardType: TextInputType.text,
                  decoration: const InputDecoration(
                    labelText: 'Primary code (auto-generated)',
                    helperText:
                        'Leave blank for a new item: the next ITM code is assigned on first save only.',
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _shelfNumberController,
                keyboardType: TextInputType.text,
                decoration: const InputDecoration(
                  labelText: 'Shelf number (optional)',
                  helperText: 'Example: A-03, R2-S1',
                ),
              ),
              const SizedBox(height: 12),
              if (_categoryListsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else
                TextFormField(
                  readOnly: true,
                  onTap: _showBusinessCategoryPicker,
                  decoration: InputDecoration(
                    labelText: 'Business category (optional)',
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                  ),
                  controller: TextEditingController(
                    text: _selectedBusinessCategory ?? '',
                  ),
                ),
              const SizedBox(height: 12),
              if (_unitsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else
                TextFormField(
                  readOnly: true,
                  onTap: _showUnitPicker,
                  decoration: InputDecoration(
                    labelText: 'Unit (optional)',
                    labelStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                  ),
                  controller: TextEditingController(
                    text: _selectedUnit?.displayLabel ?? '',
                  ),
                ),
              const SizedBox(height: 16),
              if (_categoryListsLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(),
                )
              else
                TextFormField(
                  readOnly: true,
                  onTap: _showSaleCategoryPicker,
                  decoration: InputDecoration(
                    labelText: 'Sale category (optional)',
                    labelStyle: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                    suffixIcon: const Icon(Icons.arrow_drop_down),
                  ),
                  controller: TextEditingController(
                    text: _selectedSaleCategory ?? '',
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Pricing',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cost price',
                        helperText: 'Optional: set initial unit cost',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Selling price',
                        helperText: 'Optional: set initial unit selling price',
                      ),
                    ),
                  ),
                ],
              ),
              // Non-service items only (same screen for New item + Edit item).
              if (!_isServiceSaleCategory) ...[
                const SizedBox(height: 16),
                Text(
                  'Stock',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _stockController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Stock quantity',
                          helperText: 'Optional: set initial stock quantity',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _reorderController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Reorder level',
                          helperText:
                              'Alert when stock is at or below this level',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _restockToController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Restock to',
                    helperText:
                        'Target stock level after ordering new stock',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'Saving...' : 'Save item'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2563EB),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

