import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'dart:io';

import '../db/DBResult.dart';
import '../Utils/app_theme.dart';
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

String _money(dynamic v) => '₱${_toDouble(v).toStringAsFixed(2)}';

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

String _dateOnly(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// ─────────────────────────────────────────────────────────────────────────
//  Status helpers — single source of truth for labels, icons, and colours
// ─────────────────────────────────────────────────────────────────────────

/// Returns the "effective" status string to display in the UI.
/// Prefers `effective_status` (computed by the server), falls back to
/// a client-side evaluation of the raw `status` + `date_to`.
String _resolveStatus(Map<String, dynamic> promo) {
  // Server already computed it → trust it
  final effective = promo['effective_status']?.toString().trim().toUpperCase();
  if (effective != null && effective.isNotEmpty) return effective;

  // Fallback: client-side heuristics
  final raw = (promo['status'] ?? '').toString().trim().toUpperCase();
  if (raw == 'CANCELLED') return 'CANCELLED';

  final dateTo = promo['date_to']?.toString() ?? '';
  if (dateTo.isNotEmpty) {
    final parsed = DateTime.tryParse(dateTo);
    if (parsed != null && parsed.isBefore(DateTime.now().subtract(const Duration(days: 0)))) {
      // date_to is in the past
      if (DateTime.now().isAfter(parsed)) return 'EXPIRED';
    }
  }

  if (raw == 'INACTIVE') return 'INACTIVE';
  if (raw == 'EXPIRED') return 'EXPIRED';
  if (raw == 'OUT_OF_STOCK') return 'OUT_OF_STOCK';
  return 'ACTIVE';
}

/// Chip colour + icon for each status value.
({Color color, IconData icon, String label}) _statusStyle(String status) {
  switch (status) {
    case 'CANCELLED':
      return (color: const Color(0xFF9E9E9E), icon: Icons.cancel_rounded, label: 'Cancelled');
    case 'EXPIRED':
      return (color: const Color(0xFFEF5350), icon: Icons.event_busy_rounded, label: 'Expired');
    case 'OUT_OF_STOCK':
      return (color: const Color(0xFFFF7043), icon: Icons.inventory_2_rounded, label: 'Out of Stock');
    case 'INACTIVE':
      return (color: const Color(0xFFFFB300), icon: Icons.pause_circle_rounded, label: 'Inactive');
    case 'ACTIVE':
    default:
      return (color: const Color(0xFF4CAF50), icon: Icons.check_circle_rounded, label: 'Active');
  }
}

/// Same for item-level status.
({Color color, String label}) _itemStatusStyle(String status) {
  switch (status) {
    case 'OUT_OF_STOCK':
      return (color: const Color(0xFFFF7043), label: 'OUT OF STOCK');
    default:
      return (color: const Color(0xFF4CAF50), label: 'AVAILABLE');
  }
}

class PromoManagementScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;
  const PromoManagementScreen({super.key, this.currentUser});

  @override
  State<PromoManagementScreen> createState() => _PromoManagementScreenState();
}

class _PromoManagementScreenState extends State<PromoManagementScreen> {
  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _promos = [];
  List<Map<String, dynamic>> _suppliers = [];
  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _calculationTypes = [];
  List<Map<String, dynamic>> _allDeliveries = [];

  // ── Filters
  String _search = '';
  String _status = 'ALL';
  int _supplierId = 0;
  int _storeId = 0;

  // ── Pagination
  int _itemsPerPage = 10;
  int _currentPage = 1;
  final List<int> _pageSizeOptions = const [10, 20, 50, 100];

  int _safeDropdownValue(int current, List<int> validIds, {int fallback = 0}) {
    if (current == fallback) return fallback;
    return validIds.contains(current) ? current : fallback;
  }

  int _serverTotal = 0;

  final _searchCtrl = TextEditingController();

  /// Status options shown in filters — includes OUT_OF_STOCK for querying
  static const _statuses = ['ALL', 'ACTIVE', 'INACTIVE', 'EXPIRED', 'CANCELLED', 'OUT_OF_STOCK'];

  bool get _isWindows {
    try { return !kIsWeb && Platform.isWindows; } catch (_) { return false; }
  }

  int get _currentUserId => _toInt(widget.currentUser?['user_id']);

  List<Map<String, dynamic>> get _permissions {
    final rawAdmin = widget.currentUser?['admin_modules'];
    final rawAll = widget.currentUser?['permissions'];
    final raw = rawAdmin is List ? rawAdmin : rawAll;
    return (raw as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
  }

  bool hasPermission(String moduleName) {
    return _permissions.any((p) {
      final name = p['module_name']?.toString().trim().toUpperCase() ?? '';
      final canAccess = p['can_access'] == true || p['can_access'] == 1 || p['can_access'].toString() == '1';
      return name == moduleName.trim().toUpperCase() && canAccess;
    });
  }

  bool get canView => hasPermission('PROMOS') || hasPermission('PROMO_VIEW');
  bool get canCreate => hasPermission('PROMOS') || hasPermission('PROMO_CREATE');
  bool get canEdit => hasPermission('PROMOS') || hasPermission('PROMO_EDIT');
  bool get canDelete => hasPermission('PROMOS') || hasPermission('PROMO_DELETE');

  @override
  void initState() {
    super.initState();
    _loadRefs();
    _loadPromos();
  }

  Future<void> _loadRefs() async {
    final result = await DBService.instance.fetchPromoRefs();
    if (!mounted) return;
    if (result.success) {
      final data = result.data ?? {};
      setState(() {
        _suppliers = (data['suppliers'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        _stores = (data['stores'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        _calculationTypes = (data['calculation_types'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        _allDeliveries = (data['deliveries'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        if (_calculationTypes.isEmpty) {
          _calculationTypes = [
            {'calculation_type_id': 1, 'calculation_code': 'PRICE_OVERRIDE', 'calculation_name': 'Promo Price'},
            {'calculation_type_id': 2, 'calculation_code': 'FREE_ITEM', 'calculation_name': 'Buy X Take Y'},
          ];
        }
      });
    }
  }

  Future<void> _loadPromos() async {
    if (!canView) {
      setState(() { _loading = false; _error = 'You do not have permission to view promos.'; });
      return;
    }

    setState(() { _loading = true; _error = null; });

    final result = await DBService.instance.fetchPromos(
      search: _search,
      status: _status == 'ALL' ? '' : _status,
      supplierId: _supplierId,
      storeId: _storeId,
      page: 1,
      limit: 1000,
    );

    if (!mounted) return;

    if (result.success) {
      final data = result.data ?? {};
      final pagination = Map<String, dynamic>.from(data['pagination'] as Map? ?? {});
      setState(() {
        _promos = (data['promos'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        _serverTotal = _toInt(pagination['total']);
        _currentPage = 1;
        _loading = false;
      });
    } else {
      setState(() { _loading = false; _error = result.message; });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    final q = _search.trim().toLowerCase();
    return _promos.where((p) {
      if (q.isEmpty) return true;
      final no = (p['promo_no'] ?? '').toString().toLowerCase();
      final name = (p['promo_name'] ?? '').toString().toLowerCase();
      final supplier = (p['supplier_name'] ?? '').toString().toLowerCase();
      return no.contains(q) || name.contains(q) || supplier.contains(q);
    }).toList();
  }

  int get _totalPages {
    final total = _filtered.length;
    if (total == 0) return 1;
    return (total / _itemsPerPage).ceil();
  }

  List<Map<String, dynamic>> get _pagedPromos {
    final list = _filtered;
    final start = (_currentPage - 1) * _itemsPerPage;
    if (start >= list.length) return [];
    final end = (start + _itemsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  void _goToPage(int page) => setState(() => _currentPage = page.clamp(1, _totalPages));

  List<dynamic> _visiblePageItems() {
    final total = _totalPages;
    final current = _currentPage;
    if (total <= 7) return List<int>.generate(total, (i) => i + 1);
    final items = <dynamic>[1];
    if (current > 3) items.add('...');
    final start = current <= 3 ? 2 : current - 1;
    final end = current >= total - 2 ? total - 1 : current + 1;
    for (int i = start; i <= end; i++) { if (i > 1 && i < total) items.add(i); }
    if (current < total - 2) items.add('...');
    items.add(total);
    return items;
  }

  void _onSearchChanged(String value) => setState(() { _search = value; _currentPage = 1; });

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? _red : _green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator(color: _blue));
    if (_error != null) return _ErrorView(message: _error!, onRetry: _loadPromos);

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          _header(),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Promo Management',
                    style: TextStyle(color: _textHi, fontSize: 24, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  'Create supplier/vendor promos. Link to a delivery to bound the promo stock automatically.',
                  style: TextStyle(color: _textLo, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: Icon(Icons.refresh_rounded, color: _textLo),
            onPressed: _loadPromos,
          ),
          const SizedBox(width: 8),
          if (canCreate)
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              onPressed: () => _showPromoDialog(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New Promo'),
            ),
        ],
      ),
    );
  }

  Widget _content() {
    return RefreshIndicator(
      color: _blue,
      backgroundColor: _surface,
      onRefresh: _loadPromos,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _filters()),
          SliverToBoxAdapter(child: _stats()),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          _isWindows ? _buildTable() : _buildCards(),
          SliverToBoxAdapter(child: _pagination()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _filters() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            style: TextStyle(color: _textHi, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search promo no, name, or supplier…',
              hintStyle: TextStyle(color: _textLo, fontSize: 13),
              prefixIcon: Icon(Icons.search_rounded, color: _textLo, size: 20),
              filled: true,
              fillColor: _surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _blue, width: 1.5)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
            onChanged: _onSearchChanged,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: _FilterDropdown<String>(
                  value: _status,
                  label: 'Status',
                  icon: Icons.flag_rounded,
                  items: _statuses.map((s) {
                    if (s == 'ALL') return const DropdownMenuItem(value: 'ALL', child: Text('All Statuses'));
                    final style = _statusStyle(s);
                    return DropdownMenuItem(
                      value: s,
                      child: Row(children: [
                        Icon(style.icon, size: 14, color: style.color),
                        const SizedBox(width: 6),
                        Text(style.label),
                      ]),
                    );
                  }).toList(),
                  onChanged: (v) {
                    setState(() { _status = v ?? 'ALL'; _currentPage = 1; });
                    _loadPromos();
                  },
                ),
              ),
              SizedBox(
                width: 230,
                child: _FilterDropdown<int>(
                  value: _supplierId,
                  label: 'Supplier',
                  icon: Icons.business_rounded,
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('All Suppliers')),
                    ..._suppliers.map((s) => DropdownMenuItem(
                      value: _toInt(s['supplier_id']),
                      child: Text(s['supplier_name']?.toString() ?? 'Supplier', overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (v) {
                    setState(() { _supplierId = v ?? 0; _currentPage = 1; });
                    _loadPromos();
                  },
                ),
              ),
              SizedBox(
                width: 210,
                child: _FilterDropdown<int>(
                  value: _storeId,
                  label: 'Store',
                  icon: Icons.store_rounded,
                  items: [
                    const DropdownMenuItem(value: 0, child: Text('All Stores')),
                    ..._stores.map((s) => DropdownMenuItem(
                      value: _toInt(s['store_id']),
                      child: Text(s['store_name']?.toString() ?? 'Store', overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (v) {
                    setState(() { _storeId = v ?? 0; _currentPage = 1; });
                    _loadPromos();
                  },
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: _border),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() { _search = ''; _status = 'ALL'; _supplierId = 0; _storeId = 0; _currentPage = 1; });
                  _loadPromos();
                },
                icon: Icon(Icons.restart_alt_rounded, size: 18, color: _textLo),
                label: Text('Reset', style: TextStyle(color: _textLo)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stats() {
    final total    = _promos.length;
    final filtered = _filtered.length;
    final showing  = _pagedPromos.length;
    final active   = _promos.where((p) => _resolveStatus(p) == 'ACTIVE').length;
    final expired  = _promos.where((p) => _resolveStatus(p) == 'EXPIRED').length;
    final oos      = _promos.where((p) => _resolveStatus(p) == 'OUT_OF_STOCK').length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MiniStat(label: 'Total', value: '$total', color: _blue),
          _MiniStat(label: 'Active', value: '$active', color: _green),
          if (expired > 0) _MiniStat(label: 'Expired', value: '$expired', color: _red),
          if (oos > 0)     _MiniStat(label: 'Out of Stock', value: '$oos', color: const Color(0xFFFF7043)),
          _MiniStat(label: 'Filtered', value: '$filtered', color: _teal),
          _MiniStat(label: 'Page', value: '$_currentPage / $_totalPages', color: _green),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final list = _pagedPromos;
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
                child: Row(children: const [
                  Expanded(flex: 2, child: _TH('PROMO NO')),
                  Expanded(flex: 4, child: _TH('NAME')),
                  Expanded(flex: 3, child: _TH('SUPPLIER')),
                  Expanded(flex: 2, child: _TH('DELIVERY')),
                  Expanded(flex: 3, child: _TH('STORE')),
                  Expanded(flex: 2, child: _TH('TYPE')),
                  Expanded(flex: 3, child: _TH('DATES')),
                  SizedBox(width: 60, child: _TH('ITEMS')),
                  SizedBox(width: 120, child: _TH('STATUS')),
                  SizedBox(width: 84, child: _TH('ACTIONS')),
                ]),
              ),
              Divider(height: 1, color: _border),
              if (list.isEmpty)
                Padding(padding: const EdgeInsets.all(32), child: Text('No promos found', style: TextStyle(color: _textLo)))
              else
                ...list.asMap().entries.map((e) {
                  final idx = e.key;
                  final p   = e.value;
                  return Column(children: [
                    if (idx > 0) Divider(height: 1, color: _border),
                    _PromoTableRow(
                      promo: p,
                      canEdit: canEdit,
                      canDelete: canDelete,
                      onEdit: () => _openExistingPromo(p, edit: canEdit),
                      onCancel: () => _cancelPromo(p),
                    ),
                  ]);
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCards() {
    final list = _pagedPromos;
    if (list.isEmpty) {
      return SliverFillRemaining(
        child: Center(child: Text('No promos found', style: TextStyle(color: _textLo))),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          final p = list[index];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _PromoCard(
              promo: p,
              canEdit: canEdit,
              canDelete: canDelete,
              onEdit: () => _openExistingPromo(p, edit: canEdit),
              onCancel: () => _cancelPromo(p),
            ),
          );
        },
        childCount: list.length,
      ),
    );
  }

  Widget _pagination() {
    if (_filtered.isEmpty) return const SizedBox.shrink();
    final items = _visiblePageItems();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('Total: ${_filtered.length}', style: TextStyle(color: _textHi, fontSize: 14)),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
            child: DropdownButton<int>(
              value: _itemsPerPage,
              underline: const SizedBox(),
              dropdownColor: _surface,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: _textLo),
              style: TextStyle(color: _textHi, fontSize: 14),
              items: _pageSizeOptions.map((size) => DropdownMenuItem<int>(value: size, child: Text('$size'))).toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() { _itemsPerPage = value; _currentPage = 1; });
              },
            ),
          ),
          const SizedBox(width: 16),
          _PageNavButton(label: '<', enabled: _currentPage > 1, onTap: () => _goToPage(_currentPage - 1)),
          const SizedBox(width: 6),
          ...items.map((item) {
            if (item == '...') {
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('...', style: TextStyle(color: _textLo, fontSize: 14)),
              );
            }
            final page = item as int;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _PageTab(label: '$page', active: page == _currentPage, onTap: () => _goToPage(page)),
            );
          }),
          _PageNavButton(label: '>', enabled: _currentPage < _totalPages, onTap: () => _goToPage(_currentPage + 1)),
        ],
      ),
    );
  }

  // ── Dialog helpers ───────────────────────────────────────────────────────
  Future<void> _openExistingPromo(Map<String, dynamic> promo, {required bool edit}) async {
    final id = _toInt(promo['promo_id']);
    final result = await DBService.instance.fetchPromoDetail(promoId: id);
    if (!mounted) return;
    if (!result.success) { _snack(result.message, error: true); return; }
    final data = result.data ?? {};
    final detail = Map<String, dynamic>.from(data['promo'] as Map? ?? {});
    _showPromoDialog(existing: detail, readOnly: !edit);
  }

  Future<void> _cancelPromo(Map<String, dynamic> promo) async {
    final effectiveStatus = _resolveStatus(promo);
    if (effectiveStatus == 'CANCELLED') {
      _snack('This promo is already cancelled.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Cancel Promo', style: TextStyle(color: _textHi)),
        content: Text(
          'Cancel ${promo['promo_no']}? This will stop it from applying to scans.',
          style: TextStyle(color: _textLo),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel Promo'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final result = await DBService.instance.cancelPromo(promoId: _toInt(promo['promo_id']), userId: _currentUserId);
    if (result.success) { _snack('Promo cancelled.'); _loadPromos(); }
    else { _snack(result.message, error: true); }
  }

  final itemControllers = <int, Map<String, TextEditingController>>{};

  Map<String, TextEditingController> _ctrlsFor(int i, Map<String, dynamic> it) {
    return itemControllers.putIfAbsent(i, () => {
      'promo':   TextEditingController(text: _toDouble(it['promo_price']) > 0 ? _toDouble(it['promo_price']).toStringAsFixed(2) : ''),
      'percent': TextEditingController(text: _toDouble(it['discount_percent']) > 0 ? _toDouble(it['discount_percent']).toStringAsFixed(2) : ''),
      'amount':  TextEditingController(text: _toDouble(it['discount_amount']) > 0 ? _toDouble(it['discount_amount']).toStringAsFixed(2) : ''),
      'buy':     TextEditingController(text: _toDouble(it['buy_qty']).toStringAsFixed(0)),
      'free':    TextEditingController(text: _toDouble(it['free_qty']).toStringAsFixed(0)),
      'limit':   TextEditingController(text: _toDouble(it['promo_qty_limit']) > 0 ? _toDouble(it['promo_qty_limit']).toStringAsFixed(0) : ''),
    });
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _textLo),
      prefixIcon: Icon(icon, color: _textLo, size: 19),
      filled: true,
      fillColor: _bg,
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: _blue)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }

  Future<void> _showPromoDialog({Map<String, dynamic>? existing, bool readOnly = false}) async {
    final isEdit = existing != null;
    final formKey = GlobalKey<FormState>();
    final nameCtrl    = TextEditingController(text: existing?['promo_name']?.toString() ?? '');
    final remarksCtrl = TextEditingController(text: existing?['remarks']?.toString() ?? '');

    int calculationTypeId = _toInt(existing?['calculation_type_id']);
    String calculationCode = existing?['calculation_code']?.toString() ??
        (existing?['promo_type']?.toString() == 'BUY_1_TAKE_1' ? 'FREE_ITEM' : 'PRICE_OVERRIDE');
    if (calculationTypeId == 0 && _calculationTypes.isNotEmpty) {
      final match = _calculationTypes.where((e) => e['calculation_code']?.toString() == calculationCode).toList();
      calculationTypeId = match.isNotEmpty ? _toInt(match.first['calculation_type_id']) : _toInt(_calculationTypes.first['calculation_type_id']);
      calculationCode   = match.isNotEmpty ? match.first['calculation_code']?.toString() ?? calculationCode : _calculationTypes.first['calculation_code']?.toString() ?? calculationCode;
    }

    // Use the raw DB status for the status dropdown (not effective_status)
    String status      = existing?['status']?.toString() ?? 'ACTIVE';
    int supplierId     = _toInt(existing?['supplier_id']);
    int deliveryId     = _toInt(existing?['delivery_id']);
    int storeId        = _toInt(existing?['store_id']);
    DateTime dateFrom  = DateTime.tryParse(existing?['date_from']?.toString() ?? '') ?? DateTime.now();
    DateTime dateTo    = DateTime.tryParse(existing?['date_to']?.toString() ?? '') ?? DateTime.now().add(const Duration(days: 7));
    List<Map<String, dynamic>> items = (existing?['items'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
    bool saving        = false;

    List<Map<String, dynamic>> deliveriesForSupplier = [];
    bool loadingDeliveries = false;

    Future<void> refreshDeliveries(int forSupplier, void Function(void Function()) setModalState) async {
      setModalState(() => loadingDeliveries = true);
      final result = await DBService.instance.fetchPromoDeliveries(supplierId: forSupplier);
      if (!mounted) return;
      if (result.success) {
        final data = result.data ?? {};
        final list = (data['deliveries'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        setModalState(() {
          deliveriesForSupplier = list;
          loadingDeliveries = false;
          if (deliveryId > 0 && !list.any((d) => _toInt(d['delivery_id']) == deliveryId)) deliveryId = 0;
        });
      } else {
        setModalState(() { deliveriesForSupplier = []; loadingDeliveries = false; });
      }
    }

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(builder: (context, setModalState) {
        if (supplierId > 0 && deliveriesForSupplier.isEmpty && !loadingDeliveries) {
          Future.microtask(() => refreshDeliveries(supplierId, setModalState));
        }

        Future<void> pickDate(bool from) async {
          final picked = await showDatePicker(
            context: context,
            initialDate: from ? dateFrom : dateTo,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
          );
          if (picked == null) return;
          setModalState(() {
            if (from) { dateFrom = picked; if (dateTo.isBefore(dateFrom)) dateTo = dateFrom; }
            else       { dateTo = picked; }
          });
        }

        Future<void> save() async {
          if (readOnly) return;
          if (!formKey.currentState!.validate()) return;
          if (items.isEmpty) { _snack('Add at least one promo item.', error: true); return; }
          setModalState(() => saving = true);
          final body = {
            if (isEdit) 'promo_id': existing['promo_id'],
            'promo_name':          nameCtrl.text.trim(),
            'calculation_type_id': calculationTypeId,
            'calculation_code':    calculationCode,
            'promo_type':          calculationCode == 'FREE_ITEM' ? 'BUY_1_TAKE_1' : 'PROMO_PRICE',
            'supplier_id':         supplierId == 0 ? null : supplierId,
            'delivery_id':         deliveryId == 0 ? null : deliveryId,
            'store_id':            storeId == 0 ? null : storeId,
            'date_from':           _dateOnly(dateFrom),
            'date_to':             _dateOnly(dateTo),
            'status':              status,
            'remarks':             remarksCtrl.text.trim(),
            'created_by':          _currentUserId,
            'items': items.map((it) => {
              'product_code':        it['product_code'],
              'original_unit_price': _toDouble(it['original_unit_price']),
              'promo_price':         calculationCode == 'PRICE_OVERRIDE' ? _toDouble(it['promo_price']) : it['promo_price'],
              'discount_percent':    calculationCode == 'PERCENT_OFF' ? _toDouble(it['discount_percent']) : null,
              'discount_amount':     calculationCode == 'AMOUNT_OFF' ? _toDouble(it['discount_amount']) : null,
              'buy_qty':             calculationCode == 'FREE_ITEM' ? _toDouble(it['buy_qty']) : 1,
              'free_qty':            calculationCode == 'FREE_ITEM' ? _toDouble(it['free_qty']) : 0,
              'promo_qty_limit':     it['promo_qty_limit'],
              'promo_qty_used':      it['promo_qty_used'] ?? 0,
              'item_remarks':        it['item_remarks'],
            }).toList(),
          };
          final result = isEdit ? await DBService.instance.updatePromo(body) : await DBService.instance.createPromo(body);
          if (!mounted) return;
          if (result.success) {
            Navigator.pop(context);
            _snack(isEdit ? 'Promo updated.' : 'Promo created.');
            _loadPromos();
          } else {
            setModalState(() => saving = false);
            _snack(result.message, error: true);
          }
        }

        final hasStockWarning = _toInt(existing?['stock_warning_count']) > 0;
        final effectiveStatusInDialog = existing != null ? _resolveStatus(existing) : 'ACTIVE';

        return Dialog(
          backgroundColor: _surface,
          insetPadding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
            child: Column(children: [
              // ── Dialog header ───────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                child: Row(children: [
                  Expanded(
                    child: Row(children: [
                      Text(
                        readOnly ? 'Promo Details' : (isEdit ? 'Edit Promo' : 'Create Promo'),
                        style: TextStyle(color: _textHi, fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                      if (existing != null) ...[
                        const SizedBox(width: 12),
                        _StatusChip(status: effectiveStatusInDialog),
                      ],
                    ]),
                  ),
                  IconButton(
                    onPressed: saving ? null : () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: _textLo),
                  ),
                ]),
              ),
              // ── Stock warning banner ────────────────────────────
              if (hasStockWarning)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.symmetric(horizontal: 20),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _amber.withOpacity(0.4)),
                  ),
                  child: Row(children: [
                    Icon(Icons.warning_amber_rounded, color: _amber, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${existing?['stock_warning_count']} item(s) in this promo no longer have stock from the linked delivery. The promo will not apply at POS for those items.',
                        style: TextStyle(color: _textHi, fontSize: 13),
                      ),
                    ),
                  ]),
                ),
              // ── Form ────────────────────────────────────────────
              Expanded(
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        SizedBox(
                          width: 310,
                          child: TextFormField(
                            controller: nameCtrl,
                            enabled: !readOnly,
                            style: TextStyle(color: _textHi),
                            decoration: _inputDecoration('Promo Name', Icons.local_offer_rounded),
                            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                          ),
                        ),
                        // Calculation type
                        SizedBox(
                          width: 230,
                          child: Builder(builder: (_) {
                            final ids = _calculationTypes.map((c) => _toInt(c['calculation_type_id'])).toSet();
                            final safeValue = ids.contains(calculationTypeId)
                                ? calculationTypeId
                                : (_calculationTypes.isNotEmpty ? _toInt(_calculationTypes.first['calculation_type_id']) : 0);
                            if (safeValue != calculationTypeId) {
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                setModalState(() {
                                  calculationTypeId = safeValue;
                                  final match = _calculationTypes.where((e) => _toInt(e['calculation_type_id']) == safeValue).toList();
                                  calculationCode = match.isNotEmpty ? match.first['calculation_code']?.toString() ?? 'PRICE_OVERRIDE' : 'PRICE_OVERRIDE';
                                });
                              });
                            }
                            return DropdownButtonFormField<int>(
                              value: _calculationTypes.isEmpty ? null : safeValue,
                              dropdownColor: _surface,
                              style: TextStyle(color: _textHi),
                              decoration: _inputDecoration('Calculation', Icons.calculate_rounded),
                              items: _calculationTypes.map((c) => DropdownMenuItem(
                                value: _toInt(c['calculation_type_id']),
                                child: Text(c['calculation_name']?.toString() ?? 'Promo'),
                              )).toList(),
                              onChanged: readOnly ? null : (v) => setModalState(() {
                                calculationTypeId = v ?? 0;
                                final match = _calculationTypes.where((e) => _toInt(e['calculation_type_id']) == calculationTypeId).toList();
                                calculationCode = match.isNotEmpty ? match.first['calculation_code']?.toString() ?? 'PRICE_OVERRIDE' : 'PRICE_OVERRIDE';
                              }),
                            );
                          }),
                        ),
                        // Supplier
                        SizedBox(
                          width: 230,
                          child: DropdownButtonFormField<int>(
                            value: _safeDropdownValue(supplierId, _suppliers.map((s) => _toInt(s['supplier_id'])).toList()),
                            dropdownColor: _surface,
                            style: TextStyle(color: _textHi),
                            decoration: _inputDecoration('Supplier', Icons.business_rounded),
                            items: [
                              const DropdownMenuItem(value: 0, child: Text('No Supplier')),
                              ..._suppliers.map((s) => DropdownMenuItem(value: _toInt(s['supplier_id']), child: Text(s['supplier_name']?.toString() ?? 'Supplier'))),
                            ],
                            onChanged: readOnly ? null : (v) {
                              setModalState(() { supplierId = v ?? 0; deliveryId = 0; deliveriesForSupplier = []; items.clear(); });
                              if (supplierId > 0) refreshDeliveries(supplierId, setModalState);
                            },
                          ),
                        ),
                        // Delivery
                        SizedBox(
                          width: 280,
                          child: DropdownButtonFormField<int>(
                            value: _safeDropdownValue(deliveryId, deliveriesForSupplier.map((d) => _toInt(d['delivery_id'])).toList()),
                            dropdownColor: _surface,
                            isExpanded: true,
                            style: TextStyle(color: _textHi),
                            decoration: _inputDecoration(
                              loadingDeliveries ? 'Loading deliveries…' : (supplierId == 0 ? 'Delivery (pick supplier first)' : 'Delivery (optional)'),
                              Icons.local_shipping_rounded,
                            ),
                            items: [
                              const DropdownMenuItem(value: 0, child: Text('No specific delivery')),
                              ...deliveriesForSupplier.map((d) => DropdownMenuItem(
                                value: _toInt(d['delivery_id']),
                                child: Text(d['label']?.toString() ?? d['po_number']?.toString() ?? 'Delivery', overflow: TextOverflow.ellipsis),
                              )),
                            ],
                            onChanged: (readOnly || supplierId == 0 || loadingDeliveries) ? null : (v) {
                              setModalState(() {
                                final newId = v ?? 0;
                                if (newId != deliveryId) items.clear();
                                deliveryId = newId;
                              });
                            },
                          ),
                        ),
                        // Store
                        SizedBox(
                          width: 210,
                          child: DropdownButtonFormField<int>(
                            value: _safeDropdownValue(storeId, _stores.map((s) => _toInt(s['store_id'])).toList()),
                            dropdownColor: _surface,
                            style: TextStyle(color: _textHi),
                            decoration: _inputDecoration('Store', Icons.store_rounded),
                            items: [
                              const DropdownMenuItem(value: 0, child: Text('All Stores')),
                              ..._stores.map((s) => DropdownMenuItem(value: _toInt(s['store_id']), child: Text(s['store_name']?.toString() ?? 'Store'))),
                            ],
                            onChanged: readOnly ? null : (v) => setModalState(() => storeId = v ?? 0),
                          ),
                        ),
                        SizedBox(width: 170, child: _dateBox('Date From', dateFrom, () => pickDate(true))),
                        SizedBox(width: 170, child: _dateBox('Date To', dateTo, () => pickDate(false))),
                        // Status dropdown — shows raw statuses for manual override
                        SizedBox(
                          width: 200,
                          child: DropdownButtonFormField<String>(
                            value: ['ACTIVE', 'INACTIVE', 'EXPIRED', 'CANCELLED', 'OUT_OF_STOCK'].contains(status) ? status : 'ACTIVE',
                            dropdownColor: _surface,
                            style: TextStyle(color: _textHi),
                            decoration: _inputDecoration('Status', Icons.flag_rounded),
                            items: ['ACTIVE', 'INACTIVE', 'EXPIRED', 'CANCELLED', 'OUT_OF_STOCK'].map((s) {
                              final style = _statusStyle(s);
                              return DropdownMenuItem(
                                value: s,
                                child: Row(children: [
                                  Icon(style.icon, size: 14, color: style.color),
                                  const SizedBox(width: 6),
                                  Text(style.label),
                                ]),
                              );
                            }).toList(),
                            onChanged: readOnly ? null : (v) => setModalState(() => status = v ?? 'ACTIVE'),
                          ),
                        ),
                      ]),
                      if (deliveryId > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: _teal.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.info_outline_rounded, color: _teal, size: 16),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Delivery-bound: product picker will only show items from this delivery, and promo auto-ends when the batch sells out.',
                                  style: TextStyle(color: _teal, fontSize: 12),
                                ),
                              ),
                            ]),
                          ),
                        ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: remarksCtrl,
                        enabled: !readOnly,
                        maxLines: 2,
                        style: TextStyle(color: _textHi),
                        decoration: _inputDecoration('Remarks', Icons.notes_rounded),
                      ),
                      const SizedBox(height: 20),
                      Row(children: [
                        Expanded(child: Text('Promo Items', style: TextStyle(color: _textHi, fontWeight: FontWeight.w800, fontSize: 16))),
                        if (!readOnly)
                          OutlinedButton.icon(
                            onPressed: () async {
                              final product = await _pickProduct(deliveryId: deliveryId);
                              if (product != null) {
                                if (items.any((e) => e['product_code'] == product['product_code'])) {
                                  _snack('Product already added.', error: true);
                                  return;
                                }
                                setModalState(() => items.add({
                                  'product_code':        product['product_code'],
                                  'item_description':    _cleanItemName(product['item_description']),
                                  'uom':                 product['uom'],
                                  'original_unit_price': product['unit_price'],
                                  'promo_price':         0.0,
                                  'discount_percent':    0.0,
                                  'discount_amount':     0.0,
                                  'buy_qty':             1.0,
                                  'free_qty':            1.0,
                                  'promo_qty_limit':     null,
                                  'promo_qty_used':      0.0,
                                  'item_remarks':        '',
                                  'delivery_remaining_qty': product['delivery_remaining_qty'],
                                }));
                              }
                            },
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add Item'),
                          ),
                      ]),
                      const SizedBox(height: 10),
                      if (items.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: _border)),
                          child: Text('No items added yet.', style: TextStyle(color: _textLo)),
                        )
                      else
                        ...List.generate(items.length, (i) => _itemEditor(
                          items, i, calculationCode, readOnly, setModalState,
                          isDeliveryBound: deliveryId > 0,
                        )),
                    ]),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: Text(readOnly ? 'Close' : 'Cancel')),
                  if (!readOnly) const SizedBox(width: 10),
                  if (!readOnly)
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _blue),
                      onPressed: saving ? null : save,
                      child: saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Text(isEdit ? 'Save Changes' : 'Create Promo'),
                    ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  Widget _dateBox(String label, DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: _inputDecoration(label, Icons.calendar_today_rounded),
        child: Text(_dateOnly(date), style: TextStyle(color: _textHi)),
      ),
    );
  }

  Widget _itemEditor(
      List<Map<String, dynamic>> items,
      int i,
      String calculationCode,
      bool readOnly,
      void Function(void Function()) setModalState, {
        bool isDeliveryBound = false,
      }) {
    final it   = items[i];
    final ctrls = _ctrlsFor(i, it);
    final usedQty       = _toDouble(it['promo_qty_used']);
    final batchRemaining = it['delivery_batch_remaining_qty'] ?? it['delivery_remaining_qty'];
    final isBatchExhausted = it['batch_exhausted'] == true ||
        (isDeliveryBound && _toDouble(batchRemaining) <= 0 && batchRemaining != null);

    // Item-level qty status
    final itemStatusStr = it['item_status']?.toString() ?? '';
    final isItemOOS = itemStatusStr == 'OUT_OF_STOCK' || (() {
      final limit = _toDouble(it['promo_qty_limit']);
      final used  = _toDouble(it['promo_qty_used']);
      return limit > 0 && used >= limit;
    })();

    final borderColor = isBatchExhausted || isItemOOS ? _red.withOpacity(0.5) : _border;
    final borderWidth = isBatchExhausted || isItemOOS ? 1.5 : 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor, width: borderWidth),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Text(
                  '${it['product_code']} — ${_cleanItemName(it['item_description'])}',
                  style: TextStyle(color: _textHi, fontWeight: FontWeight.w700),
                  softWrap: true,
                ),
              ),
              const SizedBox(width: 8),
              // Per-item status badge
              if (isItemOOS)
                _ItemStatusBadge(status: 'OUT_OF_STOCK')
              else if (isBatchExhausted)
                _ItemStatusBadge(status: 'BATCH_EMPTY'),
            ]),
            const SizedBox(height: 4),
            Text('SRP: ${_money(it['original_unit_price'])} • UOM: ${it['uom'] ?? 'PCS'}',
                style: TextStyle(color: _textLo, fontSize: 12)),
            if (isDeliveryBound && batchRemaining != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  'Delivery batch remaining: ${_toDouble(batchRemaining).toStringAsFixed(0)}',
                  style: TextStyle(
                    color: isBatchExhausted ? _red : _textLo,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ]),
        ),
        const SizedBox(width: 12),
        if (calculationCode == 'PRICE_OVERRIDE')
          SizedBox(
            width: 150,
            child: TextFormField(
              controller: ctrls['promo'],
              enabled: !readOnly,
              keyboardType: TextInputType.number,
              style: TextStyle(color: _textHi),
              decoration: _inputDecoration('Promo Price', Icons.price_change_rounded),
              onChanged: (v) => it['promo_price'] = _toDouble(v),
              validator: (v) {
                final price = _toDouble(v);
                if (price <= 0) return 'Required';
                if (price >= _toDouble(it['original_unit_price'])) return 'Lower than SRP';
                return null;
              },
            ),
          )
        else if (calculationCode == 'PERCENT_OFF')
          SizedBox(
            width: 150,
            child: TextFormField(
              controller: ctrls['percent'],
              enabled: !readOnly,
              keyboardType: TextInputType.number,
              style: TextStyle(color: _textHi),
              decoration: _inputDecoration('Discount %', Icons.percent_rounded),
              onChanged: (v) => it['discount_percent'] = _toDouble(v),
              validator: (v) { final n = _toDouble(v); if (n <= 0 || n >= 100) return '1-99 only'; return null; },
            ),
          )
        else if (calculationCode == 'AMOUNT_OFF')
            SizedBox(
              width: 150,
              child: TextFormField(
                controller: ctrls['amount'],
                enabled: !readOnly,
                keyboardType: TextInputType.number,
                style: TextStyle(color: _textHi),
                decoration: _inputDecoration('Less Amount', Icons.money_off_rounded),
                onChanged: (v) => it['discount_amount'] = _toDouble(v),
                validator: (v) {
                  final n = _toDouble(v);
                  if (n <= 0) return 'Required';
                  if (n >= _toDouble(it['original_unit_price'])) return 'Lower than SRP';
                  return null;
                },
              ),
            )
          else ...[
              SizedBox(
                width: 110,
                child: TextFormField(
                  controller: ctrls['buy'],
                  enabled: !readOnly,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: _textHi),
                  decoration: _inputDecoration('Buy Qty', Icons.shopping_cart_rounded),
                  onChanged: (v) => it['buy_qty'] = _toDouble(v),
                  validator: (v) => _toDouble(v) <= 0 ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 110,
                child: TextFormField(
                  controller: ctrls['free'],
                  enabled: !readOnly,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: _textHi),
                  decoration: _inputDecoration('Free Qty', Icons.card_giftcard_rounded),
                  onChanged: (v) => it['free_qty'] = _toDouble(v),
                  validator: (v) => _toDouble(v) <= 0 ? 'Required' : null,
                ),
              ),
            ],
        const SizedBox(width: 8),
        SizedBox(
          width: 140,
          child: TextFormField(
            controller: ctrls['limit'],
            enabled: !readOnly,
            keyboardType: TextInputType.number,
            style: TextStyle(color: _textHi),
            decoration: _inputDecoration('Promo Qty Limit', Icons.inventory_2_rounded),
            onChanged: (v) {
              final n = _toDouble(v);
              it['promo_qty_limit'] = n <= 0 ? null : n;
            },
            validator: (v) {
              if (v == null || v.trim().isEmpty) return null;
              final n = _toDouble(v);
              if (n <= 0) return 'Invalid';
              if (usedQty > 0 && n < usedQty) return 'Below used';
              return null;
            },
          ),
        ),
        if (usedQty > 0) ...[
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: Text(
              'Used: ${usedQty.toStringAsFixed(0)}',
              style: TextStyle(color: _textLo, fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (!readOnly)
          IconButton(
            onPressed: () => setModalState(() => items.removeAt(i)),
            icon: Icon(Icons.delete_rounded, color: _red),
          ),
      ]),
    );
  }

  Future<Map<String, dynamic>?> _pickProduct({int deliveryId = 0}) async {
    final ctrl = TextEditingController();
    List<Map<String, dynamic>> products = [];
    bool loading = false;

    Future<void> search(void Function(void Function()) setModalState) async {
      setModalState(() => loading = true);
      final result = await DBService.instance.searchPromoProducts(search: ctrl.text.trim(), limit: 50, deliveryId: deliveryId);
      if (result.success) {
        final data = result.data ?? {};
        setModalState(() {
          products = (data['products'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
          loading = false;
        });
      } else {
        setModalState(() => loading = false);
        _snack(result.message, error: true);
      }
    }

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => StatefulBuilder(builder: (context, setModalState) {
        if (products.isEmpty && !loading && ctrl.text.isEmpty) {
          Future.microtask(() => search(setModalState));
        }
        return Dialog(
          backgroundColor: _surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
            child: Column(children: [
              if (deliveryId > 0)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(color: _teal.withOpacity(0.10), borderRadius: BorderRadius.circular(8)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.local_shipping_rounded, color: _teal, size: 16),
                      const SizedBox(width: 6),
                      Expanded(child: Text('Showing products from selected delivery only.', style: TextStyle(color: _teal, fontSize: 12))),
                    ]),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      style: TextStyle(color: _textHi),
                      decoration: _inputDecoration('Search product code or name', Icons.search_rounded),
                      onSubmitted: (_) => search(setModalState),
                    ),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(onPressed: () => search(setModalState), child: const Text('Search')),
                ]),
              ),
              Expanded(
                child: loading
                    ? Center(child: CircularProgressIndicator(color: _blue))
                    : products.isEmpty
                    ? Center(child: Text(deliveryId > 0 ? 'No products in this delivery match.' : 'No products found.', style: TextStyle(color: _textLo)))
                    : ListView.separated(
                  itemCount: products.length,
                  separatorBuilder: (_, __) => Divider(color: _border, height: 1),
                  itemBuilder: (_, i) {
                    final p = products[i];
                    final remaining = p['delivery_remaining_qty'];
                    final remainingText = remaining != null ? ' • Batch: ${_toDouble(remaining).toStringAsFixed(0)}' : '';
                    return ListTile(
                      title: Text('${p['product_code']} — ${p['item_description']}',
                          style: TextStyle(color: _textHi, fontWeight: FontWeight.w600)),
                      subtitle: Text('SRP: ${_money(p['unit_price'])} • UOM: ${p['uom'] ?? 'PCS'}$remainingText',
                          style: TextStyle(color: _textLo)),
                      onTap: () => Navigator.pop(context, p),
                    );
                  },
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                ),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Row / Card widgets
// ─────────────────────────────────────────────────────────────────────────

class _PromoTableRow extends StatelessWidget {
  final Map<String, dynamic> promo;
  final VoidCallback onEdit, onCancel;
  final bool canEdit, canDelete;

  const _PromoTableRow({
    required this.promo,
    required this.onEdit,
    required this.onCancel,
    required this.canEdit,
    required this.canDelete,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStatus = _resolveStatus(promo);
    final isCancelled     = effectiveStatus == 'CANCELLED';
    final typeLabel       = (promo['calculation_name']?.toString() ?? promo['promo_type']?.toString() ?? '');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 2, child: Text(promo['promo_no']?.toString() ?? '', style: TextStyle(color: _teal, fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'monospace'), softWrap: true)),
          Expanded(flex: 4, child: Text(promo['promo_name']?.toString() ?? '', style: TextStyle(color: _textHi, fontSize: 13, fontWeight: FontWeight.w600), softWrap: true)),
          Expanded(flex: 3, child: Text(promo['supplier_name']?.toString() ?? 'N/A', style: TextStyle(color: _textLo, fontSize: 13), softWrap: true)),
          Expanded(flex: 2, child: Text(promo['delivery_no']?.toString() ?? '—', style: TextStyle(color: _textLo, fontSize: 13), softWrap: true)),
          Expanded(flex: 3, child: Text(promo['store_name']?.toString() ?? 'All Stores', style: TextStyle(color: _textLo, fontSize: 13), softWrap: true)),
          Expanded(flex: 2, child: _TypeChip(type: typeLabel)),
          Expanded(flex: 3, child: Text('${promo['date_from']} → ${promo['date_to']}', style: TextStyle(color: _textLo, fontSize: 12), softWrap: true)),
          SizedBox(width: 60, child: Text('${promo['item_count'] ?? 0}', style: TextStyle(color: _textHi, fontSize: 13, fontWeight: FontWeight.w600))),
          SizedBox(width: 120, child: _StatusChip(status: effectiveStatus)),
          SizedBox(
            width: 84,
            child: Row(children: [
              _IconBtn(
                icon: canEdit ? Icons.edit_rounded : Icons.visibility_rounded,
                color: _blue,
                tooltip: canEdit ? 'Edit' : 'View',
                onTap: onEdit,
              ),
              const SizedBox(width: 4),
              if (canDelete && !isCancelled)
                _IconBtn(
                  icon: Icons.cancel_rounded,
                  color: _red,
                  tooltip: 'Cancel promo',
                  onTap: onCancel,
                ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _PromoCard extends StatelessWidget {
  final Map<String, dynamic> promo;
  final VoidCallback onEdit, onCancel;
  final bool canEdit, canDelete;

  const _PromoCard({
    required this.promo,
    required this.onEdit,
    required this.onCancel,
    required this.canEdit,
    required this.canDelete,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStatus = _resolveStatus(promo);
    final isCancelled     = effectiveStatus == 'CANCELLED';
    final typeLabel       = (promo['calculation_name']?.toString() ?? promo['promo_type']?.toString() ?? '');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _teal.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _teal.withOpacity(0.35)),
                ),
                child: Text(promo['promo_no']?.toString() ?? '',
                    style: TextStyle(color: _teal, fontSize: 12, fontWeight: FontWeight.w700, fontFamily: 'monospace')),
              ),
              const SizedBox(width: 8),
              _StatusChip(status: effectiveStatus),
              const Spacer(),
              _IconBtn(icon: canEdit ? Icons.edit_rounded : Icons.visibility_rounded, color: _blue, tooltip: canEdit ? 'Edit' : 'View', onTap: onEdit),
              if (canDelete && !isCancelled)
                _IconBtn(icon: Icons.cancel_rounded, color: _red, tooltip: 'Cancel', onTap: onCancel),
            ],
          ),
          const SizedBox(height: 10),
          Text(promo['promo_name']?.toString() ?? '', style: TextStyle(color: _textHi, fontSize: 14, fontWeight: FontWeight.w700), softWrap: true),
          const SizedBox(height: 8),
          _kv('Supplier', promo['supplier_name']?.toString() ?? 'N/A'),
          if ((promo['delivery_no']?.toString() ?? '').isNotEmpty) _kv('Delivery', promo['delivery_no']?.toString() ?? ''),
          _kv('Store', promo['store_name']?.toString() ?? 'All Stores'),
          _kv('Dates', '${promo['date_from']} → ${promo['date_to']}'),
          const SizedBox(height: 10),
          Row(children: [
            _TypeChip(type: typeLabel),
            const SizedBox(width: 8),
            Text('${promo['item_count'] ?? 0} item(s)', style: TextStyle(color: _textLo, fontSize: 12)),
          ]),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(children: [
          TextSpan(text: '$k: ', style: TextStyle(color: _textLo, fontSize: 12, fontWeight: FontWeight.w600)),
          TextSpan(text: v, style: TextStyle(color: _textHi, fontSize: 12)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────
//  Small reusable widgets
// ─────────────────────────────────────────────────────────────────────────

/// Main promo status chip — uses _statusStyle for consistent colour+icon.
class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final s = _statusStyle(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: s.color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: s.color.withOpacity(0.35)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(s.icon, size: 12, color: s.color),
        const SizedBox(width: 4),
        Text(s.label, style: TextStyle(color: s.color, fontWeight: FontWeight.w700, fontSize: 11)),
      ]),
    );
  }
}

/// Small badge shown inline on items that are out of stock or batch-empty.
class _ItemStatusBadge extends StatelessWidget {
  final String status; // 'OUT_OF_STOCK' | 'BATCH_EMPTY'
  const _ItemStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isOOS  = status == 'OUT_OF_STOCK';
    final color  = isOOS ? const Color(0xFFFF7043) : const Color(0xFFEF5350);
    final label  = isOOS ? 'OUT OF STOCK' : 'BATCH EMPTY';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final isB1T1 = type == 'BUY_1_TAKE_1' || type.toLowerCase().contains('buy') || type.toLowerCase().contains('free');
    final color  = isB1T1 ? _teal : _blue;
    final label  = isB1T1 ? 'Buy X Take Y' : (type.isEmpty ? 'Promo Price' : type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11), overflow: TextOverflow.ellipsis),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label, value;
  final Color color;
  const _MiniStat({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: _textLo, fontSize: 12)),
      ]),
    );
  }
}

class _PageNavButton extends StatelessWidget {
  final String label; final bool enabled; final VoidCallback onTap;
  const _PageNavButton({required this.label, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: enabled ? _surface : _surface.withOpacity(0.5), shape: BoxShape.circle, border: Border.all(color: _border)),
        child: Center(child: Text(label, style: TextStyle(color: enabled ? _textHi : _textLo, fontWeight: FontWeight.w600))),
      ),
    );
  }
}

class _PageTab extends StatelessWidget {
  final String label; final bool active; final VoidCallback onTap;
  const _PageTab({required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(color: active ? _blue : _surface, shape: BoxShape.circle, border: Border.all(color: active ? _blue : _border)),
        child: Center(child: Text(label, style: TextStyle(color: active ? Colors.white : _textHi, fontWeight: FontWeight.w600, fontSize: 13))),
      ),
    );
  }
}

class _TH extends StatelessWidget {
  final String text;
  const _TH(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text, style: TextStyle(color: _textLo, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5));
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon; final Color color; final String tooltip; final VoidCallback onTap;
  const _IconBtn({required this.icon, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, color: color, size: 18)),
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final T value; final String label; final IconData icon;
  final List<DropdownMenuItem<T>> items; final ValueChanged<T?> onChanged;
  const _FilterDropdown({required this.value, required this.label, required this.icon, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final matches  = items.where((item) => item.value == value).length;
    final safeValue = matches == 1 ? value : null;
    return DropdownButtonFormField<T>(
      value: safeValue,
      isExpanded: true,
      dropdownColor: _surface,
      style: TextStyle(color: _textHi, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _textLo, fontSize: 12),
        prefixIcon: Icon(icon, color: _textLo, size: 18),
        filled: true, fillColor: _surface,
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _blue, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message; final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
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
        ]),
      ),
    );
  }
}