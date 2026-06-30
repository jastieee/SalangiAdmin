import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:async';
import '../db/DBResult.dart';
import '../Utils/app_theme.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'dart:convert';
import '../DB/env.dart';
import 'package:share_plus/share_plus.dart';
import 'inventory_screen.dart';

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

class ProductManagementScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;
  const ProductManagementScreen({super.key, this.currentUser});

  @override
  State<ProductManagementScreen> createState() => _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  String _sortBy = '';
  String _sortDir = 'asc';

  // ── Products tab state ──────────────────────────────────────────────────
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _products = [];
  List<String> _categories = [];
  String _searchQuery = '';
  int _itemsPerPage = 10;
  int _currentPage = 1;

  // ── Pending tab state ───────────────────────────────────────────────────
  bool _pendingLoading = false;
  String? _pendingError;
  List<Map<String, dynamic>> _pendingItems = [];
  String _pendingSearch = '';
  int _pendingItemsPerPage = 10;
  int _pendingCurrentPage = 1;
  bool _pendingLoadedOnce = false;

  final List<int> _pageSizeOptions = [10, 20, 50, 100];

  bool get _isWindows {
    try {
      return !kIsWeb && Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  int get _currentUserId => _toInt(widget.currentUser?['user_id']);

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
      final canAccess = p['can_access'] == true ||
          p['can_access'] == 1 ||
          p['can_access'].toString() == '1';
      return name == moduleName.trim().toUpperCase() && canAccess;
    });
  }

  bool get canViewProducts => hasPermission('PRODUCT_VIEW');
  bool get canImportProducts => hasPermission('PRODUCT_CREATE');
  bool get canCreateProducts => hasPermission('PRODUCT_CREATE');
  bool get canEditProducts => hasPermission('PRODUCT_EDIT');
  bool get canDeleteProducts => hasPermission('PRODUCT_DELETE');
  bool get canManageUom => hasPermission('PRODUCT_MANAGE_UOM');

  // Pending tab requires PRODUCT_CREATE since assigning creates a product
  bool get canManagePending => canCreateProducts;

  @override
  void initState() {
    super.initState();
    _load();
    _tabs.addListener(() {
      if (_tabs.indexIsChanging) return;
      // Lazy-load pending the first time it's tapped
      if (_tabs.index == 1 && !_pendingLoadedOnce && canManagePending) {
        _loadPending();
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  // ── Safe converters ─────────────────────────────────────────────────────
  int _toInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _toStr(dynamic v) => v?.toString() ?? '';

  List<Map<String, dynamic>> _toList(dynamic v) =>
      (v as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
          [];

  List<String> _toStrList(dynamic v) =>
      (v as List?)?.map((e) => e.toString()).toList() ?? [];


  Future<void> _exportBarcodes() async {
    try {
      final buffer = StringBuffer();
      buffer.writeln('barcode,item_description,unit_price');


      for (final p in _products) {
        final barcode = _toStr(p['product_code']);
        final desc = cleanItemName(p['item_description'])
            .replaceAll('"', '""');
        // ← Force Excel to treat barcode as text by prefixing with tab or using ="..."
        final price = _toDouble(p['unit_price']);
        buffer.writeln('="$barcode","$desc",${price.toStringAsFixed(2)}');
      }


      final bytes = utf8.encode(buffer.toString());
      final fileName = 'products_barcode_${DateTime.now().millisecondsSinceEpoch}.csv';

      if (kIsWeb) {
        _snack('Export not supported on web yet.', error: true);
        return;
      }

      if (Platform.isAndroid || Platform.isIOS) {
        final dir = await getTemporaryDirectory();
        final outputPath = '${dir.path}/$fileName';
        await File(outputPath).writeAsBytes(bytes);
        await Share.shareXFiles(
          [XFile(outputPath, mimeType: 'text/csv')],
          subject: fileName,
        );
        return;
      }

      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final outputPath = await FilePicker.saveFile(  // ← .platform.
          dialogTitle: 'Save barcode export',
          fileName: fileName,
          allowedExtensions: ['csv'],
          type: FileType.custom,
        );
        if (outputPath == null) return;
        await File(outputPath).writeAsBytes(bytes);
        _snack('Exported ${_products.length} products to $fileName');
      }

    } catch (e) {
      _snack('Export failed: $e', error: true);
    }
  }
  // ── Products loader ─────────────────────────────────────────────────────
  Future<void> _load() async {
    if (!canViewProducts) {
      setState(() {
        _loading = false;
        _error = 'You do not have permission to view products.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await DBService.instance.fetchProducts();

    if (!mounted) return;

    setState(() {
      _loading = false;
      if (result.success) {
        _products = _toList(result.data?['products']);
        _categories = _toStrList(result.data?['categories']);
        _currentPage = 1;
      } else {
        _error = result.message;
      }
    });
  }

  // ── Pending loader ──────────────────────────────────────────────────────
  Future<void> _loadPending() async {
    if (!canManagePending) {
      setState(() {
        _pendingLoadedOnce = true;
        _pendingError = 'You do not have permission to manage pending items.';
      });
      return;
    }

    setState(() {
      _pendingLoading = true;
      _pendingError = null;
    });

    final result = await DBService.instance.fetchPendingItems();

    if (!mounted) return;

    setState(() {
      _pendingLoading = false;
      _pendingLoadedOnce = true;
      if (result.success) {
        _pendingItems = _toList(result.data?['items']);
        _pendingCurrentPage = 1;
      } else {
        _pendingError = result.message;
      }
    });
  }

  // ── Products: filter + page ─────────────────────────────────────────────
  // FIND and REPLACE the entire _filtered getter:
  List<Map<String, dynamic>> get _filtered {
    final q = _searchQuery.trim().toLowerCase();
    var list = _products.where((p) {
      if (q.isEmpty) return true;
      return _toStr(p['product_code']).toLowerCase().contains(q) ||
          _toStr(p['uom']).toLowerCase().contains(q) ||
          _toStr(p['item_description']).toLowerCase().contains(q);
    }).toList();

    list.sort((a, b) {
      int cmp = 0;
      switch (_sortBy) {
        case 'name':
          cmp = cleanItemName(a['item_description'])
              .toLowerCase()
              .compareTo(cleanItemName(b['item_description']).toLowerCase());
          break;
        case 'price':
          cmp = _toDouble(a['unit_price']).compareTo(_toDouble(b['unit_price']));
          break;
        case 'code':
          cmp = _toStr(a['product_code'])
              .toLowerCase()
              .compareTo(_toStr(b['product_code']).toLowerCase());
          break;
      }
      return _sortDir == 'desc' ? -cmp : cmp;
    });

    return list;
  }

  int get _totalPages {
    final total = _filtered.length;
    if (total == 0) return 1;
    return (total / _itemsPerPage).ceil();
  }

  List<Map<String, dynamic>> get _pagedProducts {
    final list = _filtered;
    final start = (_currentPage - 1) * _itemsPerPage;
    if (start >= list.length) return [];
    final end = (start + _itemsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  // ── Pending: filter + page ──────────────────────────────────────────────
  List<Map<String, dynamic>> get _filteredPending {
    final q = _pendingSearch.trim().toLowerCase();
    return _pendingItems.where((p) {
      if (q.isEmpty) return true;
      return _toStr(p['item_description']).toLowerCase().contains(q) ||
          _toStr(p['store_name']).toLowerCase().contains(q) ||
          _toStr(p['warehouse_name']).toLowerCase().contains(q);
    }).toList();
  }

  int get _pendingTotalPages {
    final total = _filteredPending.length;
    if (total == 0) return 1;
    return (total / _pendingItemsPerPage).ceil();
  }

  List<Map<String, dynamic>> get _pagedPending {
    final list = _filteredPending;
    final start = (_pendingCurrentPage - 1) * _pendingItemsPerPage;
    if (start >= list.length) return [];
    final end = (start + _pendingItemsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  List<dynamic> _visiblePageItems({required int current, required int total}) {
    if (total <= 7) return List<int>.generate(total, (i) => i + 1);

    final items = <dynamic>[1];
    if (current > 3) items.add('...');

    final start = current <= 3 ? 2 : current - 1;
    final end = current >= total - 2 ? total - 1 : current + 1;

    for (int i = start; i <= end; i++) {
      if (i > 1 && i < total) items.add(i);
    }

    if (current < total - 2) items.add('...');
    items.add(total);
    return items;
  }

  void _goToPage(int page) {
    final safe = page.clamp(1, _totalPages);
    setState(() => _currentPage = safe);
  }

  void _goToPendingPage(int page) {
    final safe = page.clamp(1, _pendingTotalPages);
    setState(() => _pendingCurrentPage = safe);
  }

  // ── Actions (products) ──────────────────────────────────────────────────
  Future<void> _confirmDelete(Map<String, dynamic> product) async {
    if (!canDeleteProducts) {
      _snack('You do not have permission to delete products.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Delete Product',
        message:
        'Remove "${_toStr(product['item_description'])}" (${_toStr(product['product_code'])}) permanently? '
            'This will fail if the product has existing stock records.',
        confirmLabel: 'Delete',
        confirmColor: _red,
      ),
    );

    if (ok != true || !mounted) return;

    final result = await DBService.instance.deleteProduct(
      productCode: _toStr(product['product_code']),
      performedBy: _currentUserId,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _products.removeWhere(
                (p) => _toStr(p['product_code']) == _toStr(product['product_code']));
        if (_currentPage > _totalPages) _currentPage = _totalPages;
      });
      _snack('Product deleted');
    } else {
      _snack(result.message, error: true);
    }
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    if (existing == null && !canCreateProducts) {
      _snack('You do not have permission to create products.', error: true);
      return;
    }
    if (existing != null && !canEditProducts) {
      _snack('You do not have permission to edit products.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductFormDialog(
        existing: existing,
        categories: _categories,
        currentUserId: _currentUserId,
      ),
    );

    if (ok == true) _load();
  }

  Future<void> _openUnitsForm(Map<String, dynamic> product) async {
    if (!canManageUom) {
      _snack('You do not have permission to manage UOM.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProductUnitsDialog(
        product: product,
        currentUserId: _currentUserId,
      ),
    );

    if (ok == true) _load();
  }

  Future<void> _importProducts() async {
    if (!canImportProducts) {
      _snack('You do not have permission to import products.', error: true);
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
      withData: kIsWeb,
    );

    if (result == null || result.files.isEmpty) return;

    try {
      final file = result.files.single;
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ENV.IMPORT_PRODUCTS_URL),
      );

      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) {
          _snack('Unable to read file.', error: true);
          return;
        }
        request.files
            .add(http.MultipartFile.fromBytes('file', bytes, filename: file.name));
      } else {
        final path = file.path;
        if (path == null || path.isEmpty) {
          _snack('Invalid file.', error: true);
          return;
        }
        request.files.add(await http.MultipartFile.fromPath('file', path));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final respData = jsonDecode(response.body);

      if (response.statusCode == 200 && respData['success'] == true) {
        final inserted = _toInt(respData['inserted']);
        final updated = _toInt(respData['updated']);
        final pending = _toInt(respData['pending']);
        final errors = (respData['errors'] as List?) ?? [];

        if (errors.isEmpty) {
          _snack(
              'Import successful: $inserted inserted, $updated updated, $pending pending.');
        } else {
          _snack(
              'Imported with ${errors.length} issue(s): $inserted inserted, $updated updated, $pending pending.');
        }

        await _load();
        // If anything went into pending, refresh the pending tab too
        if (pending > 0 && _pendingLoadedOnce) {
          await _loadPending();
        }

        if (errors.isNotEmpty && mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: _surface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              title: Text('Import Result',
                  style: TextStyle(
                      color: _textHi, fontWeight: FontWeight.w700)),
              content: SizedBox(
                width: 420,
                child: SingleChildScrollView(
                  child: Text(errors.join('\n'),
                      style: TextStyle(color: _textLo, fontSize: 13)),
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
      } else {
        _snack(respData['message'] ?? 'Import failed.', error: true);
      }
    } catch (e) {
      _snack('Import failed: $e', error: true);
    }
  }

  Future<void> _importProductUnits() async {
    if (!canManageUom) {
      _snack('You do not have permission to import UOM.', error: true);
      return;
    }

    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx'],
      withData: kIsWeb,
    );

    if (result == null || result.files.isEmpty) return;

    try {
      final file = result.files.single;
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ENV.IMPORT_PRODUCT_UNITS_URL),
      );

      request.fields['performed_by'] = _currentUserId.toString();

      if (kIsWeb) {
        final bytes = file.bytes;
        if (bytes == null) {
          _snack('Unable to read file.', error: true);
          return;
        }
        request.files.add(
          http.MultipartFile.fromBytes('file', bytes, filename: file.name),
        );
      } else {
        final path = file.path;
        if (path == null || path.isEmpty) {
          _snack('Invalid file.', error: true);
          return;
        }
        request.files.add(await http.MultipartFile.fromPath('file', path));
      }

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      final respData = jsonDecode(response.body);

      if (response.statusCode == 200 && respData['success'] == true) {
        final inserted = _toInt(respData['inserted']);
        final updated = _toInt(respData['updated']);
        final skipped = _toInt(respData['skipped']);
        final errors = (respData['errors'] as List?) ?? [];

        _snack('UOM import done: $inserted inserted, $updated updated, $skipped skipped.');

        await _load();

        if (errors.isNotEmpty && mounted) {
          showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: _surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              title: Text('UOM Import Result',
                  style: TextStyle(color: _textHi, fontWeight: FontWeight.w700)),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Text(errors.join('\n'),
                      style: TextStyle(color: _textLo, fontSize: 13)),
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
      } else {
        _snack(respData['message'] ?? 'UOM import failed.', error: true);
      }
    } catch (e) {
      _snack('UOM import failed: $e', error: true);
    }
  }

  // ── Pending actions ─────────────────────────────────────────────────────
  Future<void> _openAssignDialog(Map<String, dynamic> item) async {
    if (!canManagePending) {
      _snack('You do not have permission to assign pending items.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AssignPendingDialog(item: item),
    );

    if (ok == true) {
      await _loadPending();
      await _load(); // refresh products since a new one was just created
    }
  }

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

  // ── BUILD ───────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator(color: _blue));
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);

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
                _buildProductsTab(),
                _buildPendingTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final onProductsTab = _tabs.index == 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Product Master',
                      style: TextStyle(
                          color: _textHi,
                          fontSize: 22,
                          fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _tabs.index == 0
                          ? 'Product code, UOM, description, and selling price / SRP'
                          : 'Imported items waiting for SKU assignment',
                      style: TextStyle(color: _textLo, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: Icon(Icons.refresh_rounded, color: _textLo),
                onPressed: _tabs.index == 0 ? _load : _loadPending,
              ),
            ],
          ),
          if (_tabs.index == 0) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (canImportProducts)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.orange,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _importProducts,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('Import'),
                  ),
                if (canManageUom)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _green,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _importProductUnits,
                    icon: const Icon(Icons.straighten_rounded, size: 18),
                    label: const Text('Import UOM'),
                  ),
                if (canCreateProducts)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _blue,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New Product'),
                  ),
                if (canViewProducts && _products.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: _teal,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _exportBarcodes,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Export Barcodes'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final pendingCount = _pendingItems.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: TabBar(
          controller: _tabs,
          onTap: (_) => setState(() {}), // refresh header subtitle/buttons
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
            const Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.inventory_2_rounded, size: 16),
                  SizedBox(width: 6),
                  Text('Products'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.pending_actions_rounded, size: 16),
                  const SizedBox(width: 6),
                  const Text('Pending'),
                  if (pendingCount > 0) ...[
                    const SizedBox(width: 6),
                    _CountBadge(count: pendingCount, color: _amber),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Products tab ────────────────────────────────────────────────────────
  Widget _buildProductsTab() => RefreshIndicator(
    color: _blue,
    backgroundColor: _surface,
    onRefresh: _load,
    child: CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(child: _buildFilters()),
        SliverToBoxAdapter(child: _buildStats()),
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        _isWindows ? _buildTable() : _buildCards(),
        SliverToBoxAdapter(child: _buildPagination()),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    ),
  );

  Widget _buildFilters() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 16, 12, 0),
    child: _SearchBar(
      hint: 'Search code, UOM, or description…',
      onChanged: (v) => setState(() {
        _searchQuery = v;
        _currentPage = 1;
      }),
    ),
  );

  Widget _buildStats() {
    final total = _products.length;
    final filtered = _filtered.length;
    final showing = _pagedProducts.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Row(
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MiniStat(label: 'Total Products', value: '$total', color: _blue),
              _MiniStat(label: 'Filtered', value: '$filtered', color: _teal),
              _MiniStat(
                  label: 'Showing',
                  value: '$showing / $_itemsPerPage',
                  color: _amber),
              _MiniStat(
                  label: 'Page',
                  value: '$_currentPage / $_totalPages',
                  color: _green),
            ],
          ),
          const Spacer(),
          _SortControl(
            sortBy: _sortBy,
            sortDir: _sortDir,
            options: const [
              {
                'value': 'name',
                'label': 'Name',
                'icon': Icons.sort_by_alpha_rounded,
              },
              {
                'value': 'code',
                'label': 'Code',
                'icon': Icons.qr_code_rounded,
              },
              {
                'value': 'price',
                'label': 'Price',
                'icon': Icons.price_change_rounded,
              },
            ],
            onChanged: (by, dir) => setState(() {
              _sortBy = by;
              _sortDir = dir;
              _currentPage = 1;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final list = _pagedProducts;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        child: Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              Padding(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: const [
                    Expanded(flex: 2, child: _TH('PRODUCT CODE')),
                    Expanded(flex: 2, child: _TH('UOM')),
                    Expanded(flex: 6, child: _TH('DESCRIPTION')),
                    Expanded(flex: 2, child: _TH('SELLING PRICE / SRP')),
                    SizedBox(width: 118, child: _TH('ACTIONS')),
                  ],
                ),
              ),
              Divider(height: 1, color: _border),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('No products found',
                      style: TextStyle(color: _textLo)),
                )
              else
                ...list.asMap().entries.map((e) {
                  final idx = e.key;
                  final prod = e.value;
                  return Column(
                    children: [
                      if (idx > 0) Divider(height: 1, color: _border),
                      _TableRow(
                        product: prod,
                        canEdit: canEditProducts,
                        canDelete: canDeleteProducts,
                        canManageUom: canManageUom,
                        onEdit: () => _openForm(existing: prod),
                        onUnits: () => _openUnitsForm(prod),
                        onDelete: () => _confirmDelete(prod),
                      ),
                    ],
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCards() {
    final list = _pagedProducts;
    if (list.isEmpty) {
      return SliverFillRemaining(
        child: Center(
            child: Text('No products found', style: TextStyle(color: _textLo))),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          final prod = list[index];
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: _ProductCard(
              product: prod,
              canEdit: canEditProducts,
              canDelete: canDeleteProducts,
              canManageUom: canManageUom,
              onEdit: () => _openForm(existing: prod),
              onUnits: () => _openUnitsForm(prod),
              onDelete: () => _confirmDelete(prod),
            ),
          );
        },
        childCount: list.length,
      ),
    );
  }

  Widget _buildPagination() {
    if (_filtered.isEmpty) return const SizedBox.shrink();
    final items = _visiblePageItems(current: _currentPage, total: _totalPages);

    return _PaginationBar(
      filteredCount: _filtered.length,
      currentPage: _currentPage,
      totalPages: _totalPages,
      itemsPerPage: _itemsPerPage,
      pageSizeOptions: _pageSizeOptions,
      visiblePages: items,
      onPageTap: _goToPage,
      onSizeChanged: (v) => setState(() {
        _itemsPerPage = v;
        _currentPage = 1;
      }),
    );
  }

  // ── Pending tab ─────────────────────────────────────────────────────────
  Widget _buildPendingTab() {
    if (!canManagePending) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'You do not have permission to manage pending items.',
            style: TextStyle(color: _textLo, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_pendingLoading) {
      return Center(child: CircularProgressIndicator(color: _blue));
    }

    if (_pendingError != null) {
      return _ErrorView(message: _pendingError!, onRetry: _loadPending);
    }

    return RefreshIndicator(
      color: _blue,
      backgroundColor: _surface,
      onRefresh: _loadPending,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: _SearchBar(
                hint: 'Search description, store, or warehouse…',
                onChanged: (v) => setState(() {
                  _pendingSearch = v;
                  _pendingCurrentPage = 1;
                }),
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildPendingStats()),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          _isWindows ? _buildPendingTable() : _buildPendingCards(),
          SliverToBoxAdapter(child: _buildPendingPagination()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildPendingStats() {
    final total = _pendingItems.length;
    final filtered = _filteredPending.length;
    final showing = _pagedPending.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MiniStat(label: 'Pending', value: '$total', color: _amber),
          _MiniStat(label: 'Filtered', value: '$filtered', color: _teal),
          _MiniStat(
              label: 'Showing',
              value: '$showing / $_pendingItemsPerPage',
              color: _blue),
          _MiniStat(
              label: 'Page',
              value: '$_pendingCurrentPage / $_pendingTotalPages',
              color: _green),
        ],
      ),
    );
  }

  Widget _buildPendingTable() {
    final list = _pagedPending;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
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
                    Expanded(flex: 5, child: _TH('DESCRIPTION')),
                    Expanded(flex: 2, child: _TH('PRICE')),
                    Expanded(flex: 2, child: _TH('WAREHOUSE QTY')),
                    Expanded(flex: 2, child: _TH('STORE QTY')),
                    Expanded(flex: 3, child: _TH('LOCATION')),
                    Expanded(flex: 2, child: _TH('IMPORTED')),
                    SizedBox(width: 110, child: _TH('ACTION')),
                  ],
                ),
              ),
              Divider(height: 1, color: _border),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('No pending items',
                      style: TextStyle(color: _textLo)),
                )
              else
                ...list.asMap().entries.map((e) {
                  final idx = e.key;
                  final item = e.value;
                  return Column(
                    children: [
                      if (idx > 0) Divider(height: 1, color: _border),
                      _PendingTableRow(
                        item: item,
                        onAssign: () => _openAssignDialog(item),
                      ),
                    ],
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingCards() {
    final list = _pagedPending;
    if (list.isEmpty) {
      return SliverFillRemaining(
        child: Center(
            child:
            Text('No pending items', style: TextStyle(color: _textLo))),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          final item = list[index];
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: _PendingCard(
              item: item,
              onAssign: () => _openAssignDialog(item),
            ),
          );
        },
        childCount: list.length,
      ),
    );
  }

  Widget _buildPendingPagination() {
    if (_filteredPending.isEmpty) return const SizedBox.shrink();
    final items = _visiblePageItems(
        current: _pendingCurrentPage, total: _pendingTotalPages);

    return _PaginationBar(
      filteredCount: _filteredPending.length,
      currentPage: _pendingCurrentPage,
      totalPages: _pendingTotalPages,
      itemsPerPage: _pendingItemsPerPage,
      pageSizeOptions: _pageSizeOptions,
      visiblePages: items,
      onPageTap: _goToPendingPage,
      onSizeChanged: (v) => setState(() {
        _pendingItemsPerPage = v;
        _pendingCurrentPage = 1;
      }),
    );
  }
}

// ── Table row ──────────────────────────────────────────────────────────────
class _TableRow extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onEdit, onUnits, onDelete;
  final bool canEdit;
  final bool canDelete;
  final bool canManageUom;

  const _TableRow({
    required this.product,
    required this.onEdit,
    required this.onUnits,
    required this.onDelete,
    required this.canEdit,
    required this.canDelete,
    required this.canManageUom,
  });

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _toStr(dynamic v) => v?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final unitPrice = _toDouble(product['unit_price']);
    final uom = _toStr(product['uom']).trim().isEmpty
        ? 'PCS'
        : _toStr(product['uom']).trim().toUpperCase();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              _toStr(product['product_code']),
              style: TextStyle(
                color: _teal,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              uom,
              style: TextStyle(color: _green, fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              cleanItemName(product['item_description']),
              style: TextStyle(color: _textHi, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₱${unitPrice.toStringAsFixed(2)}',
              style: TextStyle(color: _amber, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            width: 118,
            child: Row(
              children: [
                if (canManageUom) ...[
                  _IconBtn(
                    icon: Icons.straighten_rounded,
                    color: _green,
                    tooltip: 'Manage UOM',
                    onTap: onUnits,
                  ),
                  const SizedBox(width: 4),
                ],
                if (canEdit) ...[
                  _IconBtn(
                    icon: Icons.edit_rounded,
                    color: _blue,
                    tooltip: 'Edit',
                    onTap: onEdit,
                  ),
                  const SizedBox(width: 4),
                ],
                if (canDelete)
                  _IconBtn(
                    icon: Icons.delete_rounded,
                    color: _red,
                    tooltip: 'Delete',
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
class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onEdit, onUnits, onDelete;
  final bool canEdit;
  final bool canDelete;
  final bool canManageUom;

  const _ProductCard({
    required this.product,
    required this.onEdit,
    required this.onUnits,
    required this.onDelete,
    required this.canEdit,
    required this.canDelete,
    required this.canManageUom,
  });

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String _toStr(dynamic v) => v?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final code = _toStr(product['product_code']);
    final desc = cleanItemName(product['item_description']);
    final unitPrice = _toDouble(product['unit_price']);
    final uom = _toStr(product['uom']).trim().isEmpty
        ? 'PCS'
        : _toStr(product['uom']).trim().toUpperCase();

    final hasAnyAction = canManageUom || canEdit || canDelete;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _teal.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _teal.withOpacity(0.35)),
                ),
                child: Text(
                  code,
                  style: TextStyle(
                    color: _teal,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _green.withOpacity(0.35)),
                ),
                child: Text(
                  uom,
                  style: TextStyle(color: _green, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const Spacer(),
              if (hasAnyAction) ...[
                if (canManageUom)
                  _IconBtn(icon: Icons.straighten_rounded, color: _green, tooltip: 'Manage UOM', onTap: onUnits),
                if (canEdit)
                  _IconBtn(icon: Icons.edit_rounded, color: _blue, tooltip: 'Edit', onTap: onEdit),
                if (canDelete)
                  _IconBtn(icon: Icons.delete_rounded, color: _red, tooltip: 'Delete', onTap: onDelete),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Text(desc, style: TextStyle(color: _textHi, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(
            'SRP: ₱${unitPrice.toStringAsFixed(2)}',
            style: TextStyle(color: _amber, fontSize: 14, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: _textLo, fontSize: 12)),
        ],
      ),
    );
  }
}

class _ProductUnitsDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final int currentUserId;

  const _ProductUnitsDialog({required this.product, required this.currentUserId});

  @override
  State<_ProductUnitsDialog> createState() => _ProductUnitsDialogState();
}

// ── Product Units Dialog ──────────────────────────────────────────────────
class _ProductUnitDraft {
  final TextEditingController unitNameCtrl;
  final TextEditingController barcodeCtrl;
  final TextEditingController conversionCtrl;
  bool isBase;

  _ProductUnitDraft({
    required String unitName,
    required String barcode,
    required double conversionQty,
    required this.isBase,
  })  : unitNameCtrl = TextEditingController(text: unitName),
        barcodeCtrl = TextEditingController(text: barcode),
        conversionCtrl = TextEditingController(
          text: conversionQty.toStringAsFixed(
            conversionQty == conversionQty.roundToDouble() ? 0 : 4,
          ),
        );

  void dispose() {
    unitNameCtrl.dispose();
    barcodeCtrl.dispose();
    conversionCtrl.dispose();
  }

  Map<String, dynamic> toJson() => {
    'unit_name': unitNameCtrl.text.trim().toUpperCase(),
    'barcode': barcodeCtrl.text.trim(),
    'conversion_qty': double.tryParse(conversionCtrl.text.trim()) ?? 0,
    'is_base': isBase ? 1 : 0,
  };
}

class _ProductUnitsDialogState extends State<_ProductUnitsDialog> {
  final _formKey = GlobalKey<FormState>();
  final List<_ProductUnitDraft> _units = [];

  bool _loading = true;
  bool _saving = false;
  String? _error;

  String _toStr(dynamic v) => v?.toString() ?? '';

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  String get _productCode => _toStr(widget.product['product_code']).toUpperCase();
  String get _description => cleanItemName(widget.product['item_description']);

  @override
  void initState() {
    super.initState();
    _loadUnits();
  }

  @override
  void dispose() {
    for (final unit in _units) {
      unit.dispose();
    }
    super.dispose();
  }

  Future<void> _loadUnits() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await DBService.instance.fetchProductUnits(productCode: _productCode);

    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _loading = false;
        _error = result.message;
      });
      return;
    }

    final list = (result.data?['units'] as List?) ?? [];
    for (final old in _units) {
      old.dispose();
    }
    _units.clear();

    for (final item in list) {
      final map = Map<String, dynamic>.from(item as Map);
      _units.add(_ProductUnitDraft(
        unitName: _toStr(map['unit_name']).toUpperCase(),
        barcode: _toStr(map['barcode']),
        conversionQty: _toDouble(map['conversion_qty']) <= 0 ? 1 : _toDouble(map['conversion_qty']),
        isBase: _toStr(map['is_base']) == '1' || map['is_base'] == 1,
      ));
    }

    if (_units.isEmpty) {
      final productUom = _toStr(widget.product['uom']).trim().isEmpty
          ? 'PCS'
          : _toStr(widget.product['uom']).trim().toUpperCase();
      _units.add(_ProductUnitDraft(unitName: productUom, barcode: '', conversionQty: 1, isBase: true));
    }

    final hasBase = _units.any((u) => u.isBase);
    if (!hasBase) {
      _units.insert(0, _ProductUnitDraft(unitName: 'PCS', barcode: '', conversionQty: 1, isBase: true));
    }

    setState(() => _loading = false);
  }

  void _addBoxUnit() {
    setState(() {
      _units.add(_ProductUnitDraft(unitName: 'BOX', barcode: '', conversionQty: 1, isBase: false));
    });
  }

  void _removeUnit(int index) {
    if (_units[index].isBase) return;
    setState(() {
      final removed = _units.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final names = <String>{};
    for (final unit in _units) {
      final name = unit.unitNameCtrl.text.trim().toUpperCase();
      if (names.contains(name)) {
        setState(() => _error = 'Duplicate unit name: $name');
        return;
      }
      names.add(name);
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await DBService.instance.saveProductUnits(
      productCode: _productCode,
      units: _units.map((u) => u.toJson()).toList(),
      performedBy: widget.currentUserId,
    );

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
    return Dialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
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
                          color: _green.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _green.withOpacity(0.4)),
                        ),
                        child: Icon(Icons.straighten_rounded, color: _green, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Manage UOM', style: TextStyle(color: _textHi, fontSize: 18, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text('$_productCode — $_description', style: TextStyle(color: _textLo, fontSize: 12), overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: _textLo),
                        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _blue.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _blue.withOpacity(0.20)),
                    ),
                    child: Text(
                      'Rule: product default UOM is PCS if blank. Inventory conversion still saves as PCS.',
                      style: TextStyle(color: _textLo, fontSize: 13),
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (_loading)
                    const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator()))
                  else ...[
                    Row(
                      children: [
                        Expanded(flex: 2, child: _Label('Unit')),
                        const SizedBox(width: 10),
                        Expanded(flex: 3, child: _Label('Barcode (optional)')),
                        const SizedBox(width: 10),
                        Expanded(flex: 2, child: _Label('PCS Equivalent')),
                        const SizedBox(width: 42),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._units.asMap().entries.map((entry) {
                      final index = entry.key;
                      final unit = entry.value;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: _Field(
                                controller: unit.unitNameCtrl,
                                hint: 'PCS / BOX',
                                icon: Icons.category_rounded,
                                readOnly: unit.isBase,
                                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 3,
                              child: _Field(
                                controller: unit.barcodeCtrl,
                                hint: 'Optional barcode',
                                icon: Icons.qr_code_rounded,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              flex: 2,
                              child: _Field(
                                controller: unit.conversionCtrl,
                                hint: '1',
                                icon: Icons.calculate_rounded,
                                readOnly: unit.isBase,
                                validator: (v) {
                                  if (v == null || v.trim().isEmpty) return 'Required';
                                  final n = double.tryParse(v.trim());
                                  if (n == null || n <= 0) return 'Invalid';
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 32,
                              child: unit.isBase
                                  ? Icon(Icons.lock_rounded, color: _textLo, size: 18)
                                  : _IconBtn(
                                icon: Icons.close_rounded,
                                color: _red,
                                tooltip: 'Remove',
                                onTap: () => _removeUnit(index),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                      onPressed: _saving ? null : _addBoxUnit,
                      icon: Icon(Icons.add_rounded, color: _green, size: 18),
                      label: Text('Add Unit / BOX', style: TextStyle(color: _green, fontWeight: FontWeight.w600)),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 16),
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
                          Expanded(child: Text(_error!, style: TextStyle(color: _red, fontSize: 13))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: _border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                          child: Text('Cancel', style: TextStyle(color: _textLo)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _green,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: (_saving || _loading) ? null : _save,
                          child: _saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Save UOM', style: TextStyle(fontWeight: FontWeight.w600)),
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
}
class _ProductFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final List<String> categories;
  final int currentUserId;

  const _ProductFormDialog({
    this.existing,
    required this.categories,
    required this.currentUserId,
  });

  @override
  State<_ProductFormDialog> createState() => _ProductFormDialogState();
}


class _ProductFormDialogState extends State<_ProductFormDialog> {
  final _formKey = GlobalKey<FormState>();

  String _toStr(dynamic v) => v?.toString() ?? '';

  double _toDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  late final _codeCtrl = TextEditingController(text: _toStr(widget.existing?['product_code']));
  late final _uomCtrl = TextEditingController(
    text: _toStr(widget.existing?['uom']).trim().isEmpty
        ? 'PCS'
        : _toStr(widget.existing?['uom']).trim().toUpperCase(),
  );
  late final _descCtrl = TextEditingController(text: _cleanItemName(widget.existing?['item_description']));
  late final _priceCtrl = TextEditingController(
    text: _toDouble(widget.existing?['unit_price']).toStringAsFixed(2),
  );

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;
  late final String _originalCode = _toStr(widget.existing?['product_code']);

  @override
  void dispose() {
    _codeCtrl.dispose();
    _uomCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  String _cleanItemName(dynamic value) {
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
  }
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final uom = _uomCtrl.text.trim().isEmpty ? 'PCS' : _uomCtrl.text.trim().toUpperCase();

    setState(() {
      _saving = true;
      _error = null;
    });

    DBResult result;
    if (_isEdit) {
      result = await DBService.instance.updateProduct(
        productCode: _originalCode,
        newProductCode: _codeCtrl.text.trim().toUpperCase(),
        uom: uom,
        description: _descCtrl.text.trim(),
        unitPrice: double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
        performedBy: widget.currentUserId,
      );
    } else {
      result = await DBService.instance.createProduct(
        productCode: _codeCtrl.text.trim().toUpperCase(),
        uom: uom,
        description: _descCtrl.text.trim(),
        unitPrice: double.tryParse(_priceCtrl.text.trim()) ?? 0.0,
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
    return Dialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
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
                          color: _blue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _blue.withOpacity(0.4)),
                        ),
                        child: Icon(Icons.inventory_2_rounded, color: _blue, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isEdit ? 'Edit Product' : 'New Product',
                        style: TextStyle(color: _textHi, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: _textLo),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _Label('Product Code / SKU *'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _codeCtrl,
                    hint: 'e.g. 20001',
                    icon: Icons.qr_code_rounded,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  _Label('UOM'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _uomCtrl,
                    hint: 'PCS',
                    icon: Icons.straighten_rounded,
                    validator: (_) => null,
                  ),
                  const SizedBox(height: 16),
                  _Label('Item Description *'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _descCtrl,
                    hint: 'e.g. 555 SARDINES Green 155GRMS',
                    icon: Icons.label_outline_rounded,
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  _Label('Selling Price / SRP *'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _priceCtrl,
                    hint: '0.00',
                    icon: Icons.price_change_outlined,
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Required';
                      if (double.tryParse(v.trim()) == null) return 'Enter a valid number';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
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
                          Expanded(child: Text(_error!, style: TextStyle(color: _red, fontSize: 13))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: _border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                          child: Text('Cancel', style: TextStyle(color: _textLo)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _blue,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _saving ? null : _submit,
                          child: _saving
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                              : Text(
                            _isEdit ? 'Save Changes' : 'Create Product',
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
}

// ── Pending row & card ─────────────────────────────────────────────────────
class _PendingTableRow extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onAssign;

  const _PendingTableRow({required this.item, required this.onAssign});

  String _s(dynamic v) => v?.toString() ?? '';
  double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  int _i(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  String _dateOnly(String raw) =>
      raw.length >= 10 ? raw.substring(0, 10) : raw;

  String _location() {
    final s = _s(item['store_name']);
    final w = _s(item['warehouse_name']);
    if (s.isNotEmpty && w.isNotEmpty) return '$w / $s';
    if (s.isNotEmpty) return s;
    if (w.isNotEmpty) return w;
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    final price = _d(item['unit_price']);
    final whQty = _i(item['warehouse_qty']);
    final storeQty = _i(item['store_qty']);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              cleanItemName(item['item_description']),
              style: TextStyle(color: _textHi, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '₱${price.toStringAsFixed(2)}',
              style: TextStyle(
                  color: _amber, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$whQty',
              style: TextStyle(color: _teal, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '$storeQty',
              style: TextStyle(color: _green, fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _location(),
              style: TextStyle(color: _textLo, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              _dateOnly(_s(item['imported_at'])),
              style: TextStyle(color: _textLo, fontSize: 12),
            ),
          ),
          SizedBox(
            width: 110,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _blue,
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onAssign,
              icon: const Icon(Icons.check_rounded, size: 14),
              label: const Text('Assign',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _PendingCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onAssign;

  const _PendingCard({required this.item, required this.onAssign});

  String _s(dynamic v) => v?.toString() ?? '';
  double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  int _i(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final desc = cleanItemName(item['item_description']);
    final price = _d(item['unit_price']);
    final whQty = _i(item['warehouse_qty']);
    final storeQty = _i(item['store_qty']);
    final store = _s(item['store_name']);
    final warehouse = _s(item['warehouse_name']);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _amber.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _amber.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _amber.withOpacity(0.4)),
                ),
                child: Text(
                  'PENDING',
                  style: TextStyle(
                      color: _amber,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: onAssign,
                icon: const Icon(Icons.check_rounded, size: 14),
                label: const Text('Assign',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(desc,
              style: TextStyle(
                  color: _textHi, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _kv('Price', '₱${price.toStringAsFixed(2)}', _amber),
              _kv('Warehouse Qty', '$whQty', _teal),
              _kv('Store Qty', '$storeQty', _green),
              if (warehouse.isNotEmpty) _kv('Warehouse', warehouse, _textLo),
              if (store.isNotEmpty) _kv('Store', store, _textLo),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kv(String label, String value, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label: ',
          style: TextStyle(color: _textLo, fontSize: 11)),
      Text(value,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ],
  );
}

// ── Assign Pending Dialog ──────────────────────────────────────────────────
class _AssignPendingDialog extends StatefulWidget {
  final Map<String, dynamic> item;

  const _AssignPendingDialog({required this.item});

  @override
  State<_AssignPendingDialog> createState() => _AssignPendingDialogState();
}

class _AssignPendingDialogState extends State<_AssignPendingDialog> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtrl = TextEditingController();

  bool _generating = false;
  bool _saving = false;
  String? _error;

  String _s(dynamic v) => v?.toString() ?? '';
  double _d(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

  int _i(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _generate() async {
    setState(() {
      _generating = true;
      _error = null;
    });

    final result = await DBService.instance.generatePendingCode();

    if (!mounted) return;

    setState(() => _generating = false);

    if (result.success) {
      final code = _s(result.data?['code']);
      _codeCtrl.text = code;
    } else {
      setState(() => _error = result.message);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final pendingId = _i(widget.item['pending_id']);
    final code = _codeCtrl.text.trim();

    if (pendingId <= 0) {
      setState(() => _error = 'Invalid pending item.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = await DBService.instance.assignPendingItem(
      pendingId: pendingId,
      productCode: code,
    );

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
    final desc = cleanItemName(widget.item['item_description']);
    final price = _d(widget.item['unit_price']);
    final whQty = _i(widget.item['warehouse_qty']);
    final storeQty = _i(widget.item['store_qty']);
    final store = _s(widget.item['store_name']);
    final warehouse = _s(widget.item['warehouse_name']);

    return Dialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
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
                          color: _amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _amber.withOpacity(0.4)),
                        ),
                        child: Icon(Icons.pending_actions_rounded,
                            color: _amber, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Assign SKU',
                        style: TextStyle(
                            color: _textHi,
                            fontSize: 18,
                            fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: _textLo),
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(desc,
                            style: TextStyle(
                                color: _textHi,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 14,
                          runSpacing: 4,
                          children: [
                            _kv('Price', '₱${price.toStringAsFixed(2)}', _amber),
                            _kv('Warehouse Qty', '$whQty', _teal),
                            _kv('Store Qty', '$storeQty', _green),
                            if (warehouse.isNotEmpty)
                              _kv('Warehouse', warehouse, _textLo),
                            if (store.isNotEmpty) _kv('Store', store, _textLo),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _Label('Product Code / SKU *'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _Field(
                          controller: _codeCtrl,
                          hint: 'Type SKU or click Generate',
                          icon: Icons.qr_code_rounded,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Required';
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _green,
                          side: BorderSide(color: _green.withOpacity(0.4)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed:
                        (_generating || _saving) ? null : _generate,
                        icon: _generating
                            ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2),
                        )
                            : const Icon(Icons.autorenew_rounded, size: 16),
                        label: const Text('Generate'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Generate uses the homemade EAN-13 range (000000046XXX). '
                        'You can also type any code manually.',
                    style: TextStyle(color: _textLo, fontSize: 11),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
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
                            child: Text(_error!,
                                style: TextStyle(color: _red, fontSize: 13)),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: _border),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child:
                          Text('Cancel', style: TextStyle(color: _textLo)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _blue,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          onPressed: _saving ? null : _submit,
                          child: _saving
                              ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                              : const Text('Assign & Create Product',
                              style:
                              TextStyle(fontWeight: FontWeight.w600)),
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

  Widget _kv(String label, String value, Color color) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label: ', style: TextStyle(color: _textLo, fontSize: 11)),
      Text(value,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    ],
  );
}

// ─── Everything below is your existing widgets, kept as-is ─────────────────
// (_TableRow, _ProductCard, _ProductFormDialog, _ProductUnitsDialog,
//  _ProductUnitDraft, _MiniStat, _SearchBar, _Field, _TH, _Label, _IconBtn,
//  _ConfirmDialog, _PageTab, _PageNavButton, _ErrorView)
//
// They don't need any changes. Just keep them where they were.
//
// Two small additions to paste alongside them:

class _PaginationBar extends StatelessWidget {
  final int filteredCount;
  final int currentPage;
  final int totalPages;
  final int itemsPerPage;
  final List<int> pageSizeOptions;
  final List<dynamic> visiblePages;
  final ValueChanged<int> onPageTap;
  final ValueChanged<int> onSizeChanged;

  const _PaginationBar({
    required this.filteredCount,
    required this.currentPage,
    required this.totalPages,
    required this.itemsPerPage,
    required this.pageSizeOptions,
    required this.visiblePages,
    required this.onPageTap,
    required this.onSizeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Top row: total count + page size dropdown
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Total: $filteredCount',
                  style: TextStyle(color: _textHi, fontSize: 13)),
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
                  style: TextStyle(color: _textHi, fontSize: 13),
                  items: pageSizeOptions
                      .map((size) => DropdownMenuItem<int>(
                      value: size, child: Text('$size')))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) onSizeChanged(v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Bottom row: prev + page buttons + next
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
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
                      child: Text('...',
                          style: TextStyle(color: _textLo, fontSize: 14)),
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
          ),
        ],
      ),
    );
  }
}

// ── Small widgets ─────────────────────────────────────────────────────────
class _PageNavButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PageNavButton({required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
}
class _CountBadge extends StatelessWidget {
  final int count;
  final Color color;
  const _CountBadge({required this.count, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: color.withOpacity(0.15),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      '$count',
      style: TextStyle(
          color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const _SearchBar({required this.onChanged, required String hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      style: TextStyle(color: _textHi, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search code, UOM, or description…',
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
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool readOnly;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.readOnly = false,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      validator: validator,
      style: TextStyle(color: readOnly ? _textLo : _textHi, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: _textLo, fontSize: 13),
        prefixIcon: Icon(icon, color: _textLo, size: 18),
        filled: true,
        fillColor: readOnly ? Colors.white.withOpacity(0.02) : Colors.white.withOpacity(0.04),
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
}

class _TH extends StatelessWidget {
  final String text;
  const _TH(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: _textLo,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(color: _textLo, fontSize: 12, fontWeight: FontWeight.w500));
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
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
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(title, style: TextStyle(color: _textHi, fontWeight: FontWeight.w700)),
      content: Text(message, style: TextStyle(color: _textLo, fontSize: 13)),
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
}

class _PageTab extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _PageTab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
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
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: _textLo, size: 48),
            const SizedBox(height: 16),
            Text(message, style: TextStyle(color: _textLo, fontSize: 13), textAlign: TextAlign.center),
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
}

class _SortControl extends StatelessWidget {
  final String sortBy;
  final String sortDir;
  final void Function(String by, String dir) onChanged;
  final List<Map<String, Object>> options;

  const _SortControl({
    required this.sortBy,
    required this.sortDir,
    required this.onChanged,
    this.options = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: sortBy.isNotEmpty ? _blue.withOpacity(0.10) : _surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: sortBy.isNotEmpty ? _blue.withOpacity(0.4) : _border,
            ),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: sortBy.isEmpty ? null : sortBy,
              hint: Row(
                children: [
                  Icon(Icons.sort_rounded, color: _textLo, size: 15),
                  const SizedBox(width: 6),
                  Text(
                    'Sort by',
                    style: TextStyle(color: _textLo, fontSize: 12),
                  ),
                ],
              ),
              dropdownColor: _surface,
              icon: Icon(
                Icons.keyboard_arrow_down_rounded,
                color: _textLo,
                size: 16,
              ),
              style: TextStyle(color: _textHi, fontSize: 12),
              items: [
                DropdownMenuItem<String>(
                  value: '',
                  child: Row(
                    children: [
                      Icon(Icons.clear_rounded, color: _red, size: 15),
                      const SizedBox(width: 8),
                      Text(
                        'None',
                        style: TextStyle(color: _red, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                ...options.map((opt) {
                  final val = opt['value'] as String;
                  final lbl = opt['label'] as String;
                  final ico = opt['icon'] as IconData;
                  final isActive = sortBy == val;
                  return DropdownMenuItem<String>(
                    value: val,
                    child: Row(
                      children: [
                        Icon(
                          ico,
                          color: isActive ? _blue : _textLo,
                          size: 15,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          lbl,
                          style: TextStyle(
                            color: isActive ? _blue : _textHi,
                            fontSize: 12,
                            fontWeight: isActive
                                ? FontWeight.w700
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              onChanged: (val) {
                if (val == null) return;
                onChanged(val, sortDir);
              },
            ),
          ),
        ),

        if (sortBy.isNotEmpty) ...[
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () =>
                onChanged(sortBy, sortDir == 'asc' ? 'desc' : 'asc'),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _blue.withOpacity(0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _blue.withOpacity(0.4)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    sortDir == 'asc'
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    color: _blue,
                    size: 15,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    sortDir == 'asc' ? 'Asc' : 'Desc',
                    style: TextStyle(
                      color: _blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
