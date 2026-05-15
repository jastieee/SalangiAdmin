import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'dart:convert';
import '../db/DBResult.dart';
import '../Utils/app_theme.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../DB/env.dart';

// ── Palette ───────────────────────────────────────────────────────────────
AppTheme get _t => themeNotifier.theme;
Color get _bg => _t.bg;
Color get _surface => _t.surface;
Color get _border => _t.border;
Color get _blue => _t.blue;
Color get _green => _t.green;
Color get _amber => _t.amber;
Color get _red => _t.red;
Color get _teal => _t.teal;
Color get _textHi => _t.textHi;
Color get _textLo => _t.textLo;

// ── Shared safe parsers ───────────────────────────────────────────────────
int toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

double toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

String toStr(dynamic v) => v?.toString() ?? '';

class InventoryScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;
  const InventoryScreen({super.key, this.currentUser});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _warehouse = [];
  List<Map<String, dynamic>> _store = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _stores = [];

  String _searchWarehouse = '';
  String _searchStore = '';


  int? _selectedWarehouseId;
  int? _selectedStoreId;

  int _warehousePage = 1;
  int _storePage = 1;

  int _warehouseItemsPerPage = 10;
  int _storeItemsPerPage = 10;

  final List<int> _pageSizeOptions = [10, 20, 50, 100];

  bool get _isWindows {
    try {
      return !kIsWeb && Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  int get _currentUserId => toInt(widget.currentUser?['user_id']);

  // ── Permissions ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _permissions {
    final rawAdmin = widget.currentUser?['admin_modules'];
    final rawAll = widget.currentUser?['permissions'];
    final raw = rawAdmin is List ? rawAdmin : rawAll;

    return (raw as List?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ??
        [];
  }

  bool hasPermission(String moduleName) {
    return _permissions.any((p) {
      final name = p['module_name']?.toString().trim().toUpperCase() ?? '';
      final canAccess =
          p['can_access'] == true ||
              p['can_access'] == 1 ||
              p['can_access'].toString() == '1';

      return name == moduleName.trim().toUpperCase() && canAccess;
    });
  }

  bool get canViewInventory =>
      hasPermission('INVENTORY_VIEW') ;

  bool get canAddWarehouseStock =>
      hasPermission('WAREHOUSE_STOCK_ADD');

  bool get canImportWarehouseStock =>
      hasPermission('WAREHOUSE_STOCK_IMPORT');

  bool get canEditWarehouseStock =>
      hasPermission('WAREHOUSE_STOCK_EDIT');

  bool get canDeleteWarehouseStock =>
      hasPermission('WAREHOUSE_STOCK_DELETE');

  bool get canAddStoreStock =>
      hasPermission('STORE_STOCK_ADD');

  bool get canImportStoreStock =>
      hasPermission('STORE_STOCK_IMPORT');

  bool get canEditStoreStock =>
      hasPermission('STORE_STOCK_EDIT');

  bool get canDeleteStoreStock =>
      hasPermission('STORE_STOCK_DELETE');


  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!canViewInventory) {
      setState(() {
        _loading = false;
        _error = 'You do not have permission to view inventory.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await DBService.instance.fetchInventory();
    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result.success) {
        _warehouse = _toList(result.data?['warehouse']);
        _store = _toList(result.data?['store']);
        _warehouses = _toList(result.data?['warehouses']);
        _stores = _toList(result.data?['stores']);

        _warehousePage = 1;
        _storePage = 1;
      } else {
        _error = result.message;
      }
    });
  }

  List<Map<String, dynamic>> _toList(dynamic v) =>
      (v as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
          [];

  // ── Filtered ────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredWarehouse => _warehouse.where((r) {
    final q = _searchWarehouse.toLowerCase();

    if (_selectedWarehouseId != null &&
        toInt(r['warehouse_id']) != _selectedWarehouseId) {
      return false;
    }

    return q.isEmpty ||
        toStr(r['product_code']).toLowerCase().contains(q) ||
        toStr(r['item_description']).toLowerCase().contains(q);
  }).toList();

  List<Map<String, dynamic>> get _filteredStore => _store.where((r) {
    final q = _searchStore.toLowerCase();

    if (_selectedStoreId != null &&
        toInt(r['store_id']) != _selectedStoreId) {
      return false;
    }

    return q.isEmpty ||
        toStr(r['product_code']).toLowerCase().contains(q) ||
        cleanItemName(r['item_description']).toLowerCase().contains(q);
  }).toList();

  // ── Pagination ──────────────────────────────────────────────────────────
  int get _warehouseTotalPages {
    final total = _filteredWarehouse.length;
    if (total == 0) return 1;
    return (total / _warehouseItemsPerPage).ceil();
  }

  int get _storeTotalPages {
    final total = _filteredStore.length;
    if (total == 0) return 1;
    return (total / _storeItemsPerPage).ceil();
  }

  List<Map<String, dynamic>> get _pagedWarehouse {
    final list = _filteredWarehouse;
    final start = (_warehousePage - 1) * _warehouseItemsPerPage;
    if (start >= list.length) return [];
    final end = (start + _warehouseItemsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  List<Map<String, dynamic>> get _pagedStore {
    final list = _filteredStore;
    final start = (_storePage - 1) * _storeItemsPerPage;
    if (start >= list.length) return [];
    final end = (start + _storeItemsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  List<dynamic> _visiblePageItems({
    required int currentPage,
    required int totalPages,
  }) {
    if (totalPages <= 7) {
      return List<int>.generate(totalPages, (i) => i + 1);
    }

    final items = <dynamic>[1];

    if (currentPage > 3) {
      items.add('...');
    }

    final start = currentPage <= 3 ? 2 : currentPage - 1;
    final end = currentPage >= totalPages - 2 ? totalPages - 1 : currentPage + 1;

    for (int i = start; i <= end; i++) {
      if (i > 1 && i < totalPages) items.add(i);
    }

    if (currentPage < totalPages - 2) {
      items.add('...');
    }

    items.add(totalPages);
    return items;
  }

  void _goToWarehousePage(int page) {
    final safe = page.clamp(1, _warehouseTotalPages);
    setState(() => _warehousePage = safe);
  }

  void _goToStorePage(int page) {
    final safe = page.clamp(1, _storeTotalPages);
    setState(() => _storePage = safe);
  }

  // ── Snack ───────────────────────────────────────────────────────────────
  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? _red : _green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Open add/edit dialog ────────────────────────────────────────────────
  Future<void> _openForm({
    required String target,
    Map<String, dynamic>? existing,
  }) async {
    final isWarehouse = target == 'warehouse';

    if (existing == null) {
      final allowed = isWarehouse
          ? canAddWarehouseStock
          : canAddStoreStock;

      if (!allowed) {
        _snack(
          'You do not have permission to add ${isWarehouse ? 'warehouse' : 'store'} stock.',
          error: true,
        );
        return;
      }
    }

    if (existing != null) {
      final allowed = isWarehouse
          ? canEditWarehouseStock
          : canEditStoreStock;

      if (!allowed) {
        _snack(
          'You do not have permission to edit ${isWarehouse ? 'warehouse' : 'store'} stock.',
          error: true,
        );
        return;
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StockFormDialog(
        target: target,
        existing: existing,
        warehouses: _warehouses,
        stores: _stores,
        currentUserId: _currentUserId,
      ),
    );

    if (ok == true) _load();
  }

// ── Delete ──────────────────────────────────────────────────────────────
  Future<void> _confirmDelete({
    required String target,
    required Map<String, dynamic> item,
  }) async {
    final isWarehouse = target == 'warehouse';

    final allowed = isWarehouse
        ? canDeleteWarehouseStock
        : canDeleteStoreStock;

    if (!allowed) {
      _snack(
        'You do not have permission to delete ${isWarehouse ? 'warehouse' : 'store'} stock.',
        error: true,
      );
      return;
    }

    final code = toStr(item['product_code']);
    final desc = cleanItemName(
      toStr(item['item_description']),
    );

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Remove Stock Entry',
        message:
        'Remove "$desc" ($code) from ${isWarehouse ? 'warehouse' : 'store'} inventory?',
        confirmLabel: 'Remove',
        confirmColor: _red,
      ),
    );

    if (ok != true || !mounted) return;

    final result = await DBService.instance.deleteInventoryEntry(
      target: target,
      productCode: code,
      warehouseId: item['warehouse_id'] == null ? null : toInt(item['warehouse_id']),
      storeId: item['store_id'] == null ? null : toInt(item['store_id']),
      performedBy: _currentUserId,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        if (isWarehouse) {
          _warehouse.removeWhere((r) =>
          toStr(r['product_code']) == code &&
              toInt(r['warehouse_id']) == toInt(item['warehouse_id']));

          if (_warehousePage > _warehouseTotalPages) {
            _warehousePage = _warehouseTotalPages;
          }
        } else {
          _store.removeWhere((r) =>
          toStr(r['product_code']) == code &&
              toInt(r['store_id']) == toInt(item['store_id']));

          if (_storePage > _storeTotalPages) {
            _storePage = _storeTotalPages;
          }
        }
      });

      _snack('Stock entry removed');
    } else {
      _snack(result.message, error: true);
    }
  }

  Future<void> _importWarehouseInventory() async {
    if (!canImportWarehouseStock) {
      _snack('You do not have permission to import warehouse stock.', error: true);
      return;
    }

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ENV.IMPORT_WAREHOUSE_INVENTORY_URL),
      );

      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) {
          _snack('Unable to read file.', error: true);
          return;
        }

        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: file.name,
          ),
        );
      } else {
        final path = file.path;
        if (path == null || path.isEmpty) {
          _snack('Invalid file path.', error: true);
          return;
        }

        request.files.add(await http.MultipartFile.fromPath('file', path));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (!mounted) return;

      final data = _decodeImportResponse(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final inserted = toInt(data['inserted']);
        final updated = toInt(data['updated']);
        final skipped = toInt(data['skipped']);
        final errors = (data['errors'] as List?) ?? [];

        _snack(
          'Warehouse import done: $inserted inserted, $updated updated, $skipped skipped.',
        );

        await _load();

        if (errors.isNotEmpty && mounted) {
          _showImportErrors('Warehouse Import Result', errors);
        }
      } else {
        _snack(data['message']?.toString() ?? 'Warehouse import failed.', error: true);
      }
    } catch (e) {
      _snack('Import failed: $e', error: true);
    }
  }

  Future<void> _importStoreInventory() async {
    if (!canImportStoreStock) {
      _snack('You do not have permission to import store stock.', error: true);
      return;
    }

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        withData: kIsWeb,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ENV.IMPORT_STORE_INVENTORY_URL),
      );

      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) {
          _snack('Unable to read file.', error: true);
          return;
        }

        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: file.name,
          ),
        );
      } else {
        final path = file.path;
        if (path == null || path.isEmpty) {
          _snack('Invalid file path.', error: true);
          return;
        }

        request.files.add(await http.MultipartFile.fromPath('file', path));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);

      if (!mounted) return;

      final data = _decodeImportResponse(response.body);

      if (response.statusCode == 200 && data['success'] == true) {
        final inserted = toInt(data['inserted']);
        final updated = toInt(data['updated']);
        final skipped = toInt(data['skipped']);
        final errors = (data['errors'] as List?) ?? [];

        _snack(
          'Store import done: $inserted inserted, $updated updated, $skipped skipped.',
        );

        await _load();

        if (errors.isNotEmpty && mounted) {
          _showImportErrors('Store Import Result', errors);
        }
      } else {
        _snack(data['message']?.toString() ?? 'Store import failed.', error: true);
      }
    } catch (e) {
      _snack('Import failed: $e', error: true);
    }
  }

  Map<String, dynamic> _decodeImportResponse(String body) {
    try {
      if (body.trim().isEmpty) return {};
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return {};
    } catch (_) {
      return {};
    }
  }

  void _showImportErrors(String title, List errors) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          title,
          style: TextStyle(
            color: _textHi,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Text(
              errors.map((e) => e.toString()).join('\n'),
              style: TextStyle(color: _textLo, fontSize: 13),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close', style: TextStyle(color: _blue)),
          ),
        ],
      ),
    );
  }

  // ── Build ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: _blue));
    }
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _buildHeader(),
          _buildTabBar(),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _WarehouseTab(
                  items: _pagedWarehouse,
                  allItems: _warehouse,
                  filteredCount: _filteredWarehouse.length,
                  currentPage: _warehousePage,
                  totalPages: _warehouseTotalPages,
                  itemsPerPage: _warehouseItemsPerPage,
                  pageSizeOptions: _pageSizeOptions,
                  visiblePages: _visiblePageItems(
                    currentPage: _warehousePage,
                    totalPages: _warehouseTotalPages,
                  ),
                  isWindows: _isWindows,
                  onSearch: (v) => setState(() {
                    _searchWarehouse = v;
                    _warehousePage = 1;
                  }),
                  onAdd: () => _openForm(target: 'warehouse'),
                  onEdit: (item) => _openForm(target: 'warehouse', existing: item),
                  onDelete: (item) => _confirmDelete(target: 'warehouse', item: item),
                  canImportWarehouseStock: canImportWarehouseStock,
                  onImportWarehouse: _importWarehouseInventory,
                  onRefresh: _load,
                  selectedWarehouseId: _selectedWarehouseId,
                  warehouses: _warehouses,
                  onWarehouseFilter: (id) => setState(() {
                    _selectedWarehouseId = id;
                    _warehousePage = 1;
                  }),
                  onItemsPerPageChanged: (value) => setState(() {
                    _warehouseItemsPerPage = value;
                    _warehousePage = 1;
                  }),
                  onPageTap: _goToWarehousePage,
                ),
                _StoreTab(
                  items: _pagedStore,
                  allItems: _store,
                  filteredCount: _filteredStore.length,
                  currentPage: _storePage,
                  totalPages: _storeTotalPages,
                  itemsPerPage: _storeItemsPerPage,
                  pageSizeOptions: _pageSizeOptions,
                  visiblePages: _visiblePageItems(
                    currentPage: _storePage,
                    totalPages: _storeTotalPages,
                  ),
                  isWindows: _isWindows,
                  onSearch: (v) => setState(() {
                    _searchStore = v;
                    _storePage = 1;
                  }),
                  onAdd: () => _openForm(target: 'store'),
                  onEdit: (item) => _openForm(target: 'store', existing: item),
                  onDelete: (item) => _confirmDelete(target: 'store', item: item),
                  canImportStoreStock: canImportStoreStock,
                  onImportStore: _importStoreInventory,
                  onRefresh: _load,
                  selectedStoreId: _selectedStoreId,
                  stores: _stores,
                  onStoreFilter: (id) => setState(() {
                    _selectedStoreId = id;
                    _storePage = 1;
                  }),
                  onItemsPerPageChanged: (value) => setState(() {
                    _storeItemsPerPage = value;
                    _storePage = 1;
                  }),
                  onPageTap: _goToStorePage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
    child: Row(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inventory',
              style: TextStyle(
                color: _textHi,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'Warehouse & store stock — products master required',
              style: TextStyle(color: _textLo, fontSize: 12),
            ),
          ],
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Refresh',
          icon: Icon(Icons.refresh_rounded, color: _textLo),
          onPressed: _load,
        ),
      ],
    ),
  );

  Widget _buildTabBar() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
    child: Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: TabBar(
        controller: _tabs,
        indicator: BoxDecoration(
          color: _blue.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _blue.withOpacity(0.4)),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: _blue,
        unselectedLabelColor: _textLo,
        labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        tabs: [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warehouse_rounded, size: 16),
                const SizedBox(width: 6),
                const Text('Warehouse'),
                const SizedBox(width: 6),
                _CountBadge(count: _warehouse.length, color: _teal),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.storefront_rounded, size: 16),
                const SizedBox(width: 6),
                const Text('Store'),
                const SizedBox(width: 6),
                _CountBadge(count: _store.length, color: _green),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// ───────────────────────────────────────────────────────────────────────────
// Filter Chip
// ───────────────────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color color;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.18) : _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? color.withOpacity(0.6) : _border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? color : _textLo,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    ),
  );
}

// ───────────────────────────────────────────────────────────────────────────
// Location Badge
// ───────────────────────────────────────────────────────────────────────────
class _LocationBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _LocationBadge({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withOpacity(0.08),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.25)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 11),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    ),
  );
}

// ───────────────────────────────────────────────────────────────────────────
// Warehouse Tab
// ───────────────────────────────────────────────────────────────────────────
class _WarehouseTab extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> allItems;
  final bool isWindows;
  final ValueChanged<String> onSearch;
  final RefreshCallback onAdd, onRefresh;
  final ValueChanged<Map<String, dynamic>> onEdit, onDelete;
  final bool canImportWarehouseStock;
  final VoidCallback onImportWarehouse;
  final int? selectedWarehouseId;
  final List<Map<String, dynamic>> warehouses;
  final ValueChanged<int?> onWarehouseFilter;

  final int filteredCount;
  final int currentPage;
  final int totalPages;
  final int itemsPerPage;
  final List<int> pageSizeOptions;
  final ValueChanged<int> onItemsPerPageChanged;
  final ValueChanged<int> onPageTap;
  final List<dynamic> visiblePages;

  const _WarehouseTab({
    required this.items,
    required this.allItems,
    required this.isWindows,
    required this.onSearch,
    required this.onAdd,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
    required this.canImportWarehouseStock,
    required this.onImportWarehouse,
    required this.onWarehouseFilter,
    required this.filteredCount,
    required this.currentPage,
    required this.totalPages,
    required this.itemsPerPage,
    required this.pageSizeOptions,
    required this.onItemsPerPageChanged,
    required this.onPageTap,
    required this.visiblePages,
    this.selectedWarehouseId,
    this.warehouses = const [],
  });

  int get _totalUnits =>
      allItems.fold(0, (s, r) => s + toInt(r['quantity']));
  int get _lowStock =>
      allItems.where((r) => toInt(r['quantity']) <= 10).length;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _blue,
      backgroundColor: _surface,
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildControls()),
          SliverToBoxAdapter(child: _buildStats()),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          isWindows ? _buildTable() : _buildCards(),
          SliverToBoxAdapter(child: _buildPagination()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildControls() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SearchBar(
                hint: 'Search warehouse stock…',
                onChanged: onSearch,
              ),
            ),
            const SizedBox(width: 12),
            Row(
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Stock'),
                ),
                const SizedBox(width: 8),
                if (canImportWarehouseStock)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _teal,
                      side: BorderSide(color: _teal.withOpacity(0.4)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onImportWarehouse,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Import'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          value: selectedWarehouseId,
          dropdownColor: _surface,
          style: TextStyle(color: _textHi, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.warehouse_rounded, color: _textLo, size: 18),
            hintText: 'All Warehouses',
            hintStyle: TextStyle(color: _textLo, fontSize: 13),
            filled: true,
            fillColor: _surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _teal, width: 1.5),
            ),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('All Warehouses')),
            ...warehouses.map(
                  (w) => DropdownMenuItem(
                value: toInt(w['warehouse_id']),
                child: Text(toStr(w['warehouse_name'])),
              ),
            ),
          ],
          onChanged: onWarehouseFilter,
        ),
      ],
    ),
  );

  Widget _buildStats() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MiniStat(label: 'SKUs', value: '${allItems.length}', color: _teal),
        _MiniStat(label: 'Total Units', value: '$_totalUnits', color: _blue),
        if (_lowStock > 0)
          _MiniStat(label: 'Low Stock', value: '$_lowStock', color: _red),
      ],
    ),
  );

  Widget _buildTable() => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: const [
                  Expanded(flex: 2, child: _TH('CODE')),
                  Expanded(flex: 5, child: _TH('DESCRIPTION')),
                  Expanded(flex: 3, child: _TH('LOCATION')),
                  Expanded(flex: 2, child: _TH('QTY')),
                  Expanded(flex: 2, child: _TH('UNIT PRICE')),
                  Expanded(flex: 2, child: _TH('TOTAL COST')),
                  SizedBox(width: 80, child: _TH('ACTIONS')),
                ],
              ),
            ),
            Divider(height: 1, color: _border),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No warehouse stock found',
                  style: TextStyle(color: _textLo),
                ),
              )
            else
              ...items.asMap().entries.map(
                    (e) => Column(
                  children: [
                    if (e.key > 0) Divider(height: 1, color: _border),
                    _WhTableRow(
                      item: e.value,
                      onEdit: () => onEdit(e.value),
                      onDelete: () => onDelete(e.value),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _buildCards() => SliverList(
    delegate: SliverChildBuilderDelegate(
          (ctx, i) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _WhCard(
          item: items[i],
          onEdit: () => onEdit(items[i]),
          onDelete: () => onDelete(items[i]),
        ),
      ),
      childCount: items.length,
    ),
  );

  Widget _buildPagination() {
    if (filteredCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'Total: $filteredCount',
            style: TextStyle(color: _textHi, fontSize: 14),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: DropdownButton<int>(
              value: itemsPerPage,
              underline: const SizedBox(),
              dropdownColor: _surface,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: _textLo),
              style: TextStyle(color: _textHi, fontSize: 14),
              items: pageSizeOptions.map((size) {
                return DropdownMenuItem<int>(
                  value: size,
                  child: Text('$size'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) onItemsPerPageChanged(value);
              },
            ),
          ),
          const SizedBox(width: 16),
          _PageNavButton(
            label: '<',
            enabled: currentPage > 1,
            onTap: () => onPageTap(currentPage - 1),
          ),
          const SizedBox(width: 6),
          ...visiblePages.map((item) {
            if (item == '...') {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '...',
                  style: TextStyle(color: _textLo, fontSize: 14),
                ),
              );
            }

            final page = item as int;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _PageTab(
                label: '$page',
                active: page == currentPage,
                onTap: () => onPageTap(page),
              ),
            );
          }),
          _PageNavButton(
            label: '>',
            enabled: currentPage < totalPages,
            onTap: () => onPageTap(currentPage + 1),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Store Tab
// ───────────────────────────────────────────────────────────────────────────
class _StoreTab extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> allItems;
  final bool isWindows;
  final ValueChanged<String> onSearch;
  final RefreshCallback onAdd, onRefresh;
  final ValueChanged<Map<String, dynamic>> onEdit, onDelete;
  final bool canImportStoreStock;
  final VoidCallback onImportStore;
  final int? selectedStoreId;
  final List<Map<String, dynamic>> stores;
  final ValueChanged<int?> onStoreFilter;

  final int filteredCount;
  final int currentPage;
  final int totalPages;
  final int itemsPerPage;
  final List<int> pageSizeOptions;
  final ValueChanged<int> onItemsPerPageChanged;
  final ValueChanged<int> onPageTap;
  final List<dynamic> visiblePages;

  const _StoreTab({
    required this.items,
    required this.allItems,
    required this.isWindows,
    required this.onSearch,
    required this.onAdd,
    required this.onRefresh,
    required this.onEdit,
    required this.onDelete,
    required this.canImportStoreStock,
    required this.onImportStore,
    required this.onStoreFilter,
    required this.filteredCount,
    required this.currentPage,
    required this.totalPages,
    required this.itemsPerPage,
    required this.pageSizeOptions,
    required this.onItemsPerPageChanged,
    required this.onPageTap,
    required this.visiblePages,
    this.selectedStoreId,
    this.stores = const [],
  });

  int get _totalUnits =>
      allItems.fold(0, (s, r) => s + toInt(r['quantity_in_stock']));
  int get _lowStock =>
      allItems.where((r) => toInt(r['quantity_in_stock']) <= 10).length;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _blue,
      backgroundColor: _surface,
      onRefresh: onRefresh,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildControls()),
          SliverToBoxAdapter(child: _buildStats()),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          isWindows ? _buildTable() : _buildCards(),
          SliverToBoxAdapter(child: _buildPagination()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildControls() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
    child: Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _SearchBar(
                hint: 'Search store stock…',
                onChanged: onSearch,
              ),
            ),
            const SizedBox(width: 12),
            Row(
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: _green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Stock'),
                ),
                const SizedBox(width: 8),
                if (canImportStoreStock)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _green,
                      side: BorderSide(color: _green.withOpacity(0.4)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onImportStore,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Import'),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int?>(
          value: selectedStoreId,
          dropdownColor: _surface,
          style: TextStyle(color: _textHi, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.storefront_rounded, color: _textLo, size: 18),
            hintText: 'All Stores',
            hintStyle: TextStyle(color: _textLo, fontSize: 13),
            filled: true,
            fillColor: _surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: _green, width: 1.5),
            ),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
          ),
          items: [
            const DropdownMenuItem(value: null, child: Text('All Stores')),
            ...stores.map(
                  (s) => DropdownMenuItem(
                value: toInt(s['store_id']),
                child: Text(
                  '${toStr(s['store_name'])} - ${toStr(s['store_address'])}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
          onChanged: onStoreFilter,
        ),
      ],
    ),
  );

  Widget _buildStats() => Padding(
    padding: const EdgeInsets.fromLTRB(24, 14, 24, 4),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _MiniStat(label: 'SKUs', value: '${allItems.length}', color: _green),
        _MiniStat(label: 'Total Units', value: '$_totalUnits', color: _blue),
        if (_lowStock > 0)
          _MiniStat(label: 'Low Stock', value: '$_lowStock', color: _red),
      ],
    ),
  );

  Widget _buildTable() => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: const [
                  Expanded(flex: 2, child: _TH('CODE')),
                  Expanded(flex: 5, child: _TH('DESCRIPTION')),
                  Expanded(flex: 3, child: _TH('LOCATION')),
                  Expanded(flex: 2, child: _TH('IN STOCK')),
                  Expanded(flex: 2, child: _TH('UNIT PRICE')),
                  Expanded(flex: 2, child: _TH('TOTAL COST')),
                  Expanded(flex: 2, child: _TH('AS OF')),
                  SizedBox(width: 80, child: _TH('ACTIONS')),
                ],
              ),
            ),
            Divider(height: 1, color: _border),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'No store stock found',
                  style: TextStyle(color: _textLo),
                ),
              )
            else
              ...items.asMap().entries.map(
                    (e) => Column(
                  children: [
                    if (e.key > 0) Divider(height: 1, color: _border),
                    _StTableRow(
                      item: e.value,
                      onEdit: () => onEdit(e.value),
                      onDelete: () => onDelete(e.value),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _buildCards() => SliverList(
    delegate: SliverChildBuilderDelegate(
          (ctx, i) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: _StCard(
          item: items[i],
          onEdit: () => onEdit(items[i]),
          onDelete: () => onDelete(items[i]),
        ),
      ),
      childCount: items.length,
    ),
  );

  Widget _buildPagination() {
    if (filteredCount == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'Total: $filteredCount',
            style: TextStyle(color: _textHi, fontSize: 14),
          ),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: DropdownButton<int>(
              value: itemsPerPage,
              underline: const SizedBox(),
              dropdownColor: _surface,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: _textLo),
              style: TextStyle(color: _textHi, fontSize: 14),
              items: pageSizeOptions.map((size) {
                return DropdownMenuItem<int>(
                  value: size,
                  child: Text('$size'),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) onItemsPerPageChanged(value);
              },
            ),
          ),
          const SizedBox(width: 16),
          _PageNavButton(
            label: '<',
            enabled: currentPage > 1,
            onTap: () => onPageTap(currentPage - 1),
          ),
          const SizedBox(width: 6),
          ...visiblePages.map((item) {
            if (item == '...') {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  '...',
                  style: TextStyle(color: _textLo, fontSize: 14),
                ),
              );
            }

            final page = item as int;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _PageTab(
                label: '$page',
                active: page == currentPage,
                onTap: () => onPageTap(page),
              ),
            );
          }),
          _PageNavButton(
            label: '>',
            enabled: currentPage < totalPages,
            onTap: () => onPageTap(currentPage + 1),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Warehouse row & card
// ───────────────────────────────────────────────────────────────────────────
class _WhTableRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onEdit, onDelete;

  const _WhTableRow({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final qty = toInt(item['quantity']);
    final price = toDouble(item['unit_price']);
    final cost = toDouble(item['total_cost']);
    final isLow = qty <= 10;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              toStr(item['product_code']),
              style: TextStyle(
                color: _teal,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
                cleanItemName(item['item_description']),
                style: TextStyle(color: _textHi, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: _LocationBadge(
              label: toStr(item['warehouse_address']),
              color: _teal,
              icon: Icons.warehouse_rounded,
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                if (isLow)
                  Icon(Icons.warning_amber_rounded, color: _amber, size: 14),
                if (isLow) const SizedBox(width: 4),
                Text(
                  '$qty',
                  style: TextStyle(
                    color: qty == 0 ? _red : isLow ? _amber : _textHi,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₱${price.toStringAsFixed(2)}',
              style: TextStyle(color: _textLo, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₱${cost.toStringAsFixed(2)}',
              style: TextStyle(color: _green, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 80,
            child: Row(
              children: [
                _IconBtn(
                  icon: Icons.edit_rounded,
                  color: _blue,
                  tooltip: 'Edit',
                  onTap: onEdit,
                ),
                const SizedBox(width: 4),
                _IconBtn(
                  icon: Icons.delete_rounded,
                  color: _red,
                  tooltip: 'Remove',
                  onTap: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WhCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onEdit, onDelete;

  const _WhCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final qty = toInt(item['quantity']);
    final price = toDouble(item['unit_price']);
    final cost = toDouble(item['total_cost']);
    final isLow = qty <= 10;
    final code = toStr(item['product_code']);
    final desc = cleanItemName(item['item_description']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isLow ? _amber.withOpacity(0.4) : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CodeBadge(code, _teal),
              const Spacer(),
              if (isLow)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _amber.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: _amber, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'Low',
                        style: TextStyle(
                          color: _amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              _IconBtn(
                icon: Icons.edit_rounded,
                color: _blue,
                tooltip: 'Edit',
                onTap: onEdit,
              ),
              const SizedBox(width: 4),
              _IconBtn(
                icon: Icons.delete_rounded,
                color: _red,
                tooltip: 'Remove',
                onTap: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: TextStyle(color: _textHi, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _LocationBadge(
            label: toStr(item['warehouse_address']),
            color: _teal,
            icon: Icons.warehouse_rounded,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  label: 'Qty in WH',
                  value: '$qty units',
                  valueColor: qty == 0 ? _red : isLow ? _amber : _textHi,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoTile(
                  label: 'Unit Price',
                  value: '₱${price.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoTile(
                  label: 'Total Cost',
                  value: '₱${cost.toStringAsFixed(2)}',
                  valueColor: _green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Store row & card
// ───────────────────────────────────────────────────────────────────────────
class _StTableRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onEdit, onDelete;

  const _StTableRow({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final qty = toInt(item['quantity_in_stock']);
    final price = toDouble(item['unit_price']);
    final cost = toDouble(item['total_cost']);
    final asOfRaw = toStr(item['as_of_date']);
    final asOf = asOfRaw.length >= 10 ? asOfRaw.substring(0, 10) : asOfRaw;
    final isLow = qty <= 10;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              toStr(item['product_code']),
              style: TextStyle(
                color: _green,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Text(
                cleanItemName(item['item_description']),
              style: TextStyle(color: _textHi, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: _LocationBadge(
              label: toStr(item['store_address']),
              color: _green,
              icon: Icons.storefront_rounded,
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                if (isLow)
                  Icon(Icons.warning_amber_rounded, color: _amber, size: 14),
                if (isLow) const SizedBox(width: 4),
                Text(
                  '$qty',
                  style: TextStyle(
                    color: qty == 0 ? _red : isLow ? _amber : _textHi,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₱${price.toStringAsFixed(2)}',
              style: TextStyle(color: _textLo, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₱${cost.toStringAsFixed(2)}',
              style: TextStyle(color: _teal, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              asOf,
              style: TextStyle(color: _textLo, fontSize: 12),
            ),
          ),
          SizedBox(
            width: 80,
            child: Row(
              children: [
                _IconBtn(
                  icon: Icons.edit_rounded,
                  color: _blue,
                  tooltip: 'Edit',
                  onTap: onEdit,
                ),
                const SizedBox(width: 4),
                _IconBtn(
                  icon: Icons.delete_rounded,
                  color: _red,
                  tooltip: 'Remove',
                  onTap: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onEdit, onDelete;

  const _StCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final qty = toInt(item['quantity_in_stock']);
    final price = toDouble(item['unit_price']);
    final cost = toDouble(item['total_cost']);
    final asOfRaw = toStr(item['as_of_date']);
    final asOf = asOfRaw.length >= 10 ? asOfRaw.substring(0, 10) : asOfRaw;
    final isLow = qty <= 10;
    final code = toStr(item['product_code']);
    final desc = cleanItemName(item['item_description']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isLow ? _amber.withOpacity(0.4) : _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CodeBadge(code, _green),
              const Spacer(),
              if (isLow)
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: _amber.withOpacity(0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, color: _amber, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        'Low',
                        style: TextStyle(
                          color: _amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              _IconBtn(
                icon: Icons.edit_rounded,
                color: _blue,
                tooltip: 'Edit',
                onTap: onEdit,
              ),
              const SizedBox(width: 4),
              _IconBtn(
                icon: Icons.delete_rounded,
                color: _red,
                tooltip: 'Remove',
                onTap: onDelete,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            desc,
            style: TextStyle(color: _textHi, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _LocationBadge(
            label: toStr(item['store_address']),
            color: _green,
            icon: Icons.storefront_rounded,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InfoTile(
                  label: 'In Stock',
                  value: '$qty units',
                  valueColor: qty == 0 ? _red : isLow ? _amber : _textHi,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoTile(
                  label: 'Unit Price',
                  value: '₱${price.toStringAsFixed(2)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _InfoTile(
                  label: 'As of',
                  value: asOf,
                  valueColor: _textLo,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _InfoTile(
            label: 'Total Cost',
            value: '₱${cost.toStringAsFixed(2)}',
            valueColor: _teal,
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Stock Add / Edit Dialog
// ───────────────────────────────────────────────────────────────────────────
class _StockFormDialog extends StatefulWidget {
  final String target;
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> warehouses, stores;
  final int currentUserId;

  const _StockFormDialog({
    required this.target,
    this.existing,
    required this.warehouses,
    required this.stores,
    required this.currentUserId,
  });

  @override
  State<_StockFormDialog> createState() => _StockFormDialogState();
}

class _StockFormDialogState extends State<_StockFormDialog> {
  final _formKey = GlobalKey<FormState>();
  String _selectedUom = 'PCS';
  List<Map<String, dynamic>> _uomList = [
    {'unit_name': 'PCS', 'conversion_qty': 1}
  ];

  late final _codeCtrl =
  TextEditingController(text: toStr(widget.existing?['product_code']));

  late final _qtyCtrl = TextEditingController(
    text: widget.target == 'warehouse'
        ? (widget.existing?['quantity'] == null
        ? ''
        : '${toInt(widget.existing?['quantity'])}')
        : (widget.existing?['quantity_in_stock'] == null
        ? ''
        : '${toInt(widget.existing?['quantity_in_stock'])}'),
  );

  late final _priceCtrl = TextEditingController(
    text: widget.existing != null
        ? toDouble(widget.existing!['unit_price']).toStringAsFixed(2)
        : '',
  );

  int _warehouseId = 1;
  int _storeId = 1;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;
  bool get _isWH => widget.target == 'warehouse';

  @override
  void initState() {
    super.initState();

    if (widget.warehouses.isNotEmpty) {
      _warehouseId = toInt(widget.warehouses.first['warehouse_id']);
    }
    if (widget.stores.isNotEmpty) {
      _storeId = toInt(widget.stores.first['store_id']);
    }
    if (_isEdit) {
      _warehouseId = widget.existing?['warehouse_id'] == null
          ? _warehouseId
          : toInt(widget.existing?['warehouse_id']);
      _storeId = widget.existing?['store_id'] == null
          ? _storeId
          : toInt(widget.existing?['store_id']);
    }

    final existingCode = _codeCtrl.text.trim();
    if (existingCode.isNotEmpty) {
      _loadProductUom(existingCode);
    }
  }

  Future<void> _loadProductUom(String productCode) async {
    final code = productCode.trim().toUpperCase();

    if (code.isEmpty) {
      setState(() {
        _selectedUom = 'PCS';
        _uomList = [
          {'unit_name': 'PCS', 'conversion_qty': 1}
        ];
      });
      return;
    }

    try {
      final url = Uri.parse('${ENV.PRODUCT_UNITS_URL}?product_code=$code');
      final res = await http.get(url);

      final data = jsonDecode(res.body);
      final units = (data['units'] as List?)
          ?.map((e) => Map<String, dynamic>.from(e as Map))
          .toList() ??
          [];

      if (!mounted) return;

      setState(() {
        _uomList = units.isEmpty
            ? [
          {'unit_name': 'PCS', 'conversion_qty': 1}
        ]
            : units;

        _selectedUom = toStr(_uomList.first['unit_name']).toUpperCase();
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _selectedUom = 'PCS';
        _uomList = [
          {'unit_name': 'PCS', 'conversion_qty': 1}
        ];
      });
    }
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final code = _codeCtrl.text.trim().toUpperCase();
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 0;
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0.0;

    DBResult result;
    if (_isEdit) {
      result = await DBService.instance.updateInventoryEntry(
        target: widget.target,
        productCode: code,
        quantity: qty,
        uom: _selectedUom,
        unitPrice: price,
        warehouseId: _isWH ? _warehouseId : null,
        storeId: _isWH ? null : _storeId,
        performedBy: widget.currentUserId,
      );
    } else {
      result = await DBService.instance.addInventoryEntry(
        target: widget.target,
        productCode: code,
        quantity: qty,
        uom: _selectedUom,
        unitPrice: price,
        warehouseId: _isWH ? _warehouseId : null,
        storeId: _isWH ? null : _storeId,
        performedBy: widget.currentUserId,
      );
    }

    if (!mounted) return;

    if (result.success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        _saving = false;
        _error = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = _isWH ? _teal : _green;
    final locationLabel = _isWH ? 'Warehouse' : 'Store';

    return Dialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: accentColor.withOpacity(0.4)),
                        ),
                        child: Icon(
                          _isWH
                              ? Icons.warehouse_rounded
                              : Icons.storefront_rounded,
                          color: accentColor,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${_isEdit ? 'Edit' : 'Add'} $locationLabel Stock',
                        style: TextStyle(
                          color: _textHi,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: _textLo),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  if (!_isEdit) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _blue.withOpacity(0.25)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded, color: _blue, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Product must exist in the Product Master before it can be added to inventory.',
                              style: TextStyle(color: _blue, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _Label(locationLabel),
                  const SizedBox(height: 6),
                  _isWH
                      ? _dropdown<int>(
                    value: _warehouseId,
                    items: widget.warehouses
                        .map(
                          (w) => DropdownMenuItem(
                        value: toInt(w['warehouse_id']),
                        child: Text(toStr(w['warehouse_name'])),
                      ),
                    )
                        .toList(),
                    onChanged: (v) => setState(() => _warehouseId = v!),
                  )
                      : _dropdown<int>(
                    value: _storeId,
                    items: widget.stores
                        .map(
                          (s) => DropdownMenuItem(
                        value: toInt(s['store_id']),
                        child: Text(toStr(s['store_name'])),
                      ),
                    )
                        .toList(),
                    onChanged: (v) => setState(() => _storeId = v!),
                  ),
                  const SizedBox(height: 16),
                  const _Label('Product Code *'),
                  const SizedBox(height: 6),
                  Focus(
                    onFocusChange: (hasFocus) {
                      if (!hasFocus) {
                        _loadProductUom(_codeCtrl.text);
                      }
                    },
                    child: _Field(
                      controller: _codeCtrl,
                      hint: 'e.g. 20001',
                      icon: Icons.qr_code_rounded,
                      readOnly: _isEdit,
                      keyType: TextInputType.text,
                      validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _Label('Quantity *'),
                            const SizedBox(height: 6),
                            _Field(
                              controller: _qtyCtrl,
                              hint: '0',
                              icon: Icons.numbers_rounded,
                              keyType: TextInputType.number,
                              validator: (v) {
                                if (v == null || v.trim().isEmpty) return 'Required';
                                if (int.tryParse(v.trim()) == null) return 'Must be a whole number';
                                if (int.parse(v.trim()) < 0) return 'Cannot be negative';
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const _Label('UOM *'),
                            const SizedBox(height: 6),
                            _dropdown<String>(
                              value: _selectedUom,
                              items: _uomList.map((u) {
                                final name = toStr(u['unit_name']).toUpperCase();
                                final conv = toDouble(u['conversion_qty']);

                                return DropdownMenuItem<String>(
                                  value: name,
                                  child: Text('$name = ${conv.toStringAsFixed(0)} PCS'),
                                );
                              }).toList(),
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _selectedUom = v);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const _Label('Unit Price (₱) *'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _priceCtrl,
                    hint: '0.00',
                    icon: Icons.attach_money_rounded,
                    keyType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (double.tryParse(v.trim()) == null) return 'Invalid price';
                      if (double.parse(v.trim()) < 0) return 'Cannot be negative';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _red.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline, color: _red, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(color: _red, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: _border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed:
                          _saving ? null : () => Navigator.of(context).pop(false),
                          child: Text('Cancel', style: TextStyle(color: _textLo)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: accentColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _saving ? null : _submit,
                          child: _saving
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                              : Text(
                            _isEdit ? 'Save Changes' : 'Add Stock',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _dropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      dropdownColor: _surface,
      style: TextStyle(color: _textHi, fontSize: 14),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withOpacity(0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: _blue, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ───────────────────────────────────────────────────────────────────────────
class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;

  const _CountBadge({
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      '$count',
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _CodeBadge extends StatelessWidget {
  final String code;
  final Color color;

  const _CodeBadge(this.code, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withOpacity(0.12),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: color.withOpacity(0.35)),
    ),
    child: Text(
      code,
      style: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w700,
        fontFamily: 'monospace',
      ),
    ),
  );
}

class _CatBadge extends StatelessWidget {
  final String label;
  const _CatBadge(this.label);

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) {
      return Text('—', style: TextStyle(color: _textLo, fontSize: 12));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: _amber.withOpacity(0.10),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: _amber.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: _amber, fontSize: 11, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label, value;
  final Color? valueColor;

  const _InfoTile({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: _bg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: _textLo, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? _textHi,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    ),
  );
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: _border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: _textLo, fontSize: 12)),
      ],
    ),
  );
}

class _SearchBar extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const _SearchBar({
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => TextField(
    style: TextStyle(color: _textHi, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _textLo, fontSize: 13),
      prefixIcon: Icon(Icons.search_rounded, color: _textLo, size: 20),
      filled: true,
      fillColor: _surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _blue, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    onChanged: onChanged,
  );
}

String cleanItemName(dynamic value) {
  var text = toStr(value)
      .replaceAll('️', '')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  text = text.replaceFirst(RegExp(r'\s*-\s+.*$'), '').trim();
  text = text.replaceFirst(RegExp(r'\s+!\s*.*$'), '').trim();

  text = text.replaceFirst(RegExp(r'\s+is the\s+.*$', caseSensitive: false), '').trim();
  text = text.replaceFirst(RegExp(r'\s+perfect for\s+.*$', caseSensitive: false), '').trim();
  text = text.replaceFirst(RegExp(r'\s+great for\s+.*$', caseSensitive: false), '').trim();
  text = text.replaceFirst(RegExp(r'\s+ideal for\s+.*$', caseSensitive: false), '').trim();
  text = text.replaceFirst(RegExp(r'\s+by\s+.*$', caseSensitive: false), '').trim();

  return text.trim();
}class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool readOnly;
  final TextInputType keyType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.readOnly = false,
    this.keyType = TextInputType.text,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    readOnly: readOnly,
    validator: validator,
    keyboardType: keyType,
    style: TextStyle(color: readOnly ? _textLo : _textHi, fontSize: 14),
    decoration: InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: _textLo, fontSize: 13),
      prefixIcon: Icon(icon, color: _textLo, size: 18),
      filled: true,
      fillColor:
      readOnly ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.04),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _blue, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _red),
      ),
      errorStyle: TextStyle(color: _red, fontSize: 11),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
    ),
  );
}

class _TH extends StatelessWidget {
  final String text;
  const _TH(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: _textLo,
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.5,
    ),
  );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(color: _textLo, fontSize: 12, fontWeight: FontWeight.w500),
  );
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, color: color, size: 18),
      ),
    ),
  );
}

class _ConfirmDialog extends StatelessWidget {
  final String title, message, confirmLabel;
  final Color confirmColor;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _surface,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    title: Text(
      title,
      style: TextStyle(color: _textHi, fontWeight: FontWeight.w700),
    ),
    content: Text(
      message,
      style: TextStyle(color: _textLo, fontSize: 13),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: Text('Cancel', style: TextStyle(color: _textLo)),
      ),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: confirmColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () => Navigator.of(context).pop(true),
        child: Text(confirmLabel),
      ),
    ],
  );
}

class _PageTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PageTab({
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: onTap,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: active ? _blue : _surface,
        shape: BoxShape.circle,
        border: Border.all(color: active ? _blue : _border),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : _textHi,
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    ),
  );
}

class _PageNavButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PageNavButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(20),
    onTap: enabled ? onTap : null,
    child: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: enabled ? _surface : _surface.withOpacity(0.5),
        shape: BoxShape.circle,
        border: Border.all(color: _border),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            color: enabled ? _textHi : _textLo,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_rounded, color: _textLo, size: 48),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(color: _textLo, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}