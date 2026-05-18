import 'dart:convert';
import 'package:http/http.dart' as http;
import 'env.dart';

class DBResult {
  final bool success;
  final String message;
  final Map<String, dynamic>? data;

  const DBResult({
    required this.success,
    required this.message,
    this.data,
  });
}

class DBService {
  DBService._();
  static final DBService instance = DBService._();

  // ── Shared helpers ─────────────────────────────────────────────────────

  Future<DBResult> _post(String url, Map<String, dynamic> body) async {
    try {
      final response = await http
          .post(Uri.parse(url),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(
          success: false,
          message: 'Server returned unexpected response '
              '(HTTP ${response.statusCode}). '
              'Check that the PHP file exists and Apache is running.',
        );
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } on http.ClientException catch (e) {
      return DBResult(success: false, message: 'Cannot reach server. Is XAMPP running? (${e.message})');
    } on FormatException {
      return DBResult(success: false, message: 'Server returned invalid data. Check PHP error logs.');
    } catch (e) {
      return DBResult(success: false, message: 'Error: $e');
    }
  }

  Future<DBResult> _request(String method, String url, Map<String, dynamic> body) async {
    try {
      final request = http.Request(method, Uri.parse(url))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(body);
      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);

      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(success: false, message: 'Server error (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } on http.ClientException catch (e) {
      return DBResult(success: false, message: 'Network error: ${e.message}');
    } on FormatException {
      return DBResult(success: false, message: 'Invalid server response.');
    } catch (e) {
      return DBResult(success: false, message: 'Error: $e');
    }
  }

  // ── LOGIN ──────────────────────────────────────────────────────────────
  Future<DBResult> login({
    required String username,
    required String password,
  }) async {
    final result = await _post(
      ENV.LOGIN_URL,
      {
        'username': username,
        'password': password,
      },
    );

    if (!result.success) return result;

    final data = result.data ?? {};

    final userData = data['user'] is Map
        ? Map<String, dynamic>.from(data['user'])
        : Map<String, dynamic>.from(data);

    userData.remove('success');
    userData.remove('message');

    return DBResult(
      success: true,
      message: data['message'] ?? 'Login successful',
      data: userData,
    );
  }

  // ── DASHBOARD ──────────────────────────────────────────────────────────

  Future<DBResult> fetchDashboard() async {
    try {
      final response = await http
          .get(Uri.parse(ENV.DASHBOARD_URL))
          .timeout(const Duration(seconds: 30));
      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(success: false, message: 'Dashboard: unexpected server response (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(success: decoded['success'] == true, message: decoded['message'] ?? '', data: decoded);
    } on http.ClientException catch (e) {
      return DBResult(success: false, message: 'Cannot reach dashboard. (${e.message})');
    } on FormatException {
      return DBResult(success: false, message: 'Dashboard returned invalid data.');
    } catch (e) {
      return DBResult(success: false, message: 'Dashboard error: $e');
    }
  }

  // ── USER MANAGEMENT ────────────────────────────────────────────────────

  /// Fetch all users, roles, and modules
  Future<DBResult> fetchUsers() async {
    try {
      final response = await http
          .get(Uri.parse(ENV.USERS_URL))
          .timeout(const Duration(seconds: 30));
      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(success: false, message: 'Users: unexpected response (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(success: decoded['success'] == true, message: decoded['message'] ?? '', data: decoded);
    } catch (e) {
      return DBResult(success: false, message: 'Fetch users error: $e');
    }
  }

  /// Create a new user
  /// permissions = [{'module_id': int, 'can_access': bool}, ...]
  // Add warehouseId to your existing DBService createUser and updateUser methods.
// Keep your ENV.USERS_URL / _request names the same as your project.

  Future<DBResult> createUser({
    required String username,
    required String password,
    required String fullName,
    String? email,
    int? storeId,
    int? warehouseId,
    required int roleId,
    required List<Map<String, dynamic>> permissions,
    int performedBy = 0,
  }) =>
      _request('POST', ENV.USERS_URL, {
        'username': username,
        'password': password,
        'full_name': fullName,
        'email': email ?? '',
        'role_id': roleId,
        'store_id': storeId,
        'warehouse_id': warehouseId,
        'assigned_store_ids': storeId == null ? [] : [storeId],
        'assigned_warehouse_ids': warehouseId == null ? [] : [warehouseId],
        'permissions': permissions,
        'performed_by': performedBy,
      });

  Future<DBResult> updateUser({
    required int userId,
    required String fullName,
    String? email,
    int? roleId,
    int? storeId,
    int? warehouseId,
    required List<Map<String, dynamic>> permissions,
    int performedBy = 0,
  }) =>
      _request('PUT', ENV.USERS_URL, {
        'user_id': userId,
        'full_name': fullName,
        'email': email ?? '',
        'role_id': roleId,
        'store_id': storeId,
        'warehouse_id': warehouseId,
        'assigned_store_ids': storeId == null ? [] : [storeId],
        'assigned_warehouse_ids': warehouseId == null ? [] : [warehouseId],
        'permissions': permissions,
        'performed_by': performedBy,
      });


  /// Activate or deactivate a user
  Future<DBResult> toggleUserActive({
    required int userId,
    required bool isActive,
    int performedBy = 0,
  }) =>
      _request('PATCH', ENV.USERS_URL, {
        'user_id': userId,
        'is_active': isActive,
        'performed_by': performedBy,
      });

  /// Delete a user
  Future<DBResult> deleteUser({required int userId, int performedBy = 0}) =>
      _request('DELETE', ENV.USERS_URL, {'user_id': userId, 'performed_by': performedBy});

  Future<DBResult> fetchProducts({String search = ''}) async {
    try {
      final params = <String, String>{};
      if (search.isNotEmpty) params['search'] = search;

      final uri = Uri.parse(ENV.PRODUCTS_URL).replace(queryParameters: params.isEmpty ? null : params);
      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(
          success: false,
          message: 'Products: unexpected server response (HTTP ${response.statusCode}).',
        );
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data:    decoded,
      );
    } on http.ClientException catch (e) {
      return DBResult(success: false, message: 'Cannot reach products API. (${e.message})');
    } on FormatException {
      return DBResult(success: false, message: 'Products returned invalid data.');
    } catch (e) {
      return DBResult(success: false, message: 'Products error: $e');
    }
  }

  Future<DBResult> createProduct({
    required String productCode,
    required String description,
    required double unitPrice,
    required String uom,
    int performedBy = 0,
  }) =>
      _post(ENV.PRODUCTS_URL, {
        'product_code': productCode,
        'item_description': description,
        'unit_price': unitPrice,
        'uom': uom,
        'performed_by': performedBy,
      });

  /// Update an existing product
  Future<DBResult> updateProduct({
    required String productCode,
    String? newProductCode,
    String? description,
    double? unitPrice,
    String? uom,
    int performedBy = 0,
  }) =>
      _request('PUT', ENV.PRODUCTS_URL, {
        'product_code': productCode,
        if (newProductCode != null)
          'new_product_code': newProductCode,
        if (description != null)
          'item_description': description,
        if (unitPrice != null)
          'unit_price': unitPrice,
        if (uom != null)
          'uom': uom,
        'performed_by': performedBy,
      });

  /// Delete a product (server will reject if stock records exist)
  Future<DBResult> deleteProduct({
    required String productCode,
    int performedBy = 0,
  }) =>
      _request('DELETE', ENV.PRODUCTS_URL, {
        'product_code': productCode,
        'performed_by': performedBy,
      });



  /// Fetch product units / UOM for one product.
  Future<DBResult> fetchProductUnits({
    required String productCode,
  }) async {
    try {
      final uri = Uri.parse(ENV.PRODUCT_UNITS_URL).replace(queryParameters: {
        'product_code': productCode,
      });

      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(
          success: false,
          message: 'Product units: unexpected server response (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } on http.ClientException catch (e) {
      return DBResult(success: false, message: 'Cannot reach product units API. (${e.message})');
    } on FormatException {
      return DBResult(success: false, message: 'Product units returned invalid data.');
    } catch (e) {
      return DBResult(success: false, message: 'Product units error: $e');
    }
  }

  /// Save all product units / UOM for one product.
  /// Inventory remains stored as PCS.
  Future<DBResult> saveProductUnits({
    required String productCode,
    required List<Map<String, dynamic>> units,
    int performedBy = 0,
  }) =>
      _post(ENV.PRODUCT_UNITS_URL, {
        'product_code': productCode,
        'units': units,
        'performed_by': performedBy,
      });

  // ── INVENTORY ──────────────────────────────────────────────────────────────

  /// Fetch warehouse + store inventory in one call
  Future<DBResult> fetchInventory({String view = 'both'}) async {
    try {
      final uri = Uri.parse(ENV.INVENTORY_URL).replace(queryParameters: {'view': view});
      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(success: false,
            message: 'Inventory: unexpected response (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data:    decoded,
      );
    } on http.ClientException catch (e) {
      return DBResult(success: false, message: 'Cannot reach inventory API. (${e.message})');
    } on FormatException {
      return DBResult(success: false, message: 'Inventory returned invalid data.');
    } catch (e) {
      return DBResult(success: false, message: 'Inventory error: $e');
    }
  }




  /// Add (or upsert) a stock entry.
  /// [target] = 'warehouse' or 'store'
  Future<DBResult> addInventoryEntry({
    required String target,
    required String productCode,
    required int quantity,
    String uom = 'PCS',
    double? unitPrice,
    int? warehouseId,
    int? storeId,
    int performedBy = 0,
  }) =>
      _request('POST', ENV.INVENTORY_URL, {
        'target': target,
        'product_code': productCode,
        'quantity': quantity,
        'uom': uom,
        if (unitPrice != null) 'unit_price': unitPrice,
        if (warehouseId != null) 'warehouse_id': warehouseId,
        if (storeId != null) 'store_id': storeId,
        'performed_by': performedBy,
      });
  /// Update quantity / price of an existing stock entry.
  Future<DBResult> updateInventoryEntry({
    required String target,
    required String productCode,
    required int quantity,
    String uom = 'PCS',
    double? unitPrice,
    int? warehouseId,
    int? storeId,
    int performedBy = 0,
  }) =>
      _request('PUT', ENV.INVENTORY_URL, {
        'target': target,
        'product_code': productCode,
        'quantity': quantity,
        'uom': uom,
        if (unitPrice != null) 'unit_price': unitPrice,
        if (warehouseId != null) 'warehouse_id': warehouseId,
        if (storeId != null) 'store_id': storeId,
        'performed_by': performedBy,
      });

  /// Remove a stock entry from warehouse or store.
  Future<DBResult> deleteInventoryEntry({
    required String target,
    required String productCode,
    int? warehouseId,
    int? storeId,
    int  performedBy = 0,
  }) =>
      _request('DELETE', ENV.INVENTORY_URL, {
        'target':       target,
        'product_code': productCode,
        if (warehouseId != null) 'warehouse_id': warehouseId,
        if (storeId     != null) 'store_id':     storeId,
        'performed_by': performedBy,
      });

  // REFUND

  Future<DBResult> refundLookup({required String transactionNo}) async {
    try {
      final uri = Uri.parse(ENV.REFUND_LOOKUP_URL).replace(
        queryParameters: {'transaction_no': transactionNo},
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      final ct = response.headers['content-type'] ?? '';

      if (!ct.contains('application/json')) {
        return DBResult(
          success: false,
          message: 'Refund lookup: unexpected server response (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } on http.ClientException catch (e) {
      return DBResult(success: false, message: 'Cannot reach refund lookup API. (${e.message})');
    } on FormatException {
      return DBResult(success: false, message: 'Refund lookup returned invalid data.');
    } catch (e) {
      return DBResult(success: false, message: 'Refund lookup error: $e');
    }
  }

  Future<DBResult> processRefund({
    required int transactionId,
    required int userId,
    required String reason,
    required List<Map<String, dynamic>> items,
  }) =>
      _post(ENV.REFUND_PROCESS_URL, {
        'transaction_id': transactionId,
        'user_id': userId,
        'reason': reason,
        'items': items,
      });


  // ── SUPPLIERS ────────────────────────────────────────────────────────────

  Future<DBResult> fetchSuppliers({String search = ''}) async {
    try {
      final params = <String, String>{};
      if (search.isNotEmpty) params['search'] = search;

      final uri = Uri.parse(ENV.SUPPLIERS_URL)
          .replace(queryParameters: params.isEmpty ? null : params);

      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(
          success: false,
          message: 'Suppliers: unexpected server response (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } catch (e) {
      return DBResult(success: false, message: 'Suppliers error: $e');
    }
  }

  Future<DBResult> createSupplier({
    required String supplierCode,
    required String supplierName,
    String? contactPerson,
    String? contactNumber,
    String? email,
    String? address,
    String status = 'ACTIVE',
    int performedBy = 0,
  }) =>
      _post(ENV.SUPPLIERS_URL, {
        'supplier_code': supplierCode,
        'supplier_name': supplierName,
        'contact_person': contactPerson ?? '',
        'contact_number': contactNumber ?? '',
        'email': email ?? '',
        'address': address ?? '',
        'status': status,
        'performed_by': performedBy,
      });

  Future<DBResult> updateSupplier({
    required dynamic supplierId,
    required String supplierCode,
    required String supplierName,
    String? contactPerson,
    String? contactNumber,
    String? email,
    String? address,
    String status = 'ACTIVE',
    int performedBy = 0,
  }) =>
      _request('PUT', ENV.SUPPLIERS_URL, {
        'supplier_id': supplierId,
        'supplier_code': supplierCode,
        'supplier_name': supplierName,
        'contact_person': contactPerson ?? '',
        'contact_number': contactNumber ?? '',
        'email': email ?? '',
        'address': address ?? '',
        'status': status,
        'performed_by': performedBy,
      });

  Future<DBResult> deleteSupplier({
    required dynamic supplierId,
    int performedBy = 0,
  }) =>
      _request('DELETE', ENV.SUPPLIERS_URL, {
        'supplier_id': supplierId,
        'performed_by': performedBy,
      });

  // ── DELIVERIES ───────────────────────────────────────────────────────────

  Future<DBResult> fetchDeliveries({
    String search = '',
    String dateFrom = '',
    String dateTo = '',
    String status = '',
    int warehouseId = 0,
    int supplierId = 0,
    int page = 1,
    int limit = 20,
    String supplierSearch = '',
  }) async {
    try {
      final params = <String, String>{
        'view': 'list',
        'page': '$page',
        'limit': '$limit',
      };

      if (search.isNotEmpty) params['search'] = search;
      if (dateFrom.isNotEmpty) params['date_from'] = dateFrom;
      if (dateTo.isNotEmpty) params['date_to'] = dateTo;
      if (status.isNotEmpty) params['status'] = status;
      if (warehouseId > 0) params['warehouse_id'] = '$warehouseId';
      if (supplierId > 0) params['supplier_id'] = '$supplierId';
      if (supplierSearch.isNotEmpty) {
        params['supplier_search'] = supplierSearch;
      }

      final uri = Uri.parse(ENV.DELIVERIES_URL).replace(queryParameters: params);

      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(
          success: false,
          message: 'Deliveries: unexpected server response (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } catch (e) {
      return DBResult(success: false, message: 'Deliveries error: $e');
    }
  }

  Future<DBResult> fetchDeliveryDetails({
    required int deliveryId,
  }) async {
    try {
      final uri = Uri.parse(ENV.DELIVERIES_URL).replace(
        queryParameters: {
          'view': 'detail',
          'delivery_id': '$deliveryId',
        },
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(
          success: false,
          message: 'Delivery details: unexpected server response (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } catch (e) {
      return DBResult(success: false, message: 'Delivery detail error: $e');
    }
  }

  Future<DBResult> fetchStoresWarehouses() async {
    try {
      final response = await http
          .get(Uri.parse(ENV.STORES_WAREHOUSES_URL))
          .timeout(const Duration(seconds: 30));

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;

      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } catch (e) {
      return DBResult(success: false, message: 'Error: $e');
    }
  }

  Future<DBResult> saveLocation({
    required String type,
    required String name,
    required String address,
    int? id,
  }) {
    final body = {
      'type': type,
      'name': name,
      'address': address,
      if (id != null) 'id': id,
    };

    return id == null
        ? _request('POST', ENV.STORES_WAREHOUSES_URL, body)
        : _request('PUT', ENV.STORES_WAREHOUSES_URL, body);
  }

  Future<DBResult> deleteLocation({
    required String type,
    required int id,
  }) {
    return _request('DELETE', ENV.STORES_WAREHOUSES_URL, {
      'type': type,
      'id': id,
    });
  }

  // ── PROMO MANAGEMENT ─────────────────────────────────────────────────────

  Future<DBResult> fetchPromos({
    String search = '',
    String status = '',
    int supplierId = 0,
    int storeId = 0,
    String dateFrom = '',
    String dateTo = '',
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final params = <String, String>{
        'action': 'list',
        'page': '$page',
        'limit': '$limit',
      };
      if (search.isNotEmpty) params['search'] = search;
      if (status.isNotEmpty && status != 'ALL') params['status'] = status;
      if (supplierId > 0) params['supplier_id'] = '$supplierId';
      if (storeId > 0) params['store_id'] = '$storeId';
      if (dateFrom.isNotEmpty) params['date_from'] = dateFrom;
      if (dateTo.isNotEmpty) params['date_to'] = dateTo;

      final uri = Uri.parse(ENV.PROMOS_URL).replace(queryParameters: params);
      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(success: false, message: 'Promos: unexpected server response (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(success: decoded['success'] == true, message: decoded['message'] ?? '', data: decoded);
    } catch (e) {
      return DBResult(success: false, message: 'Promos error: $e');
    }
  }

  Future<DBResult> fetchPromoRefs() async {
    try {
      final uri = Uri.parse(ENV.PROMOS_URL).replace(queryParameters: {'action': 'refs'});
      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(success: false, message: 'Promo references: unexpected server response (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(success: decoded['success'] == true, message: decoded['message'] ?? '', data: decoded);
    } catch (e) {
      return DBResult(success: false, message: 'Promo references error: $e');
    }
  }


  Future<DBResult> fetchPromoDetail({required int promoId}) async {
    try {
      final uri = Uri.parse(ENV.PROMOS_URL).replace(queryParameters: {
        'action': 'detail',
        'promo_id': '$promoId',
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(success: false, message: 'Promo detail: unexpected server response (HTTP ${response.statusCode}).');
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(success: decoded['success'] == true, message: decoded['message'] ?? '', data: decoded);
    } catch (e) {
      return DBResult(success: false, message: 'Promo detail error: $e');
    }
  }


// ── REPLACE this existing method ─────────────────────────────────────
  Future<DBResult> searchPromoProducts({
    String search = '',
    int limit = 30,
    int deliveryId = 0, // NEW: when > 0, only return products in that delivery
  }) async {
    try {
      final params = <String, String>{
        'action': 'products',
        'search': search,
        'limit': '$limit',
      };
      if (deliveryId > 0) params['delivery_id'] = '$deliveryId';

      final uri = Uri.parse(ENV.PROMOS_URL).replace(queryParameters: params);
      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(
          success: false,
          message: 'Promo products: unexpected server response (HTTP ${response.statusCode}).',
        );
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } catch (e) {
      return DBResult(success: false, message: 'Promo product search error: $e');
    }
  }

// ── ADD this new method ──────────────────────────────────────────────
  Future<DBResult> fetchPromoDeliveries({
    int supplierId = 0,
    int limit = 50,
  }) async {
    try {
      final params = <String, String>{
        'action': 'deliveries',
        'limit': '$limit',
      };
      if (supplierId > 0) params['supplier_id'] = '$supplierId';

      final uri = Uri.parse(ENV.PROMOS_URL).replace(queryParameters: params);
      final response = await http.get(uri).timeout(const Duration(seconds: 30));
      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(
          success: false,
          message: 'Promo deliveries: unexpected server response (HTTP ${response.statusCode}).',
        );
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } catch (e) {
      return DBResult(success: false, message: 'Promo deliveries error: $e');
    }
  }
  Future<DBResult> createPromo(Map<String, dynamic> promo) => _post(ENV.PROMOS_URL, promo);

  Future<DBResult> updatePromo(Map<String, dynamic> promo) => _request('PUT', ENV.PROMOS_URL, promo);

  Future<DBResult> cancelPromo({required int promoId, int userId = 0}) =>
      _request('DELETE', ENV.PROMOS_URL, {'promo_id': promoId, 'user_id': userId});

  // ── PENDING ITEMS ───────────────────────────────────────────────────────

  Future<DBResult> fetchPendingItems() async {
    try {
      final uri = Uri.parse(ENV.PENDING_ITEMS_URL).replace(
        queryParameters: {'action': 'fetch'},
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(
          success: false,
          message: 'Pending items: unexpected server response (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } on http.ClientException catch (e) {
      return DBResult(success: false, message: 'Cannot reach pending items API. (${e.message})');
    } on FormatException {
      return DBResult(success: false, message: 'Pending items returned invalid data.');
    } catch (e) {
      return DBResult(success: false, message: 'Pending items error: $e');
    }
  }

  Future<DBResult> generatePendingCode() async {
    try {
      final uri = Uri.parse(ENV.PENDING_ITEMS_URL).replace(
        queryParameters: {'action': 'generate_code'},
      );

      final response = await http.get(uri).timeout(const Duration(seconds: 30));

      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(
          success: false,
          message: 'Code generation: unexpected server response (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } catch (e) {
      return DBResult(success: false, message: 'Code generation error: $e');
    }
  }

  Future<DBResult> assignPendingItem({
    required int pendingId,
    required String productCode,
  }) async {
    try {
      // pending_items.php expects form-encoded POST, not JSON
      final response = await http.post(
        Uri.parse(ENV.PENDING_ITEMS_URL),
        body: {
          'action': 'assign',
          'pending_id': pendingId.toString(),
          'product_code': productCode,
        },
      ).timeout(const Duration(seconds: 30));

      final ct = response.headers['content-type'] ?? '';
      if (!ct.contains('application/json')) {
        return DBResult(
          success: false,
          message: 'Assign pending: unexpected server response (HTTP ${response.statusCode}).',
        );
      }

      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      return DBResult(
        success: decoded['success'] == true,
        message: decoded['message'] ?? '',
        data: decoded,
      );
    } catch (e) {
      return DBResult(success: false, message: 'Assign pending error: $e');
    }
  }
}

