import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/asset.dart';
import '../models/client.dart';
import '../models/expense.dart';
import '../models/item.dart';
import '../models/sale.dart';
import '../models/sale_item.dart';
import '../models/service_transaction.dart';
import '../models/store.dart';
import '../models/unit.dart';
import '../models/loan.dart';
import 'app_settings_service.dart';
import 'local_db_service.dart';

class MotherApiEndpoint {
  final String interfaceName;
  final String ip;
  final String baseUrl;
  final bool isHotspotLikely;
  final String motherId;
  final String apiVersion;
  final String motherName;

  const MotherApiEndpoint({
    required this.interfaceName,
    required this.ip,
    required this.baseUrl,
    required this.isHotspotLikely,
    required this.motherId,
    required this.apiVersion,
    required this.motherName,
  });
}

class MotherApiServerService {
  MotherApiServerService._();
  static final MotherApiServerService instance = MotherApiServerService._();

  static const _uuid = Uuid();
  static const String _motherIdKey = 'motherApiServerId';
  static const String _discoveryMagic = 'MOTHER_DISCOVERY_V1';
  static const String _discoveryToken = 'mother-discovery-v1';
  static const String _discoverType = 'discover_mother';
  static const String _helloType = 'mother_hello';
  static const String _apiVersion = '1.0';
  static const int _discoveryPort = 42109;
  static const String _saleCategoriesMetaKey = 'item_sale_categories';
  static const String _businessCategoriesMetaKey = 'item_business_categories';
  static const String _pendingRemoteUserLoginRejectedMessage =
      'Your account is not verified yet. Please contact the shop owner on the main device (mother app) so they can verify your account and assign your role.';

  HttpServer? _server;
  RawDatagramSocket? _discoverySocket;
  Timer? _beaconTimer;
  Timer? _networkRefreshTimer;
  final Map<String, int> _sessionTokens = <String, int>{};
  int _port = 8090;
  String _motherId = '';
  String _primaryLanIp = '127.0.0.1';

  Future<void> start({int port = 8090}) async {
    if (_server != null) return;
    await _ensureMotherIdentity();
    _primaryLanIp = await _detectPrimaryLanIp();
    _port = port;
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.listen(_handleRequest, onError: (_) {});
    await _startUdpDiscovery();
    _startNetworkRefreshWatcher();
  }

  int get port => _port;

  Future<List<String>> getAdvertisedBaseUrls() async {
    final endpoints = await getAdvertisedEndpoints();
    return endpoints.map((e) => e.baseUrl).toList();
  }

  Future<List<MotherApiEndpoint>> getAdvertisedEndpoints() async {
    final endpoints = <MotherApiEndpoint>[];
    final motherName = _resolvedMotherName;
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        final ifaceName = iface.name.toLowerCase();
        for (final addr in iface.addresses) {
          final ip = addr.address.trim();
          if (ip.isEmpty) continue;
          final hotspotLikely =
              ifaceName.contains('ap') ||
              ifaceName.contains('hotspot') ||
              ifaceName.contains('tether') ||
              ifaceName.contains('wlan');
          endpoints.add(
            MotherApiEndpoint(
              interfaceName: iface.name,
              ip: ip,
              baseUrl: 'http://$ip:$_port',
              isHotspotLikely: hotspotLikely,
              motherId: _motherId,
              apiVersion: _apiVersion,
              motherName: motherName,
            ),
          );
        }
      }
    } catch (_) {}
    endpoints.sort((a, b) {
      if (a.isHotspotLikely == b.isHotspotLikely) {
        return a.baseUrl.compareTo(b.baseUrl);
      }
      return a.isHotspotLikely ? -1 : 1;
    });
    final dedup = <String>{};
    return endpoints.where((e) => dedup.add(e.baseUrl)).toList();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      if (request.method == 'GET' && request.uri.path == '/health') {
        return _sendJson(request, 200, {
          'ok': true,
          'motherId': _motherId,
          'name': _resolvedMotherName,
          'apiVersion': _apiVersion,
          'port': _port,
        });
      }
      if (request.method == 'POST' && request.uri.path == '/auth/signup') {
        final body = await _readBody(request);
        final email = (body['email'] ?? '').toString();
        final password = (body['password'] ?? '').toString();
        final name = (body['name'] ?? '').toString();
        if (email.isEmpty || password.isEmpty || name.isEmpty) {
          return _sendJson(request, 400, {'message': 'Missing fields'});
        }
        try {
          await LocalDbService.instance.createRemoteUser(
            email: email,
            password: password,
            name: name,
          );
        } catch (_) {
          return _sendJson(request, 409, {'message': 'User already exists'});
        }
        return _sendJson(request, 201, {
          'message': 'Signup received. Await role assignment from mother app.',
        });
      }
      if (request.method == 'POST' && request.uri.path == '/auth/login') {
        final body = await _readBody(request);
        final email = (body['email'] ?? '').toString();
        final password = (body['password'] ?? '').toString();
        final user = await LocalDbService.instance.getRemoteUserByEmail(email);
        if (user == null || (user['password'] as String? ?? '') != password) {
          return _sendJson(request, 401, {'message': 'Invalid credentials'});
        }
        if (!_remoteUserIsVerifiedForLogin(user)) {
          return _sendJson(request, 403, {
            'message': _pendingRemoteUserLoginRejectedMessage,
            'code': 'PENDING_APPROVAL',
          });
        }
        final userId = user['id'] as int;
        final token = _generateToken();
        _sessionTokens[token] = userId;
        return _sendJson(request, 200, {
          'token': token,
          'user': {
            'id': userId,
            'name': user['name'],
            'email': user['email'],
            'role': user['role'],
            'profilePic': user['profile_pic'],
          },
        });
      }
      if (request.method == 'POST' && request.uri.path == '/auth/reset-password') {
        final body = await _readBody(request);
        final email = (body['email'] ?? '').toString().trim().toLowerCase();
        final newPassword = (body['newPassword'] ?? '').toString();
        if (email.isEmpty || newPassword.isEmpty) {
          return _sendJson(request, 400, {'message': 'Missing fields'});
        }
        final remote = await LocalDbService.instance.updateRemoteUserPasswordByEmail(
          email: email,
          newPassword: newPassword,
        );
        if (remote > 0) {
          return _sendJson(request, 200, {'message': 'Password reset successful.'});
        }
        final local = await LocalDbService.instance.updateAuthPasswordByEmail(
          email: email,
          newPassword: newPassword,
        );
        if (local > 0) {
          return _sendJson(request, 200, {'message': 'Password reset successful.'});
        }
        return _sendJson(request, 404, {'message': 'Account not found.'});
      }
      if (request.method == 'GET' && request.uri.path == '/auth/me') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final user = await LocalDbService.instance.getRemoteUserById(userId);
        if (user == null) {
          return _sendJson(request, 404, {'message': 'User not found'});
        }
        return _sendJson(request, 200, {
          'user': {
            'id': userId,
            'name': user['name'],
            'email': user['email'],
            'role': user['role'],
            'profilePic': user['profile_pic'],
          },
        });
      }
      if ((request.method == 'POST' || request.method == 'PUT') &&
          request.uri.path == '/auth/profile') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final body = await _readBody(request);
        final name = (body['name'] ?? '').toString().trim();
        final email = (body['email'] ?? '').toString().trim().toLowerCase();
        final profilePic = (body['profilePic'] ?? '').toString().trim();
        if (name.isEmpty || email.isEmpty) {
          return _sendJson(request, 400, {'message': 'Name and email are required'});
        }
        final updatedRows = await LocalDbService.instance.updateRemoteUserProfile(
          userId: userId,
          name: name,
          email: email,
          profilePic: profilePic.isEmpty ? null : profilePic,
        );
        if (updatedRows <= 0) {
          return _sendJson(request, 404, {'message': 'User not found'});
        }
        final user = await LocalDbService.instance.getRemoteUserById(userId);
        return _sendJson(request, 200, {
          'message': 'Profile updated successfully.',
          'user': {
            'id': userId,
            'name': user?['name'] ?? name,
            'email': user?['email'] ?? email,
            'role': user?['role'] ?? 'STAFF',
            'profilePic': user?['profile_pic'],
          },
        });
      }
      if (request.uri.path == '/transactions') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final rows = await LocalDbService.instance.getRemoteTransactions();
          return _sendJson(request, 200, {'data': rows});
        }
        if (request.method == 'POST' || request.method == 'PUT') {
          final body = await _readBody(request);
          final description = (body['description'] ?? '').toString();
          final amount = double.tryParse((body['amount'] ?? '').toString());
          if (description.isEmpty || amount == null) {
            return _sendJson(request, 400, {'message': 'Invalid payload'});
          }
          await LocalDbService.instance.insertRemoteTransaction(
            remoteUserId: userId,
            description: description,
            amount: amount,
          );
          return _sendJson(request, 201, {'message': 'Transaction saved'});
        }
      }
      if (request.uri.path == '/stores') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final rows = await LocalDbService.instance.getStores();
          return _sendJson(request, 200, {
            'data': rows.map((e) => e.toMap()).toList(),
          });
        }
        if (request.method == 'POST' || request.method == 'PUT') {
          final body = await _readBody(request);
          final name = (body['name'] ?? '').toString().trim();
          if (name.isEmpty) {
            return _sendJson(request, 400, {'message': 'Store name is required'});
          }
          final store = Store(
            id: _asInt(body['id']),
            name: name,
            description: (body['description'] ?? '').toString().trim().isEmpty
                ? null
                : (body['description'] ?? '').toString().trim(),
            isDefault: ((body['isDefault'] as bool?) ?? false),
          );
          final id = await LocalDbService.instance.upsertStore(store);
          return _sendJson(request, 200, {'message': 'Store saved', 'id': id});
        }
      }
      if (request.uri.path == '/clients') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final rows = await LocalDbService.instance.getClients();
          return _sendJson(request, 200, {
            'data': rows.map((e) => e.toMap()).toList(),
          });
        }
        if (request.method == 'POST' || request.method == 'PUT') {
          final body = await _readBody(request);
          final name = (body['name'] ?? '').toString().trim();
          if (name.isEmpty) {
            return _sendJson(request, 400, {'message': 'Client name is required'});
          }
          final client = Client(
            id: _asInt(body['id']),
            storeId: _asInt(body['storeId']),
            name: name,
            phone: (body['phone'] ?? '').toString().trim().isEmpty
                ? null
                : (body['phone'] ?? '').toString().trim(),
            address: (body['address'] ?? '').toString().trim().isEmpty
                ? null
                : (body['address'] ?? '').toString().trim(),
          );
          final id = await LocalDbService.instance.upsertClient(client);
          return _sendJson(request, 200, {'message': 'Client saved', 'id': id});
        }
      }
      if (request.method == 'GET' && request.uri.path == '/clients/account') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final clientId = _asInt(request.uri.queryParameters['clientId']);
        if (clientId == null || clientId <= 0) {
          return _sendJson(request, 400, {'message': 'Missing clientId'});
        }
        final balance = await LocalDbService.instance.getClientAccountBalance(clientId);
        return _sendJson(request, 200, {'clientId': clientId, 'balance': balance});
      }
      if (request.method == 'GET' && request.uri.path == '/clients/account/transactions') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final clientId = _asInt(request.uri.queryParameters['clientId']);
        if (clientId == null || clientId <= 0) {
          return _sendJson(request, 400, {'message': 'Missing clientId'});
        }
        final rows = await LocalDbService.instance.getClientAccountTransactions(clientId);
        return _sendJson(request, 200, {'clientId': clientId, 'data': rows});
      }
      if ((request.method == 'POST' || request.method == 'PUT') &&
          request.uri.path == '/clients/account/transaction') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final body = await _readBody(request);
        final clientId = _asInt(body['clientId']);
        final amount = _asDouble(body['amount']);
        final transactionType = (body['transactionType'] ?? '').toString().trim();
        final note = (body['note'] ?? '').toString().trim();
        if (clientId == null || amount == null || amount == 0 || transactionType.isEmpty) {
          return _sendJson(request, 400, {'message': 'Invalid account transaction payload'});
        }
        final clientRows = await LocalDbService.instance.getClients();
        Client? client;
        for (final c in clientRows) {
          if (c.id == clientId) {
            client = c;
            break;
          }
        }
        if (client == null) {
          return _sendJson(request, 404, {'message': 'Client not found'});
        }
        try {
          await LocalDbService.instance.recordClientAccountTransaction(
            clientId: clientId,
            storeId: client.storeId,
            transactionType: transactionType,
            amount: amount,
            note: note,
          );
          final balance = await LocalDbService.instance.getClientAccountBalance(clientId);
          return _sendJson(request, 200, {
            'message': 'Account transaction saved',
            'balance': balance,
          });
        } catch (e) {
          return _sendJson(request, 400, {'message': '$e'});
        }
      }
      if (request.uri.path == '/items') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final rows = await LocalDbService.instance.getItems();
          return _sendJson(request, 200, {
            'data': await _itemsPayloadWithBarcodes(rows),
          });
        }
        if (request.method == 'POST' || request.method == 'PUT') {
          final body = await _readBody(request);
          final name = (body['name'] ?? '').toString().trim();
          if (name.isEmpty) {
            return _sendJson(request, 400, {'message': 'Item name is required'});
          }
          final incomingId = _asInt(body['id']);
          Item? existingItem;
          if (incomingId != null) {
            final existingItems = await LocalDbService.instance.getItems();
            for (final row in existingItems) {
              if (row.id == incomingId) {
                existingItem = row;
                break;
              }
            }
          }
          final costPriceRaw = _asDouble(body['costPrice'] ?? body['cost_price']);
          final sellingPriceRaw = _asDouble(
            body['sellingPrice'] ?? body['selling_price'],
          );
          final stockQtyRaw = _asDouble(body['stockQty'] ?? body['stock_qty']);
          final reorderLevelRaw = _asDouble(
            body['reorderLevel'] ?? body['reorder_level'],
          );
          final restockToRaw = _asDouble(body['restockTo'] ?? body['restock_to']);
          final skuRaw = (body['sku'] ?? '').toString().trim();
          final barcodeRaw = (body['barcode'] ?? '').toString().trim();
          String? sku = skuRaw.isEmpty ? null : skuRaw;
          String? barcode = barcodeRaw.isEmpty ? null : barcodeRaw;
          if (incomingId != null && existingItem != null) {
            if (sku == null || sku.isEmpty) {
              sku = (existingItem.sku ?? '').trim().isEmpty
                  ? null
                  : existingItem.sku!.trim();
            }
            if (barcode == null || barcode.isEmpty) {
              barcode = (existingItem.barcode ?? '').trim().isEmpty
                  ? null
                  : existingItem.barcode!.trim();
            }
          } else if (incomingId == null) {
            if ((sku == null || sku.isEmpty) &&
                (barcode == null || barcode.isEmpty)) {
              sku = null;
              barcode = null;
            } else {
              if (sku != null &&
                  sku.isNotEmpty &&
                  (barcode == null || barcode.isEmpty)) {
                barcode = sku;
              }
              if (barcode != null &&
                  barcode.isNotEmpty &&
                  (sku == null || sku.isEmpty)) {
                sku = barcode;
              }
            }
          }
          final item = Item(
            id: incomingId,
            storeId:
                _asInt(body['storeId'] ?? body['store_id']) ?? existingItem?.storeId,
            name: name,
            sku: sku,
            barcode: barcode,
            category: _resolveOptionalStringField(
              body,
              camel: 'category',
              snake: 'category',
              existing: existingItem?.category,
            ),
            unit: _resolveOptionalStringField(
              body,
              camel: 'unit',
              snake: 'unit',
              existing: existingItem?.unit,
            ),
            unitShort: _resolveOptionalStringField(
              body,
              camel: 'unitShort',
              snake: 'unit_short',
              existing: existingItem?.unitShort,
            ),
            shelfNumber: _resolveOptionalStringField(
              body,
              camel: 'shelfNumber',
              snake: 'shelf_number',
              existing: existingItem?.shelfNumber,
            ),
            imageUrl: _resolveOptionalStringField(
              body,
              camel: 'imageUrl',
              snake: 'image_url',
              existing: existingItem?.imageUrl,
            ),
            imageUrl2: _resolveOptionalStringField(
              body,
              camel: 'imageUrl2',
              snake: 'image_url_2',
              existing: existingItem?.imageUrl2,
            ),
            imageUrl3: _resolveOptionalStringField(
              body,
              camel: 'imageUrl3',
              snake: 'image_url_3',
              existing: existingItem?.imageUrl3,
            ),
            packagingId:
                _asInt(body['packagingId'] ?? body['packaging_id']) ??
                existingItem?.packagingId,
            variantGroup: _resolveOptionalStringField(
              body,
              camel: 'variantGroup',
              snake: 'variant_group',
              existing: existingItem?.variantGroup,
            ),
            unitsPerPackage:
                _asDouble(body['unitsPerPackage'] ?? body['units_per_package']) ??
                existingItem?.unitsPerPackage,
            costPrice: costPriceRaw ?? existingItem?.costPrice ?? 0,
            sellingPrice: sellingPriceRaw ?? existingItem?.sellingPrice ?? 0,
            stockQty: stockQtyRaw ?? existingItem?.stockQty ?? 0,
            reorderLevel: reorderLevelRaw ?? existingItem?.reorderLevel ?? 0,
            restockTo: restockToRaw ?? existingItem?.restockTo ?? 0,
            createdAt: existingItem?.createdAt,
          );
          final id = await LocalDbService.instance.upsertItem(item);
          final persistedId = incomingId ?? item.id ?? (id > 0 ? id : null);
          if (persistedId != null && persistedId > 0) {
            if (_bodyHasKey(body, 'acceptedBarcodes', 'accepted_barcodes')) {
              final accepted = _parseAcceptedBarcodesList(body);
              await LocalDbService.instance.replaceItemBarcodes(
                itemId: persistedId,
                barcodes: accepted,
              );
            }
          }
          final rows = await LocalDbService.instance.getItems();
          return _sendJson(request, 200, {
            'message': 'Item saved',
            'id': persistedId ?? id,
            'data': await _itemsPayloadWithBarcodes(rows),
          });
        }
      }
      if (request.method == 'POST' &&
          request.uri.path == '/items/special-sale-outcomes') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final body = await _readBody(request);
        final updatesRaw = body['updates'];
        if (updatesRaw is! List) {
          return _sendJson(request, 400, {'message': 'Missing updates list'});
        }
        for (final row in updatesRaw) {
          if (row is! Map) continue;
          final map = row is Map<String, dynamic>
              ? row
              : Map<String, dynamic>.from(row);
          final itemId = _asInt(map['itemId']);
          if (itemId == null || itemId <= 0) continue;
          final stillAvailable = map['stillAvailable'] == true;
          final metersSold = _asDouble(map['metersSold']) ?? 0;
          await LocalDbService.instance.applySpecialItemSaleOutcome(
            itemId: itemId,
            stillAvailable: stillAvailable,
            metersSold: metersSold,
          );
        }
        final rows = await LocalDbService.instance.getItems();
        return _sendJson(request, 200, {
          'message': 'Special item stock updated',
          'data': await _itemsPayloadWithBarcodes(rows),
        });
      }
      if (request.method == 'GET' && request.uri.path == '/items/transactions') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final itemIdRaw = request.uri.queryParameters['itemId'];
        final itemId = _asInt(itemIdRaw);
        if (itemId == null || itemId <= 0) {
          return _sendJson(request, 400, {
            'message': 'Missing or invalid itemId query parameter',
          });
        }
        final rows = await _getItemTransactions(itemId);
        return _sendJson(request, 200, {
          'itemId': itemId,
          'data': rows,
        });
      }
      if ((request.method == 'POST' || request.method == 'PUT') &&
          request.uri.path == '/items/delete') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final body = await _readBody(request);
        final itemId = _asInt(body['id']);
        if (itemId == null) {
          return _sendJson(request, 400, {'message': 'Missing item id'});
        }
        final deleted = await LocalDbService.instance.deleteItem(itemId);
        final rows = await LocalDbService.instance.getItems();
        return _sendJson(request, 200, {
          'message': deleted > 0 ? 'Item deleted' : 'Item not found',
          'data': rows.map((e) => e.toMap()).toList(),
        });
      }
      if (request.uri.path == '/units') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final rows = await LocalDbService.instance.getUnits();
          return _sendJson(request, 200, {
            'data': rows.map((e) => e.toMap()).toList(),
          });
        }
        if (request.method == 'POST' || request.method == 'PUT') {
          final body = await _readBody(request);
          final unitName = (body['unitName'] ?? body['unit_name'] ?? '')
              .toString()
              .trim();
          final unitShortName = (body['unitShortName'] ??
                  body['unit_short_name'] ??
                  '')
              .toString()
              .trim();
          if (unitName.isEmpty || unitShortName.isEmpty) {
            return _sendJson(request, 400, {
              'message': 'Unit name and short name are required',
            });
          }
          final unit = Unit(
            id: _asInt(body['id']),
            unitName: unitName,
            unitShortName: unitShortName,
          );
          final id = unit.id == null
              ? await LocalDbService.instance.insertUnit(unit)
              : (await LocalDbService.instance.updateUnit(unit)) > 0
              ? unit.id!
              : unit.id!;
          return _sendJson(request, 200, {'message': 'Unit saved', 'id': id});
        }
      }
      if (request.uri.path == '/item-categories') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final categoryType = _categoryTypeFromRequest(request.uri.queryParameters['type']);
        if (categoryType == null) {
          return _sendJson(request, 400, {
            'message': 'Missing or invalid type. Use sale or business.',
          });
        }
        if (request.method == 'GET') {
          final values = await _getItemCategoryList(categoryType);
          return _sendJson(request, 200, {
            'type': categoryType,
            'data': values,
          });
        }
        if (request.method == 'POST' || request.method == 'PUT') {
          final body = await _readBody(request);
          final name = (body['name'] ?? '').toString().trim();
          final oldName = (body['oldName'] ?? '').toString().trim();
          if (name.isEmpty) {
            return _sendJson(request, 400, {'message': 'Category name is required'});
          }
          final values = await _getItemCategoryList(categoryType);
          if (oldName.isNotEmpty) {
            final idx = values.indexWhere(
              (v) => v.trim().toLowerCase() == oldName.toLowerCase(),
            );
            if (idx >= 0) {
              values[idx] = name;
            } else {
              values.add(name);
            }
          } else {
            values.add(name);
          }
          await _setItemCategoryList(categoryType, values);
          return _sendJson(request, 200, {
            'message': 'Category saved',
            'type': categoryType,
            'data': await _getItemCategoryList(categoryType),
          });
        }
        return _sendJson(request, 405, {'message': 'Method not allowed'});
      }
      if ((request.method == 'POST' || request.method == 'PUT') &&
          request.uri.path == '/item-categories/delete') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final body = await _readBody(request);
        final categoryType = _categoryTypeFromRequest(body['type']?.toString());
        final name = (body['name'] ?? '').toString().trim();
        if (categoryType == null || name.isEmpty) {
          return _sendJson(request, 400, {'message': 'Type and name are required'});
        }
        final values = await _getItemCategoryList(categoryType);
        values.removeWhere((v) => v.trim().toLowerCase() == name.toLowerCase());
        await _setItemCategoryList(categoryType, values);
        return _sendJson(request, 200, {
          'message': 'Category deleted',
          'type': categoryType,
          'data': await _getItemCategoryList(categoryType),
        });
      }
      if ((request.method == 'POST' || request.method == 'PUT') &&
          request.uri.path == '/units/delete') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final body = await _readBody(request);
        final unitId = _asInt(body['id']);
        if (unitId == null) {
          return _sendJson(request, 400, {'message': 'Missing unit id'});
        }
        final deleted = await LocalDbService.instance.deleteUnit(unitId);
        final rows = await LocalDbService.instance.getUnits();
        return _sendJson(request, 200, {
          'message': deleted > 0 ? 'Unit deleted' : 'Unit not found',
          'data': rows.map((e) => e.toMap()).toList(),
        });
      }
      if (request.uri.path == '/stock/receive') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final rows = await LocalDbService.instance.getStockReceiptsWithDetails();
          return _sendJson(request, 200, {'data': rows});
        }
        if (request.method != 'POST' && request.method != 'PUT') {
          return _sendJson(request, 405, {'message': 'Method not allowed'});
        }
        final body = await _readBody(request);
        final itemId = _asInt(body['itemId']);
        final quantity = _asDouble(body['quantity']);
        if (itemId == null || quantity == null || quantity <= 0) {
          return _sendJson(request, 400, {'message': 'Invalid stock payload'});
        }
        final updated = await LocalDbService.instance.receiveStock(
          itemId: itemId,
          quantity: quantity,
          unitCost: _asDouble(body['unitCost']),
          totalCost: _asDouble(body['totalCost']),
          sellingPrice: _asDouble(body['sellingPrice']),
          brand: (body['brand'] ?? '').toString().trim().isEmpty
              ? null
              : (body['brand'] ?? '').toString().trim(),
          expiryDate: _asDate(body['expiryDate']),
          storeId: _asInt(body['storeId']),
        );
        return _sendJson(request, 200, {
          'message': 'Stock received',
          'updatedRows': updated,
        });
      }
      if (request.uri.path == '/stock/adjust') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method != 'POST' && request.method != 'PUT') {
          return _sendJson(request, 405, {'message': 'Method not allowed'});
        }
        final body = await _readBody(request);
        final itemId = _asInt(body['itemId']);
        final quantity = _asDouble(body['quantity']);
        final type = (body['type'] ?? '').toString().trim().toLowerCase();
        if (itemId == null ||
            quantity == null ||
            quantity <= 0 ||
            (type != 'add' && type != 'remove')) {
          return _sendJson(request, 400, {'message': 'Invalid stock adjustment payload'});
        }
        final items = await LocalDbService.instance.getItems();
        Item? item;
        for (final current in items) {
          if (current.id == itemId) {
            item = current;
            break;
          }
        }
        if (item == null) {
          return _sendJson(request, 404, {'message': 'Item not found'});
        }
        if (type == 'remove' && item.stockQty < quantity) {
          final maxStock = item.stockQty == item.stockQty.roundToDouble()
              ? item.stockQty.toInt().toString()
              : item.stockQty.toStringAsFixed(2);
          return _sendJson(request, 400, {
            'message': 'Not enough stock. Max is $maxStock.',
          });
        }
        final signedQty = type == 'remove' ? -quantity : quantity;
        final reason = (body['reason'] ?? '').toString().trim();
        final brandTag = reason.isEmpty ? 'ADJ|' : 'ADJ|$reason';
        final updated = await LocalDbService.instance.receiveStock(
          itemId: itemId,
          quantity: signedQty,
          unitCost: item.costPrice,
          totalCost: item.costPrice * signedQty,
          sellingPrice: item.sellingPrice,
          brand: brandTag,
          receivedAt: _asDate(body['adjustedAt']) ?? DateTime.now(),
          storeId: _asInt(body['storeId']) ?? item.storeId,
        );
        return _sendJson(request, 200, {
          'message': 'Stock adjusted',
          'updatedRows': updated,
        });
      }
      if (request.uri.path == '/sales') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final rows = await LocalDbService.instance.getSalesWithItemDetails();
          return _sendJson(request, 200, {'data': rows});
        }
        if (request.method != 'POST' && request.method != 'PUT') {
          return _sendJson(request, 405, {'message': 'Method not allowed'});
        }
        final body = await _readBody(request);
        final totalAmount = _asDouble(body['totalAmount']);
        final itemsRaw = body['items'];
        if (totalAmount == null ||
            totalAmount <= 0 ||
            itemsRaw is! List ||
            itemsRaw.isEmpty) {
          return _sendJson(request, 400, {'message': 'Invalid sale payload'});
        }
        final saleItems = <SaleItem>[];
        for (final row in itemsRaw) {
          if (row is! Map<String, dynamic>) continue;
          final itemId = _asInt(row['itemId']);
          final quantity = _asDouble(row['quantity']);
          final unitPrice = _asDouble(row['unitPrice']);
          final productDiscount = _asDouble(row['productDiscount']) ?? 0;
          if (itemId == null ||
              quantity == null ||
              unitPrice == null ||
              quantity <= 0 ||
              unitPrice < 0 ||
              productDiscount < 0) {
            return _sendJson(request, 400, {'message': 'Invalid sale item payload'});
          }
          saleItems.add(
            SaleItem(
              itemId: itemId,
              quantity: quantity,
              unitPrice: unitPrice,
              productDiscount: productDiscount,
            ),
          );
        }
        if (saleItems.isEmpty) {
          return _sendJson(request, 400, {'message': 'No sale items provided'});
        }
        final amountReceived = _asDouble(body['amountReceived']) ?? totalAmount;
        final balance = _asDouble(body['balance']) ?? (totalAmount - amountReceived);
        final overallDiscount = _asDouble(body['overallDiscount']) ?? 0;
        final paymentMethodRaw =
            (body['paymentMethod'] ?? '').toString().trim().toLowerCase();
        final paymentMethod = paymentMethodRaw.isEmpty ? 'cash' : paymentMethodRaw;
        final sale = Sale(
          storeId: _asInt(body['storeId']),
          totalAmount: totalAmount,
          overallDiscount: overallDiscount < 0 ? 0 : overallDiscount,
          amountReceived: amountReceived,
          balance: balance,
          customerName: (body['customerName'] ?? '').toString().trim().isEmpty
              ? null
              : (body['customerName'] ?? '').toString().trim(),
          customerPhone: (body['customerPhone'] ?? '').toString().trim().isEmpty
              ? null
              : (body['customerPhone'] ?? '').toString().trim(),
          customerAddress:
              (body['customerAddress'] ?? '').toString().trim().isEmpty
              ? null
              : (body['customerAddress'] ?? '').toString().trim(),
          paymentMethod: paymentMethod,
        );
        try {
          final saleId = await LocalDbService.instance.createSale(sale, saleItems);
          return _sendJson(request, 201, {'message': 'Sale saved', 'saleId': saleId});
        } catch (e) {
          return _sendJson(request, 400, {'message': e.toString()});
        }
      }
      if ((request.method == 'POST' || request.method == 'PUT') &&
          request.uri.path == '/sales/delete') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final body = await _readBody(request);
        final saleId = _asInt(body['id']);
        if (saleId == null) {
          return _sendJson(request, 400, {'message': 'Missing sale id'});
        }
        try {
          final deleted = await LocalDbService.instance.deleteSale(saleId);
          final rows = await LocalDbService.instance.getSalesWithItemDetails();
          return _sendJson(request, 200, {
            'message': deleted > 0 ? 'Sale deleted' : 'Sale not found',
            'data': rows,
          });
        } catch (e) {
          return _sendJson(request, 400, {'message': e.toString()});
        }
      }
      if (request.method == 'GET' && request.uri.path == '/sales/history') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final rows = await LocalDbService.instance.getSalesWithItemDetails();
        return _sendJson(request, 200, {'data': rows});
      }
      if (request.method == 'GET' && request.uri.path == '/sales/by-customer') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final name = (request.uri.queryParameters['name'] ?? '').trim();
        if (name.isEmpty) {
          return _sendJson(request, 400, {'message': 'Missing customer name'});
        }
        final rows = await LocalDbService.instance.getSalesWithItemDetailsByCustomer(
          name,
        );
        return _sendJson(request, 200, {'data': rows});
      }
      if (request.method == 'GET' && request.uri.path == '/debts') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final isPaidRaw = request.uri.queryParameters['isPaid'];
        bool? isPaid;
        if (isPaidRaw != null) {
          final raw = isPaidRaw.trim().toLowerCase();
          isPaid = raw == '1' || raw == 'true' || raw == 'yes';
        }
        final debts = await LocalDbService.instance.getDebts(isPaid: isPaid);
        return _sendJson(request, 200, {
          'data': debts.map((e) => e.toMap()).toList(),
        });
      }
      if (request.method == 'GET' && request.uri.path == '/debt-payments') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final customerName = (request.uri.queryParameters['customerName'] ?? '')
            .trim();
        final rows = await LocalDbService.instance.getDebtPayments(
          customerName: customerName.isEmpty ? null : customerName,
        );
        return _sendJson(request, 200, {
          'data': rows.map((e) => e.toMap()).toList(),
        });
      }
      if (request.uri.path == '/debts/pay') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final customerName = (request.uri.queryParameters['customerName'] ?? '')
              .trim();
          final rows = await LocalDbService.instance.getDebtPayments(
            customerName: customerName.isEmpty ? null : customerName,
          );
          return _sendJson(request, 200, {
            'data': rows.map((e) => e.toMap()).toList(),
          });
        }
        if (request.method != 'POST' && request.method != 'PUT') {
          return _sendJson(request, 405, {'message': 'Method not allowed'});
        }
        final body = await _readBody(request);
        final customerName = (body['customerName'] ?? '').toString().trim();
        final amount = _asDouble(body['amount']);
        final clientId = _asInt(body['clientId']);
        final useClientAccount = (body['useClientAccount'] as bool?) ?? false;
        if (customerName.isEmpty || amount == null || amount <= 0) {
          return _sendJson(request, 400, {'message': 'Invalid debt payment payload'});
        }
        double remaining;
        try {
          if (useClientAccount) {
            if (clientId == null || clientId <= 0) {
              return _sendJson(request, 400, {
                'message': 'clientId is required when useClientAccount is true',
              });
            }
            final clients = await LocalDbService.instance.getClients();
            Client? client;
            for (final c in clients) {
              if (c.id == clientId) {
                client = c;
                break;
              }
            }
            if (client == null) {
              return _sendJson(request, 404, {'message': 'Client not found'});
            }
            remaining = await LocalDbService.instance.payDebtForCustomerFromClientAccount(
              clientId: clientId,
              customerName: customerName,
              paymentAmount: amount,
              storeId: client.storeId,
            );
          } else {
            remaining = await LocalDbService.instance.payDebtForCustomer(
              customerName: customerName,
              paymentAmount: amount,
            );
          }
        } catch (e) {
          return _sendJson(request, 400, {'message': '$e'});
        }
        return _sendJson(request, 200, {
          'message': 'Debt payment saved',
          'remaining': remaining,
        });
      }
      if (request.uri.path == '/loans') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final rows = await LocalDbService.instance.getLoans();
          return _sendJson(request, 200, {
            'data': rows.map((e) => e.toRemoteBody()).toList(),
          });
        }
        if (request.method == 'POST' || request.method == 'PUT') {
          final body = await _readBody(request);
          final clientId = _asInt(body['clientId'] ?? body['client_id']);
          final principal = _asDouble(
            body['principalAmount'] ?? body['principal_amount'],
          );
          final pct = _asDouble(
                body['annualInterestPercent'] ?? body['annual_interest_percent'],
              ) ??
              0;
          final expected = _asDate(
            body['expectedPaymentDate'] ?? body['expected_payment_date'],
          );
          if (clientId == null ||
              clientId <= 0 ||
              principal == null ||
              principal <= 0 ||
              expected == null) {
            return _sendJson(request, 400, {'message': 'Invalid loan payload'});
          }
          final issued =
              _asDate(body['createdAt'] ?? body['created_at']) ?? DateTime.now();
          final accrued = Loan.computeAccrued(
            principal: principal,
            annualInterestPercent: pct,
            issuedAt: issued,
            expectedPaymentDate: expected,
          );
          final statusRaw = (body['status'] ?? 'active').toString().trim();
          final loan = Loan(
            id: _asInt(body['id']),
            storeId: _asInt(body['storeId'] ?? body['store_id']),
            clientId: clientId,
            principalAmount: principal,
            annualInterestPercent: pct,
            expectedPaymentDate: expected,
            interestAmount: accrued.interest,
            totalDue: accrued.total,
            note: (body['note'] ?? '').toString().trim().isEmpty
                ? null
                : (body['note'] ?? '').toString().trim(),
            status: statusRaw.isEmpty ? 'active' : statusRaw,
            createdAt: issued,
          );
          final id = await LocalDbService.instance.upsertLoan(loan);
          return _sendJson(request, 200, {'message': 'Loan saved', 'id': id});
        }
      }
      if (request.uri.path == '/loans/payments') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final loanId = _asInt(request.uri.queryParameters['loanId']);
          final clientId = _asInt(request.uri.queryParameters['clientId']);
          final rows = await LocalDbService.instance.getLoanPayments(
            loanId: loanId,
            clientId: clientId,
          );
          return _sendJson(request, 200, {'data': rows});
        }
        if (request.method == 'POST') {
          final body = await _readBody(request);
          final loanId = _asInt(body['loanId'] ?? body['loan_id']);
          final clientId = _asInt(body['clientId'] ?? body['client_id']);
          final amount = _asDouble(body['amount']);
          if (loanId == null || clientId == null || amount == null || amount <= 0) {
            return _sendJson(request, 400, {'message': 'Invalid loan payment payload'});
          }
          try {
            final remaining = await LocalDbService.instance.payLoan(
              loanId: loanId,
              clientId: clientId,
              amount: amount,
              storeId: _asInt(body['storeId'] ?? body['store_id']),
              note: (body['note'] ?? '').toString().trim(),
            );
            return _sendJson(request, 200, {
              'message': 'Loan payment saved',
              'remaining': remaining,
            });
          } catch (e) {
            return _sendJson(request, 400, {'message': '$e'});
          }
        }
      }
      if (request.uri.path == '/expenses') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final rows = await LocalDbService.instance.getExpenses();
          return _sendJson(request, 200, {
            'data': rows.map((e) => e.toMap()).toList(),
          });
        }
        if (request.method == 'POST' || request.method == 'PUT') {
          final body = await _readBody(request);
          final title = (body['title'] ?? '').toString().trim();
          final amount = _asDouble(body['amount']);
          if (title.isEmpty || amount == null || amount <= 0) {
            return _sendJson(request, 400, {'message': 'Invalid expense payload'});
          }
          final expense = Expense(
            id: _asInt(body['id']),
            storeId: _asInt(body['storeId'] ?? body['store_id']),
            title: title,
            category: (body['category'] ?? '').toString().trim().isEmpty
                ? null
                : (body['category'] ?? '').toString().trim(),
            paidBy: (body['paidBy'] ?? body['paid_by']).toString().trim().isEmpty
                ? null
                : (body['paidBy'] ?? body['paid_by']).toString().trim(),
            receivedBy: (body['receivedBy'] ?? body['received_by'])
                    .toString()
                    .trim()
                    .isEmpty
                ? null
                : (body['receivedBy'] ?? body['received_by']).toString().trim(),
            notes: (body['notes'] ?? '').toString().trim().isEmpty
                ? null
                : (body['notes'] ?? '').toString().trim(),
            amount: amount,
            createdAt:
                _asDate(body['createdAt'] ?? body['created_at']) ?? DateTime.now(),
          );
          final id = await LocalDbService.instance.upsertExpense(expense);
          return _sendJson(request, 200, {'message': 'Expense saved', 'id': id});
        }
      }
      if (request.uri.path == '/services') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final rows = await LocalDbService.instance.getServiceTransactions();
          return _sendJson(request, 200, {
            'data': rows.map((e) => e.toMap()).toList(),
          });
        }
        if (request.method == 'POST' || request.method == 'PUT') {
          final body = await _readBody(request);
          final title =
              (body['title'] ?? body['name'] ?? '').toString().trim();
          final amount = _asDouble(body['amount'] ?? body['price']);
          if (title.isEmpty || amount == null || amount <= 0) {
            return _sendJson(request, 400, {'message': 'Invalid service payload'});
          }
          final service = ServiceTransaction(
            id: _asInt(body['id']),
            storeId: _asInt(body['storeId'] ?? body['store_id']),
            title: title,
            notes: (body['notes'] ?? body['description'] ?? '')
                    .toString()
                    .trim()
                    .isEmpty
                ? null
                : (body['notes'] ?? body['description'] ?? '').toString().trim(),
            amount: amount,
            createdAt:
                _asDate(body['createdAt'] ?? body['created_at']) ?? DateTime.now(),
          );
          final id = await LocalDbService.instance.upsertServiceTransaction(service);
          final rows = await LocalDbService.instance.getServiceTransactions();
          return _sendJson(request, 200, {
            'message': 'Service saved',
            'id': id,
            'data': rows.map((e) => e.toMap()).toList(),
          });
        }
      }
      if ((request.method == 'POST' || request.method == 'PUT') &&
          request.uri.path == '/expenses/delete') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final body = await _readBody(request);
        final expenseId = _asInt(body['id']);
        if (expenseId == null) {
          return _sendJson(request, 400, {'message': 'Missing expense id'});
        }
        final deleted = await LocalDbService.instance.deleteExpense(expenseId);
        final rows = await LocalDbService.instance.getExpenses();
        return _sendJson(request, 200, {
          'message': deleted > 0 ? 'Expense deleted' : 'Expense not found',
          'data': rows.map((e) => e.toMap()).toList(),
        });
      }
      if (request.uri.path == '/assets') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final rows = await LocalDbService.instance.getAssets();
          return _sendJson(request, 200, {
            'data': rows.map((e) => e.toMap()).toList(),
          });
        }
        if (request.method == 'POST' || request.method == 'PUT') {
          final body = await _readBody(request);
          final name = (body['name'] ?? '').toString().trim();
          if (name.isEmpty) {
            return _sendJson(request, 400, {'message': 'Asset name is required'});
          }
          final purchaseCost =
              _asDouble(body['purchaseCost'] ?? body['purchase_cost']) ?? 0;
          var currentValue =
              _asDouble(body['currentValue'] ?? body['current_value']) ??
                  purchaseCost;
          if (currentValue < 0) currentValue = 0;
          final purchaseDate = _asDate(
                body['purchaseDate'] ?? body['purchase_date'],
              ) ??
              DateTime.now();
          final asset = Asset(
            id: _asInt(body['id']),
            storeId: _asInt(body['storeId'] ?? body['store_id']),
            name: name,
            purchaseCost: purchaseCost < 0 ? 0 : purchaseCost,
            currentValue: currentValue,
            purchaseDate: purchaseDate,
            notes: (body['notes'] ?? '').toString().trim().isEmpty
                ? null
                : (body['notes'] ?? '').toString().trim(),
            createdAt:
                _asDate(body['createdAt'] ?? body['created_at']) ?? DateTime.now(),
            updatedAt:
                _asDate(body['updatedAt'] ?? body['updated_at']) ?? DateTime.now(),
          );
          final id = await LocalDbService.instance.upsertAsset(asset);
          final rows = await LocalDbService.instance.getAssets();
          return _sendJson(request, 200, {
            'message': 'Asset saved',
            'id': id,
            'data': rows.map((e) => e.toMap()).toList(),
          });
        }
      }
      if ((request.method == 'POST' || request.method == 'PUT') &&
          request.uri.path == '/assets/delete') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final body = await _readBody(request);
        final assetId = _asInt(body['id']);
        if (assetId == null) {
          return _sendJson(request, 400, {'message': 'Missing asset id'});
        }
        final deleted = await LocalDbService.instance.deleteAsset(assetId);
        final rows = await LocalDbService.instance.getAssets();
        return _sendJson(request, 200, {
          'message': deleted > 0 ? 'Asset deleted' : 'Asset not found',
          'data': rows.map((e) => e.toMap()).toList(),
        });
      }
      if (request.method == 'GET' &&
          request.uri.path == '/assets/depreciations') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final assetId = _asInt(
          request.uri.queryParameters['assetId'] ??
              request.uri.queryParameters['asset_id'],
        );
        if (assetId == null) {
          return _sendJson(request, 400, {'message': 'Missing assetId'});
        }
        final rows =
            await LocalDbService.instance.getAssetDepreciations(assetId);
        return _sendJson(request, 200, {'data': rows});
      }
      if (request.method == 'POST' && request.uri.path == '/assets/depreciate') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final body = await _readBody(request);
        final assetId = _asInt(body['assetId'] ?? body['asset_id']);
        final amount = _asDouble(body['amount']);
        if (assetId == null || amount == null || amount <= 0) {
          return _sendJson(
            request,
            400,
            {'message': 'Invalid depreciation payload'},
          );
        }
        final noteRaw = (body['note'] ?? '').toString().trim();
        await LocalDbService.instance.addAssetDepreciation(
          assetId: assetId,
          amount: amount,
          note: noteRaw.isEmpty ? null : noteRaw,
        );
        final assets = await LocalDbService.instance.getAssets();
        final history =
            await LocalDbService.instance.getAssetDepreciations(assetId);
        return _sendJson(request, 200, {
          'message': 'Depreciation recorded',
          'data': assets.map((e) => e.toMap()).toList(),
          'depreciations': history,
        });
      }
      if ((request.method == 'POST' || request.method == 'PUT') &&
          request.uri.path == '/services/delete') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final body = await _readBody(request);
        final serviceId = _asInt(body['id']);
        if (serviceId == null) {
          return _sendJson(request, 400, {'message': 'Missing service id'});
        }
        final deleted = await LocalDbService.instance.deleteServiceTransaction(
          serviceId,
        );
        final rows = await LocalDbService.instance.getServiceTransactions();
        return _sendJson(request, 200, {
          'message': deleted > 0 ? 'Service deleted' : 'Service not found',
          'data': rows.map((e) => e.toMap()).toList(),
        });
      }
      if (request.method == 'GET' && request.uri.path == '/stock/receipts') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final rows = await LocalDbService.instance.getStockReceiptsWithDetails();
        return _sendJson(request, 200, {'data': rows});
      }
      if ((request.method == 'POST' || request.method == 'PUT') &&
          request.uri.path == '/stock/receipts/delete') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final body = await _readBody(request);
        final receiptId = _asInt(body['id']);
        if (receiptId == null) {
          return _sendJson(request, 400, {'message': 'Missing receipt id'});
        }
        try {
          final deleted = await LocalDbService.instance.deleteStockReceipt(
            receiptId,
          );
          final rows = await LocalDbService.instance.getStockReceiptsWithDetails();
          return _sendJson(request, 200, {
            'message': deleted > 0 ? 'Receive record deleted' : 'Receipt not found',
            'data': rows,
          });
        } catch (e) {
          return _sendJson(request, 400, {'message': e.toString()});
        }
      }
      if (request.uri.path == '/stock/transfers' ||
          request.uri.path == '/stock/transfer') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        if (request.method == 'GET') {
          final rows = await LocalDbService.instance.getStockTransfersWithDetails();
          return _sendJson(request, 200, {'data': rows});
        }
        if (request.method == 'POST' || request.method == 'PUT') {
          final body = await _readBody(request);
          final destinationOnly = body['destinationOnly'] == true;
          if (destinationOnly) {
            final fromItemId = _asInt(body['fromItemId']);
            final toItemId = _asInt(body['toItemId']);
            final toQuantity = _asDouble(body['toQuantity']);
            if (fromItemId == null ||
                toItemId == null ||
                toQuantity == null ||
                toQuantity <= 0) {
              return _sendJson(request, 400, {
                'message': 'Invalid destination-only transfer payload',
              });
            }
            try {
              final transferId =
                  await LocalDbService.instance.transferStockAdditionalDestination(
                fromItemId: fromItemId,
                toItemId: toItemId,
                toQuantity: toQuantity,
                toCostPrice: _asDouble(body['toCostPrice']),
                toSellingPrice: _asDouble(body['toSellingPrice']),
                storeId: _asInt(body['storeId']),
              );
              return _sendJson(request, 200, {
                'message': 'Stock transfer saved',
                'transferId': transferId,
              });
            } catch (e) {
              return _sendJson(request, 400, {'message': '$e'});
            }
          }
          final fromItemId = _asInt(body['fromItemId']);
          final toItemId = _asInt(body['toItemId']);
          final fromQuantity = _asDouble(body['fromQuantity']);
          final conversionFactor = _asDouble(body['conversionFactor']);
          if (fromItemId == null ||
              toItemId == null ||
              fromQuantity == null ||
              conversionFactor == null ||
              fromQuantity <= 0 ||
              conversionFactor <= 0) {
            return _sendJson(request, 400, {
              'message': 'Invalid stock transfer payload',
            });
          }
          try {
            final transferId = await LocalDbService.instance.transferStock(
              fromItemId: fromItemId,
              toItemId: toItemId,
              fromQuantity: fromQuantity,
              conversionFactor: conversionFactor,
              toCostPrice: _asDouble(body['toCostPrice']),
              toSellingPrice: _asDouble(body['toSellingPrice']),
              fromCostPrice: _asDouble(body['fromCostPrice']),
              storeId: _asInt(body['storeId']),
              notes: (body['notes'] ?? '').toString().trim().isEmpty
                  ? null
                  : (body['notes'] ?? '').toString().trim(),
            );
            return _sendJson(request, 200, {
              'message': 'Stock transfer saved',
              'transferId': transferId,
            });
          } catch (e) {
            return _sendJson(request, 400, {'message': '$e'});
          }
        }
        return _sendJson(request, 405, {'message': 'Method not allowed'});
      }
      if (request.method == 'GET' && request.uri.path == '/dashboard/analytics') {
        final userId = await _requireApprovedRemoteUserOrRespond(request);
        if (userId == null) return;
        final rangeRaw = (request.uri.queryParameters['range'] ?? 'today')
            .trim()
            .toLowerCase();
        final normalizedRange = switch (rangeRaw) {
          'week' || 'lastweek' => 'lastweek',
          'month' || 'lastmonth' => 'lastmonth',
          'all' => 'all',
          _ => 'today',
        };
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        final start = switch (normalizedRange) {
          'lastweek' => startOfToday.subtract(const Duration(days: 6)),
          'lastmonth' => DateTime(now.year, now.month - 1, now.day),
          'all' => DateTime(2000),
          _ => startOfToday,
        };
        final end = DateTime(
          now.year,
          now.month,
          now.day,
          23,
          59,
          59,
          999,
        );
        bool inRange(DateTime date) =>
            !date.isBefore(start) && !date.isAfter(end);

        final defaultStore = await LocalDbService.instance.getDefaultStore();
        final sales = await LocalDbService.instance.getAllSales();
        final filteredSales = normalizedRange == 'all'
            ? sales
            : sales.where((s) => inRange(s.createdAt)).toList();
        final salesTotal = filteredSales.fold<double>(
          0,
          (sum, s) => sum + s.totalAmount,
        );
        final salesCount = filteredSales.length;

        final expenses = await LocalDbService.instance.getExpenses();
        final filteredExpenses = normalizedRange == 'all'
            ? expenses
            : expenses.where((e) => inRange(e.createdAt)).toList();
        final expensesTotal = filteredExpenses.fold<double>(
          0,
          (sum, e) => sum + e.amount,
        );

        final stockReceipts = await LocalDbService.instance
            .getStockReceiptsWithDetails();
        final receivesTotal = stockReceipts.fold<double>(0, (sum, row) {
          final receivedAt = DateTime.tryParse(
            (row['received_at'] as String?) ?? '',
          );
          if (receivedAt == null) return sum;
          if (normalizedRange != 'all' && !inRange(receivedAt)) return sum;
          return sum + ((row['total_cost'] as num?)?.toDouble() ?? 0);
        });

        final outstandingDebts =
            await LocalDbService.instance.getOutstandingDebtTotal();
        final reorderCount = await LocalDbService.instance.getReorderCount();

        return _sendJson(request, 200, {
          'range': normalizedRange,
          'data': {
            'store': defaultStore?.toMap(),
            'salesTotal': salesTotal,
            'salesCount': salesCount,
            'outstandingDebts': outstandingDebts,
            'expensesTotal': expensesTotal,
            'receivesTotal': receivesTotal,
            'reorderCount': reorderCount,
          },
        });
      }
      _sendJson(request, 404, {'message': 'Not found'});
    } catch (_) {
      _sendJson(request, 500, {'message': 'Server error'});
    }
  }

  int? _requireAuth(HttpRequest request) {
    final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    if (!auth.startsWith('Bearer ')) return null;
    final token = auth.replaceFirst('Bearer ', '').trim();
    return _sessionTokens[token];
  }

  bool _remoteUserIsVerifiedForLogin(Map<String, Object?> user) {
    return _remoteApprovedFlag(user) == 1 &&
        (user['role'] as String? ?? '').trim().isNotEmpty;
  }

  int _remoteApprovedFlag(Map<String, Object?> user) {
    final raw = user['approved'];
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  /// Returns remote user id, or `null` after sending 401 or 403 on [request].
  Future<int?> _requireApprovedRemoteUserOrRespond(HttpRequest request) async {
    final userId = _requireAuth(request);
    if (userId == null) {
      _sendJson(request, 401, {'message': 'Unauthorized'});
      return null;
    }
    final user = await LocalDbService.instance.getRemoteUserById(userId);
    if (user == null) {
      _sendJson(request, 401, {'message': 'Unauthorized'});
      return null;
    }
    if (!_remoteUserIsVerifiedForLogin(user)) {
      _sendJson(request, 403, {
        'message': _pendingRemoteUserLoginRejectedMessage,
        'code': 'PENDING_APPROVAL',
      });
      return null;
    }
    return userId;
  }

  Future<Map<String, dynamic>> _readBody(HttpRequest request) async {
    final raw = await utf8.decoder.bind(request).join();
    if (raw.trim().isEmpty) return <String, dynamic>{};
    return jsonDecode(raw) as Map<String, dynamic>;
  }

  void _sendJson(HttpRequest request, int status, Map<String, dynamic> body) {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    request.response.close();
  }

  String _generateToken() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final rand = Random.secure();
    return List.generate(32, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  bool _bodyHasKey(Map<dynamic, dynamic> body, String camel, String snake) =>
      body.containsKey(camel) || body.containsKey(snake);

  String? _readOptionalStringFromBody(Map<dynamic, dynamic> body, String camel, String snake) {
    final raw = body[camel] ?? body[snake];
    if (raw == null) return null;
    final trimmed = raw.toString().trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _resolveOptionalStringField(
    Map<dynamic, dynamic> body, {
    required String camel,
    required String snake,
    String? existing,
  }) {
    if (_bodyHasKey(body, camel, snake)) {
      return _readOptionalStringFromBody(body, camel, snake);
    }
    return existing;
  }

  List<String> _parseAcceptedBarcodesList(Map<String, dynamic> body) {
    final raw = body['accepted_barcodes'] ?? body['acceptedBarcodes'];
    if (raw is! List) return const [];
    return LocalDbService.instance.normalizeBarcodeList(
      raw.map((e) => e.toString()).where((s) => s.trim().isNotEmpty),
    );
  }

  Future<List<Map<String, dynamic>>> _itemsPayloadWithBarcodes(
    List<Item> rows,
  ) async {
    final aliasMap = await LocalDbService.instance.getItemBarcodesMap();
    return [
      for (final e in rows)
        {
          ...e.toMap(),
          'accepted_barcodes': e.id != null
              ? (aliasMap[e.id!] ?? const <String>[])
              : const <String>[],
        },
    ];
  }

  int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }

  double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().trim());
  }

  DateTime? _asDate(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString().trim());
  }

  String? _categoryTypeFromRequest(String? rawType) {
    final raw = (rawType ?? '').trim().toLowerCase();
    if (raw == 'sale' || raw == 'business') return raw;
    return null;
  }

  String _categoryMetaKey(String categoryType) {
    return categoryType == 'sale'
        ? _saleCategoriesMetaKey
        : _businessCategoriesMetaKey;
  }

  List<String> _parseCategoryValues(String? raw) {
    return (raw ?? '')
        .split('|')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<List<String>> _getItemCategoryList(String categoryType) async {
    final key = _categoryMetaKey(categoryType);
    final raw = await LocalDbService.instance.getAppMeta(key);
    return _parseCategoryValues(raw);
  }

  Future<void> _setItemCategoryList(
    String categoryType,
    List<String> values,
  ) async {
    final key = _categoryMetaKey(categoryType);
    final cleaned = values
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    await LocalDbService.instance.setAppMeta(key, cleaned.join('|'));
  }

  Future<List<Map<String, Object?>>> _getItemTransactions(int itemId) async {
    final receipts =
        await LocalDbService.instance.getStockReceiptsForItemWithDetails(itemId);
    final sales = await LocalDbService.instance.getSaleRowsForItem(itemId);
    final transfers = await LocalDbService.instance.getTransferRowsForItem(itemId);

    final rows = <Map<String, Object?>>[];

    for (final row in receipts) {
      final receivedAt = (row['received_at'] ?? '').toString();
      final brand = (row['brand'] ?? '').toString().trim();
      final isAdjustment = brand.startsWith('ADJ|');
      final qty = (row['quantity'] as num?)?.toDouble() ?? 0;
      rows.add({
        'type': isAdjustment ? 'adjustment' : 'receive',
        'date': receivedAt,
        'reference': row['id'],
        'quantity': qty,
        'itemId': itemId,
        'itemName': row['item_name'],
        'storeId': row['store_id'],
        'storeName': row['store_name'],
        'unitCost': (row['unit_cost'] as num?)?.toDouble(),
        'totalCost': (row['total_cost'] as num?)?.toDouble(),
        'raw': row,
      });
    }

    for (final row in sales) {
      final soldAt = (row['sold_at'] ?? '').toString();
      rows.add({
        'type': 'sale',
        'date': soldAt,
        'reference': row['sale_id'],
        'quantity': (row['quantity'] as num?)?.toDouble() ?? 0,
        'itemId': itemId,
        'storeId': row['store_id'],
        'customerName': row['customer_name'],
        'unitPrice': (row['unit_price'] as num?)?.toDouble(),
        'lineTotal': (row['line_total'] as num?)?.toDouble(),
        'raw': row,
      });
    }

    for (final row in transfers) {
      final createdAt = (row['created_at'] ?? '').toString();
      final isFromItem = row['from_item_id'] == itemId;
      final fromQty = (row['from_quantity'] as num?)?.toDouble() ?? 0;
      if (isFromItem && fromQty <= 0) {
        continue;
      }
      rows.add({
        'type': isFromItem ? 'transfer_out' : 'transfer_in',
        'date': createdAt,
        'reference': row['id'],
        'quantity':
            ((isFromItem ? row['from_quantity'] : row['to_quantity']) as num?)
                    ?.toDouble() ??
                0,
        'itemId': itemId,
        'storeId': row['store_id'],
        'fromItemId': row['from_item_id'],
        'toItemId': row['to_item_id'],
        'fromItemName': row['from_item_name'],
        'toItemName': row['to_item_name'],
        'notes': row['notes'],
        'raw': row,
      });
    }

    rows.sort((a, b) {
      final left = DateTime.tryParse((a['date'] ?? '').toString());
      final right = DateTime.tryParse((b['date'] ?? '').toString());
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });

    return rows;
  }

  String get _resolvedMotherName {
    final raw = AppSettingsService.instance.shopName.trim();
    return raw.isEmpty ? 'Mother POS' : raw;
  }

  Future<void> _ensureMotherIdentity() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = (prefs.getString(_motherIdKey) ?? '').trim();
    if (existing.isNotEmpty) {
      _motherId = existing;
      return;
    }
    _motherId = _uuid.v4();
    await prefs.setString(_motherIdKey, _motherId);
  }

  Future<void> _startUdpDiscovery() async {
    try {
      _discoverySocket?.close();
      _discoverySocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
        reusePort: true,
      );
      _discoverySocket!.broadcastEnabled = true;
      _discoverySocket!.listen((event) {
        if (event != RawSocketEvent.read) return;
        final datagram = _discoverySocket!.receive();
        if (datagram == null) return;
        final message = utf8.decode(datagram.data, allowMalformed: true).trim();
        var shouldRespond = false;
        try {
          final decoded = jsonDecode(message);
          if (decoded is Map<String, dynamic>) {
            shouldRespond =
                (decoded['type'] ?? '').toString().trim() == _discoverType &&
                (decoded['token'] ?? '').toString().trim() == _discoveryToken;
          }
        } catch (_) {
          // Backward compatibility with legacy plain-text discovery ping.
          shouldRespond = message.contains(_discoveryMagic);
        }
        if (!shouldRespond) return;
        final response = _buildDiscoveryPayload();
        _discoverySocket!.send(
          utf8.encode(jsonEncode(response)),
          datagram.address,
          datagram.port,
        );
      });

      _beaconTimer?.cancel();
      _beaconTimer = Timer.periodic(const Duration(seconds: 4), (_) {
        final payload = utf8.encode(jsonEncode(_buildDiscoveryPayload()));
        _discoverySocket?.send(
          payload,
          InternetAddress('255.255.255.255'),
          _discoveryPort,
        );
      });
    } catch (_) {
      // Discovery is best-effort; API server should still run if UDP fails.
    }
  }

  void _startNetworkRefreshWatcher() {
    _networkRefreshTimer?.cancel();
    _networkRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) async {
      final latestIp = await _detectPrimaryLanIp();
      if (latestIp == _primaryLanIp) return;
      _primaryLanIp = latestIp;
    });
  }

  Map<String, Object?> _buildDiscoveryPayload() {
    return {
      'type': _helloType,
      'token': _discoveryToken,
      'baseUrl': 'http://$_primaryLanIp:$_port',
      'motherId': _motherId,
      'name': _resolvedMotherName,
      'apiVersion': _apiVersion,
      'port': _port,
    };
  }

  Future<String> _detectPrimaryLanIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address.trim();
          if (ip.isNotEmpty) return ip;
        }
      }
    } catch (_) {}
    return '127.0.0.1';
  }

}
