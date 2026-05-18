import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:csv/csv.dart' as csv;
import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../db/DBResult.dart';
import '../Utils/app_theme.dart';

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

class SupplierManagementScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;
  const SupplierManagementScreen({super.key, this.currentUser});

  @override
  State<SupplierManagementScreen> createState() => _SupplierManagementScreenState();
}

class _SupplierManagementScreenState extends State<SupplierManagementScreen> {
  bool _loading = true;
  bool _importing = false;
  String? _error;

  List<Map<String, dynamic>> _suppliers = [];

  String _searchQuery = '';
  int _itemsPerPage = 10;
  int _currentPage = 1;

  final List<int> _pageSizeOptions = [10, 20, 50, 100];

  bool get _isWindows {
    try {
      return !kIsWeb && Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  int get _currentUserId {
    final id = widget.currentUser?['user_id'] ?? widget.currentUser?['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return int.tryParse(id?.toString() ?? '') ?? 0;
  }

  // ── Permissions ─────────────────────────────────────────────────────────
  bool _hasPermission(String permissionName) {
    final modules = List<Map<String, dynamic>>.from(
      widget.currentUser?['admin_modules'] ?? [],
    );

    return modules.any((m) {
      final name = m['module_name']?.toString() ?? '';
      final canAccess = m['can_access'] == true ||
          m['can_access'] == 1 ||
          m['can_access'].toString() == '1';
      return name == permissionName && canAccess;
    });
  }

  bool get canCreate => _hasPermission('SUPPLIER_CREATE');
  bool get canEdit => _hasPermission('SUPPLIER_EDIT');
  bool get canDelete => _hasPermission('SUPPLIER_DELETE');
  bool get canImport => _hasPermission('SUPPLIER_IMPORT');

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ── Safe converters ─────────────────────────────────────────────────────
  String _toStr(dynamic v) => v?.toString() ?? '';

  // ── Loader ──────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await DBService.instance.fetchSuppliers();

    if (!mounted) return;

    final List<Map<String, dynamic>> loaded = [];

    if (result.success) {
      final supplierData = result.data?['suppliers'];
      if (supplierData is List) {
        for (final item in supplierData) {
          if (item is Map) loaded.add(Map<String, dynamic>.from(item));
        }
      }
    }

    setState(() {
      _loading = false;
      if (result.success) {
        _suppliers = loaded;
        _currentPage = 1;
      } else {
        _error = result.message;
      }
    });
  }

  // ── Filter + paging ─────────────────────────────────────────────────────
  List<Map<String, dynamic>> get _filtered {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _suppliers;

    return _suppliers.where((s) {
      return _toStr(s['supplier_code']).toLowerCase().contains(q) ||
          _toStr(s['supplier_name']).toLowerCase().contains(q) ||
          _toStr(s['contact_person']).toLowerCase().contains(q) ||
          _toStr(s['contact_number']).toLowerCase().contains(q) ||
          _toStr(s['email']).toLowerCase().contains(q);
    }).toList();
  }

  int get _totalPages {
    final total = _filtered.length;
    if (total == 0) return 1;
    return (total / _itemsPerPage).ceil();
  }

  List<Map<String, dynamic>> get _pagedSuppliers {
    final list = _filtered;
    final start = (_currentPage - 1) * _itemsPerPage;
    if (start >= list.length) return [];
    final end = (start + _itemsPerPage).clamp(0, list.length);
    return list.sublist(start, end);
  }

  void _goToPage(int page) {
    final safe = page.clamp(1, _totalPages);
    setState(() => _currentPage = safe);
  }

  List<dynamic> _visiblePageItems() {
    final total = _totalPages;
    final current = _currentPage;
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

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
      _currentPage = 1;
    });
  }

  // ── Snack ───────────────────────────────────────────────────────────────
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

  // ── Add / Edit dialog ───────────────────────────────────────────────────
  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    if (existing == null && !canCreate) {
      _snack('You do not have permission to create suppliers.', error: true);
      return;
    }
    if (existing != null && !canEdit) {
      _snack('You do not have permission to edit suppliers.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SupplierFormDialog(
        existing: existing,
        currentUserId: _currentUserId,
      ),
    );

    if (ok == true) _load();
  }

  // ── Deactivate ──────────────────────────────────────────────────────────
  Future<void> _toggleActive(Map<String, dynamic> supplier) async {
    if (!canDelete) {
      _snack('You do not have permission to change supplier status.', error: true);
      return;
    }

    final name = _toStr(supplier['supplier_name']);
    final isActive =
        _toStr(supplier['status']).toUpperCase() == 'ACTIVE';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: isActive ? 'Deactivate Supplier' : 'Activate Supplier',
        message: isActive
            ? 'Are you sure you want to deactivate $name?'
            : 'Are you sure you want to activate $name?',
        confirmLabel: isActive ? 'Deactivate' : 'Activate',
        confirmColor: isActive ? _red : _green,
      ),
    );

    if (ok != true || !mounted) return;

    final result = await DBService.instance.deleteSupplier(
      supplierId: supplier['supplier_id'],
      performedBy: _currentUserId,
    );

    if (!mounted) return;

    if (result.success) {
      _snack(isActive ? 'Supplier deactivated.' : 'Supplier activated.');
      _load();
    } else {
      _snack(result.message, error: true);
    }
  }

  // ── Import (unchanged logic, just relocated) ────────────────────────────
  Future<void> _importSuppliers() async {
    if (_importing) return;
    if (!canImport) {
      _snack('You do not have permission to import suppliers.', error: true);
      return;
    }

    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv', 'xlsx'],
        withData: true,
      );

      if (picked == null || picked.files.isEmpty) return;

      final file = picked.files.single;
      final ext = (file.extension ?? '').toLowerCase();
      final bytes = file.bytes;

      if (bytes == null) {
        _snack('Unable to read selected file.', error: true);
        return;
      }

      List<Map<String, dynamic>> rows;
      if (ext == 'csv') {
        rows = _parseSupplierCsv(bytes);
      } else if (ext == 'xlsx') {
        rows = _parseSupplierXlsx(bytes);
      } else {
        _snack('Only CSV and XLSX files are accepted.', error: true);
        return;
      }

      if (rows.isEmpty) {
        _snack('No valid supplier rows found. Supplier name is required.', error: true);
        return;
      }

      final confirmed = await _showImportPreview(rows, file.name);
      if (confirmed != true) return;

      setState(() => _importing = true);

      int successCount = 0;
      int failedCount = 0;
      final errors = <String>[];

      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];
        final result = await DBService.instance.createSupplier(
          supplierCode: '',
          supplierName: _toStr(r['supplier_name']),
          contactPerson: _toStr(r['contact_person']),
          contactNumber: _toStr(r['contact_number']),
          email: _toStr(r['email']),
          address: _toStr(r['address']),
          status: _toStr(r['status']).isEmpty ? 'ACTIVE' : _toStr(r['status']),
          performedBy: _currentUserId,
        );

        if (result.success) {
          successCount++;
        } else {
          failedCount++;
          errors.add('Row ${i + 2}: ${r['supplier_name'] ?? '-'} — ${result.message}');
        }
      }

      if (!mounted) return;
      setState(() => _importing = false);
      await _load();

      _showImportResult(
        successCount: successCount,
        failedCount: failedCount,
        errors: errors,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _importing = false);
      _snack('Import error: $e', error: true);
    }
  }

  List<Map<String, dynamic>> _parseSupplierCsv(Uint8List bytes) {
    final content = utf8.decode(bytes, allowMalformed: true);
    final decoded = csv.CsvDecoder().convert(content);
    final table = decoded.map<List<dynamic>>((row) => List<dynamic>.from(row)).toList();
    return _parseTableRows(table);
  }

  List<Map<String, dynamic>> _parseSupplierXlsx(Uint8List bytes) {
    final workbook = excel.Excel.decodeBytes(bytes);
    if (workbook.tables.isEmpty) return [];

    final firstSheetName = workbook.tables.keys.first;
    final sheet = workbook.tables[firstSheetName];
    if (sheet == null) return [];

    final table = sheet.rows.map((row) {
      return row.map((cell) => cell?.value?.toString() ?? '').toList();
    }).toList();

    return _parseTableRows(table);
  }

  List<Map<String, dynamic>> _parseTableRows(List<List<dynamic>> table) {
    if (table.isEmpty) return [];

    final headers = table.first.map((h) => _normalizeHeader(h?.toString() ?? '')).toList();

    final nameIndex = headers.indexOf('supplier_name');
    final contactIndex = headers.indexOf('contact_person');
    final numberIndex = headers.indexOf('contact_number');
    final emailIndex = headers.indexOf('email');
    final addressIndex = headers.indexOf('address');
    final statusIndex = headers.indexOf('status');

    if (nameIndex < 0) throw Exception('Missing required column: supplier_name');

    final rows = <Map<String, dynamic>>[];

    for (int i = 1; i < table.length; i++) {
      final row = table[i];

      String valueAt(int index) {
        if (index < 0 || index >= row.length) return '';
        return row[index]?.toString().trim() ?? '';
      }

      final supplierName = valueAt(nameIndex);
      if (supplierName.isEmpty) continue;

      String status = valueAt(statusIndex).toUpperCase();
      if (status.isEmpty || (status != 'ACTIVE' && status != 'INACTIVE')) status = 'ACTIVE';

      rows.add({
        'supplier_name': supplierName,
        'contact_person': valueAt(contactIndex),
        'contact_number': valueAt(numberIndex),
        'email': valueAt(emailIndex),
        'address': valueAt(addressIndex),
        'status': status,
      });
    }

    return rows;
  }

  String _normalizeHeader(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll('-', '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  Future<bool?> _showImportPreview(List<Map<String, dynamic>> rows, String fileName) {
    final previewRows = rows.take(10).toList();

    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Import Suppliers', style: TextStyle(color: _textHi, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 760,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('File: $fileName\n${rows.length} valid supplier row(s) found.',
                  style: TextStyle(color: _textLo, fontSize: 13)),
              const SizedBox(height: 14),
              Container(
                constraints: const BoxConstraints(maxHeight: 320),
                decoration: BoxDecoration(
                  border: Border.all(color: _border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SingleChildScrollView(
                    child: DataTable(
                      headingRowColor: WidgetStateProperty.all(_bg),
                      columns: const [
                        DataColumn(label: Text('Supplier')),
                        DataColumn(label: Text('Contact')),
                        DataColumn(label: Text('Phone')),
                        DataColumn(label: Text('Email')),
                        DataColumn(label: Text('Status')),
                      ],
                      rows: previewRows.map((r) {
                        return DataRow(cells: [
                          DataCell(Text(_toStr(r['supplier_name']), style: TextStyle(color: _textHi))),
                          DataCell(Text(_toStr(r['contact_person']), style: TextStyle(color: _textHi))),
                          DataCell(Text(_toStr(r['contact_number']), style: TextStyle(color: _textHi))),
                          DataCell(Text(_toStr(r['email']), style: TextStyle(color: _textHi))),
                          DataCell(Text(_toStr(r['status']), style: TextStyle(color: _textHi))),
                        ]);
                      }).toList(),
                    ),
                  ),
                ),
              ),
              if (rows.length > 10) ...[
                const SizedBox(height: 8),
                Text('Showing first 10 rows only.', style: TextStyle(color: _textLo, fontSize: 12)),
              ],
              const SizedBox(height: 8),
              Text('Supplier codes will be auto-generated by the server.',
                  style: TextStyle(color: _amber, fontSize: 12)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: _textLo)),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _blue),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.upload_file_rounded, size: 16),
            label: const Text('Import'),
          ),
        ],
      ),
    );
  }

  void _showImportResult({
    required int successCount,
    required int failedCount,
    required List<String> errors,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Import Result', style: TextStyle(color: _textHi, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(Icons.check_circle_rounded, color: _green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('$successCount supplier(s) imported successfully.',
                      style: TextStyle(color: _textHi)),
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Icon(
                  failedCount > 0 ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                  color: failedCount > 0 ? _amber : _textLo,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text('$failedCount failed.', style: TextStyle(color: _textHi))),
              ]),
              if (errors.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border),
                  ),
                  child: SingleChildScrollView(
                    child: Text(errors.take(20).join('\n'),
                        style: TextStyle(color: _red, fontSize: 12)),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _blue),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showTemplateInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Supplier Import Template',
            style: TextStyle(color: _textHi, fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: 580,
          child: SelectableText(
            'CSV/XLSX columns:\n\n'
                'supplier_name,contact_person,contact_number,email,address,status\n\n'
                'Required:\n'
                'supplier_name\n\n'
                'Optional:\n'
                'contact_person\n'
                'contact_number\n'
                'email\n'
                'address\n'
                'status — ACTIVE or INACTIVE\n\n'
                'Example:\n'
                'supplier_name,contact_person,contact_number,email,address,status\n'
                'ABC Trading,Juan Dela Cruz,09171234567,abc@email.com,Manila,ACTIVE\n'
                'XYZ Supplier,Maria Santos,09991234567,xyz@email.com,Cebu,ACTIVE\n\n'
                'Supplier code is not included because the server auto-generates it.',
            style: TextStyle(color: _textHi, fontSize: 13),
          ),
        ),
        actions: [
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _blue),
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── UI ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator(color: _blue));
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
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
                                'Suppliers',
                                style: TextStyle(
                                    color: _textHi,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Manage supplier master records for deliveries and receiving',
                                style: TextStyle(color: _textLo, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh',
                          icon: Icon(Icons.refresh_rounded, color: _textLo),
                          onPressed: _load,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (canImport) ...[
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _textHi,
                              side: BorderSide(color: _border),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _showTemplateInfo,
                            icon: const Icon(Icons.description_rounded, size: 16),
                            label: const Text('Template'),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.orange,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: _importing ? null : _importSuppliers,
                            icon: const Icon(Icons.upload_file_rounded, size: 18),
                            label: const Text('Import'),
                          ),
                        ],
                        if (canCreate)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: _blue,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            onPressed: () => _openForm(),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('New Supplier'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(child: _buildBody()),
            ],
          ),
          if (_importing)
            Container(
              color: Colors.black.withOpacity(0.25),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: _blue),
                      const SizedBox(height: 14),
                      Text('Importing suppliers...',
                          style: TextStyle(
                              color: _textHi, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() => RefreshIndicator(
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
    padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
    child: _SearchBar(onChanged: _onSearchChanged),
  );

  Widget _buildStats() {
    final total = _suppliers.length;
    final filtered = _filtered.length;
    final showing = _pagedSuppliers.length;
    final active = _suppliers
        .where((s) => _toStr(s['status']).toUpperCase() == 'ACTIVE')
        .length;
    final inactive = total - active;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _MiniStat(label: 'Total', value: '$total', color: _blue),
          _MiniStat(label: 'Filtered', value: '$filtered', color: _teal),
          _MiniStat(label: 'Showing', value: '$showing / $_itemsPerPage', color: _amber),
          _MiniStat(label: 'Active', value: '$active', color: _green),
          if (inactive > 0)
            _MiniStat(label: 'Inactive', value: '$inactive', color: _red),
          _MiniStat(label: 'Page', value: '$_currentPage / $_totalPages', color: _textLo),
        ],
      ),
    );
  }

  Widget _buildTable() {
    final list = _pagedSuppliers;

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
                    Expanded(flex: 2, child: _TH('CODE')),
                    Expanded(flex: 4, child: _TH('SUPPLIER')),
                    Expanded(flex: 3, child: _TH('CONTACT')),
                    Expanded(flex: 3, child: _TH('PHONE')),
                    Expanded(flex: 4, child: _TH('EMAIL')),
                    Expanded(flex: 2, child: _TH('STATUS')),
                    SizedBox(width: 92, child: _TH('ACTIONS')),
                  ],
                ),
              ),
              Divider(height: 1, color: _border),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('No suppliers found', style: TextStyle(color: _textLo)),
                )
              else
                ...list.asMap().entries.map((e) {
                  return Column(
                    children: [
                      if (e.key > 0) Divider(height: 1, color: _border),
                      _SupplierTableRow(
                        supplier: e.value,
                        canEdit: canEdit,
                        canDelete: canDelete,
                        onEdit: () => _openForm(existing: e.value),
                        onToggle: () => _toggleActive(e.value),
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
    final list = _pagedSuppliers;

    if (list.isEmpty) {
      return SliverFillRemaining(
        child: Center(child: Text('No suppliers found', style: TextStyle(color: _textLo))),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
            (context, index) {
          final s = list[index];
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: _SupplierCard(
              supplier: s,
              canEdit: canEdit,
              canDelete: canDelete,
              onEdit: () => _openForm(existing: s),
              onToggle: () => _toggleActive(s),
            ),
          );
        },
        childCount: list.length,
      ),
    );
  }

  Widget _buildPagination() {
    if (_filtered.isEmpty) return const SizedBox.shrink();

    final items = _visiblePageItems();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text('Total: ${_filtered.length}',
              style: TextStyle(color: _textHi, fontSize: 14)),
          const SizedBox(width: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _border),
            ),
            child: DropdownButton<int>(
              value: _itemsPerPage,
              underline: const SizedBox(),
              dropdownColor: _surface,
              icon: Icon(Icons.keyboard_arrow_down_rounded, color: _textLo),
              style: TextStyle(color: _textHi, fontSize: 14),
              items: _pageSizeOptions
                  .map((size) => DropdownMenuItem<int>(value: size, child: Text('$size')))
                  .toList(),
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _itemsPerPage = value;
                  _currentPage = 1;
                });
              },
            ),
          ),
          const SizedBox(width: 16),
          _PageNavButton(
            label: '<',
            enabled: _currentPage > 1,
            onTap: () => _goToPage(_currentPage - 1),
          ),
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
              child: _PageTab(
                label: '$page',
                active: page == _currentPage,
                onTap: () => _goToPage(page),
              ),
            );
          }),
          _PageNavButton(
            label: '>',
            enabled: _currentPage < _totalPages,
            onTap: () => _goToPage(_currentPage + 1),
          ),
        ],
      ),
    );
  }
}

// ── Table row ──────────────────────────────────────────────────────────────
class _SupplierTableRow extends StatelessWidget {
  final Map<String, dynamic> supplier;
  final VoidCallback onEdit, onToggle;
  final bool canEdit, canDelete;

  const _SupplierTableRow({
    required this.supplier,
    required this.onEdit,
    required this.onToggle,
    required this.canEdit,
    required this.canDelete,
  });

  String _s(dynamic v) => v?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final status = _s(supplier['status']).toUpperCase();
    final isActive = status == 'ACTIVE';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              _s(supplier['supplier_code']).isEmpty ? '—' : _s(supplier['supplier_code']),
              style: TextStyle(
                color: _teal,
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              _s(supplier['supplier_name']),
              style: TextStyle(color: _textHi, fontSize: 13, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _s(supplier['contact_person']).isEmpty ? '—' : _s(supplier['contact_person']),
              style: TextStyle(color: _textHi, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              _s(supplier['contact_number']).isEmpty ? '—' : _s(supplier['contact_number']),
              style: TextStyle(color: _textLo, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              _s(supplier['email']).isEmpty ? '—' : _s(supplier['email']),
              style: TextStyle(color: _textLo, fontSize: 13),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: (isActive ? _green : _amber).withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: (isActive ? _green : _amber).withOpacity(0.35)),
              ),
              child: Text(
                status.isEmpty ? 'ACTIVE' : status,
                style: TextStyle(
                  color: isActive ? _green : _amber,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          SizedBox(
            width: 92,
            child: Row(
              children: [
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
                    icon: isActive ? Icons.block_rounded : Icons.check_circle_rounded,
                    color: isActive ? _red : _green,
                    tooltip: isActive ? 'Deactivate' : 'Activate',
                    onTap: onToggle,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  final Map<String, dynamic> supplier;
  final VoidCallback onEdit, onToggle;
  final bool canEdit, canDelete;

  const _SupplierCard({
    required this.supplier,
    required this.onEdit,
    required this.onToggle,
    required this.canEdit,
    required this.canDelete,
  });

  String _s(dynamic v) => v?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    final code = _s(supplier['supplier_code']);
    final name = _s(supplier['supplier_name']);
    final contact = _s(supplier['contact_person']);
    final phone = _s(supplier['contact_number']);
    final email = _s(supplier['email']);
    final status = _s(supplier['status']).toUpperCase();
    final isActive = status == 'ACTIVE';

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
            children: [
              if (code.isNotEmpty)
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
                  color: (isActive ? _green : _amber).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: (isActive ? _green : _amber).withOpacity(0.35)),
                ),
                child: Text(
                  status.isEmpty ? 'ACTIVE' : status,
                  style: TextStyle(
                    color: isActive ? _green : _amber,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              if (canEdit)
                _IconBtn(
                  icon: Icons.edit_rounded,
                  color: _blue,
                  tooltip: 'Edit',
                  onTap: onEdit,
                ),
              if (canDelete)
                _IconBtn(
                  icon: isActive ? Icons.block_rounded : Icons.check_circle_rounded,
                  color: isActive ? _red : _green,
                  tooltip: isActive ? 'Deactivate' : 'Activate',
                  onTap: onToggle,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(name,
              style: TextStyle(color: _textHi, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (contact.isNotEmpty)
            _InfoRow(icon: Icons.person_outline_rounded, label: contact),
          if (phone.isNotEmpty)
            _InfoRow(icon: Icons.phone_rounded, label: phone),
          if (email.isNotEmpty)
            _InfoRow(icon: Icons.email_outlined, label: email),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(icon, color: _textLo, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label,
              style: TextStyle(color: _textLo, fontSize: 12),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    ),
  );
}

// ── Supplier Form Dialog ──────────────────────────────────────────────────
class _SupplierFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final int currentUserId;

  const _SupplierFormDialog({this.existing, required this.currentUserId});

  @override
  State<_SupplierFormDialog> createState() => _SupplierFormDialogState();
}

class _SupplierFormDialogState extends State<_SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();

  String _s(dynamic v) => v?.toString() ?? '';

  late final _nameCtrl = TextEditingController(text: _s(widget.existing?['supplier_name']));
  late final _contactCtrl = TextEditingController(text: _s(widget.existing?['contact_person']));
  late final _phoneCtrl = TextEditingController(text: _s(widget.existing?['contact_number']));
  late final _emailCtrl = TextEditingController(text: _s(widget.existing?['email']));
  late final _addressCtrl = TextEditingController(text: _s(widget.existing?['address']));

  String _status = 'ACTIVE';
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _status = _s(widget.existing?['status']).isEmpty ? 'ACTIVE' : _s(widget.existing?['status']);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final result = _isEdit
        ? await DBService.instance.updateSupplier(
      supplierId: widget.existing?['supplier_id'],
      supplierCode: _s(widget.existing?['supplier_code']),
      supplierName: _nameCtrl.text.trim(),
      contactPerson: _contactCtrl.text.trim(),
      contactNumber: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      status: _status,
      performedBy: widget.currentUserId,
    )
        : await DBService.instance.createSupplier(
      supplierCode: '',
      supplierName: _nameCtrl.text.trim(),
      contactPerson: _contactCtrl.text.trim(),
      contactNumber: _phoneCtrl.text.trim(),
      email: _emailCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
      status: _status,
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
                        child: Icon(Icons.business_rounded, color: _blue, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isEdit ? 'Edit Supplier' : 'New Supplier',
                        style: TextStyle(
                            color: _textHi, fontSize: 18, fontWeight: FontWeight.w700),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: _textLo),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                    ],
                  ),
                  if (_isEdit) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.qr_code_rounded, color: _textLo, size: 16),
                          const SizedBox(width: 8),
                          Text(
                            'Supplier Code: ${_s(widget.existing?['supplier_code']).isEmpty ? "—" : _s(widget.existing?['supplier_code'])}',
                            style: TextStyle(
                                color: _textLo, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _Label('Supplier Name *'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _nameCtrl,
                    hint: 'e.g. ABC Trading',
                    icon: Icons.business_rounded,
                    validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  _Label('Contact Person'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _contactCtrl,
                    hint: 'e.g. Juan Dela Cruz',
                    icon: Icons.person_outline_rounded,
                  ),
                  const SizedBox(height: 16),
                  _Label('Contact Number'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _phoneCtrl,
                    hint: 'e.g. 09171234567',
                    icon: Icons.phone_rounded,
                  ),
                  const SizedBox(height: 16),
                  _Label('Email'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _emailCtrl,
                    hint: 'e.g. supplier@email.com',
                    icon: Icons.email_outlined,
                  ),
                  const SizedBox(height: 16),
                  _Label('Address'),
                  const SizedBox(height: 6),
                  _Field(
                    controller: _addressCtrl,
                    hint: 'Full address',
                    icon: Icons.location_on_outlined,
                    maxLines: 3,
                  ),
                  const SizedBox(height: 16),
                  _Label('Status'),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _status,
                    dropdownColor: _surface,
                    style: TextStyle(color: _textHi, fontSize: 14),
                    decoration: InputDecoration(
                      prefixIcon: Icon(Icons.toggle_on_outlined,
                          color: _textLo, size: 18),
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 13),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ACTIVE', child: Text('ACTIVE')),
                      DropdownMenuItem(value: 'INACTIVE', child: Text('INACTIVE')),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) {
                      if (v != null) setState(() => _status = v);
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
                          child: Text('Cancel', style: TextStyle(color: _textLo)),
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
                              : Text(
                            _isEdit ? 'Save Changes' : 'Create Supplier',
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

// ── Small shared widgets (matching product_management_screen) ─────────────
class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool readOnly;
  final int maxLines;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.hint,
    required this.icon,
    this.readOnly = false,
    this.maxLines = 1,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      validator: validator,
      maxLines: maxLines,
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

class _SearchBar extends StatelessWidget {
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      style: TextStyle(color: _textHi, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search code, name, contact, phone, or email…',
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
          Text(value,
              style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: _textLo, fontSize: 12)),
        ],
      ),
    );
  }
}

class _TH extends StatelessWidget {
  final String text;
  const _TH(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(
          color: _textLo,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ));
  }
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(text,
        style: TextStyle(color: _textLo, fontSize: 12, fontWeight: FontWeight.w500));
  }
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
      title: Text(title,
          style: TextStyle(color: _textHi, fontWeight: FontWeight.w700)),
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
            Text(message,
                style: TextStyle(color: _textLo, fontSize: 13),
                textAlign: TextAlign.center),
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