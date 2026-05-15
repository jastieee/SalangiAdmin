import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart' as csv;
import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../db/DBResult.dart';
import '../Utils/app_theme.dart';

AppTheme get _t => themeNotifier.theme;
Color get _bg => _t.bg;
Color get _surface => _t.surface;
Color get _border => _t.border;
Color get _blue => _t.blue;
Color get _green => _t.green;
Color get _red => _t.red;
Color get _amber => _t.amber;
Color get _textHi => _t.textHi;
Color get _textLo => _t.textLo;

class SupplierManagementScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;

  const SupplierManagementScreen({super.key, this.currentUser});

  @override
  State<SupplierManagementScreen> createState() =>
      _SupplierManagementScreenState();
}

class _SupplierManagementScreenState extends State<SupplierManagementScreen> {
  bool _loading = true;
  bool dialogSaving = false;
  bool _importing = false;
  String? _error;
  String _search = '';

  List<Map<String, dynamic>> _suppliers = [];

  final _searchCtrl = TextEditingController();

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

  int get _currentUserId {
    final id = widget.currentUser?['user_id'] ?? widget.currentUser?['id'];
    if (id is int) return id;
    if (id is num) return id.toInt();
    return int.tryParse(id?.toString() ?? '') ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSuppliers() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await DBService.instance.fetchSuppliers();

    if (!mounted) return;

    final List<Map<String, dynamic>> loadedSuppliers = [];

    if (result.success) {
      final data = result.data;
      final dynamic supplierData = data?['suppliers'];

      if (supplierData is List) {
        for (final item in supplierData) {
          if (item is Map) {
            loadedSuppliers.add(Map<String, dynamic>.from(item));
          }
        }
      }
    }

    setState(() {
      _loading = false;

      if (result.success) {
        _suppliers = loadedSuppliers;
      } else {
        _error = result.message;
      }
    });
  }

  List<Map<String, dynamic>> get _filteredSuppliers {
    final q = _search.trim().toLowerCase();

    if (q.isEmpty) return _suppliers;

    return _suppliers.where((s) {
      final code = s['supplier_code']?.toString().toLowerCase() ?? '';
      final name = s['supplier_name']?.toString().toLowerCase() ?? '';
      final contact = s['contact_person']?.toString().toLowerCase() ?? '';
      final phone = s['contact_number']?.toString().toLowerCase() ?? '';
      final email = s['email']?.toString().toLowerCase() ?? '';

      return code.contains(q) ||
          name.contains(q) ||
          contact.contains(q) ||
          phone.contains(q) ||
          email.contains(q);
    }).toList();
  }

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

  Future<void> _showSupplierDialog({Map<String, dynamic>? supplier}) async {
    final isEdit = supplier != null;

    final nameCtrl = TextEditingController(
      text: supplier?['supplier_name']?.toString() ?? '',
    );
    final contactCtrl = TextEditingController(
      text: supplier?['contact_person']?.toString() ?? '',
    );
    final phoneCtrl = TextEditingController(
      text: supplier?['contact_number']?.toString() ?? '',
    );
    final emailCtrl = TextEditingController(
      text: supplier?['email']?.toString() ?? '',
    );
    final addressCtrl = TextEditingController(
      text: supplier?['address']?.toString() ?? '',
    );

    String status = supplier?['status']?.toString() ?? 'ACTIVE';
    bool dialogSaving = false;

    final formKey = GlobalKey<FormState>();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> save() async {
              if (!formKey.currentState!.validate()) return;

              setModalState(() => dialogSaving = true);

              final result = isEdit
                  ? await DBService.instance.updateSupplier(
                supplierId: supplier?['supplier_id'],
                supplierCode: supplier?['supplier_code']?.toString() ?? '',
                supplierName: nameCtrl.text.trim(),
                contactPerson: contactCtrl.text.trim(),
                contactNumber: phoneCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                address: addressCtrl.text.trim(),
                status: status,
                performedBy: _currentUserId,
              )
                  : await DBService.instance.createSupplier(
                supplierCode: '',
                supplierName: nameCtrl.text.trim(),
                contactPerson: contactCtrl.text.trim(),
                contactNumber: phoneCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                address: addressCtrl.text.trim(),
                status: status,
                performedBy: _currentUserId,
              );

              if (!mounted) return;

              if (result.success) {
                Navigator.pop(context);
                _snack(isEdit ? 'Supplier updated.' : 'Supplier created.');
                _loadSuppliers();
              } else {
                setModalState(() => dialogSaving = false);
                _snack(result.message, error: true);
              }
            }

            return AlertDialog(
              backgroundColor: _surface,
              title: Text(
                isEdit ? 'Edit Supplier' : 'Add Supplier',
                style: TextStyle(color: _textHi),
              ),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isEdit) ...[
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _bg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _border),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.qr_code_rounded,
                                    color: _textLo, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Supplier Code: ${supplier?['supplier_code'] ?? '-'}',
                                  style: TextStyle(
                                    color: _textLo,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        _Field(
                          controller: nameCtrl,
                          label: 'Supplier Name',
                          hint: 'Enter supplier name',
                          requiredField: true,
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: contactCtrl,
                          label: 'Contact Person',
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: phoneCtrl,
                          label: 'Contact Number',
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: emailCtrl,
                          label: 'Email',
                        ),
                        const SizedBox(height: 12),
                        _Field(
                          controller: addressCtrl,
                          label: 'Address',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          value: status,
                          dropdownColor: _surface,
                          decoration: _inputDecoration('Status'),
                          style: TextStyle(color: _textHi),
                          items: const [
                            DropdownMenuItem(
                              value: 'ACTIVE',
                              child: Text('ACTIVE'),
                            ),
                            DropdownMenuItem(
                              value: 'INACTIVE',
                              child: Text('INACTIVE'),
                            ),
                          ],
                          onChanged: dialogSaving
                              ? null
                              : (v) {
                            if (v != null) {
                              setModalState(() => status = v);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed:
                  dialogSaving ? null : () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: _textLo)),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _blue),
                  onPressed: dialogSaving ? null : save,
                  icon: dialogSaving
                      ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                      : const Icon(Icons.save_rounded, size: 16),
                  label: Text(isEdit ? 'Update' : 'Save'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deactivateSupplier(Map<String, dynamic> supplier) async {
    final name = supplier['supplier_name']?.toString() ?? 'this supplier';
    final isActive =
        (supplier['status']?.toString().toUpperCase() ?? 'ACTIVE') == 'ACTIVE';

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: Text(
            isActive ? 'Deactivate Supplier' : 'Activate Supplier', style: TextStyle(color: _textHi)),
        content: Text(
            isActive
                ? 'Are you sure you want to deactivate $name?'
                : 'Are you sure you want to activate $name?',
          style: TextStyle(color: _textLo),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: _textLo)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(isActive ? 'Deactivate' : 'Activate'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final result = await DBService.instance.deleteSupplier(
      supplierId: supplier['supplier_id'],
      performedBy: _currentUserId,
    );

    if (!mounted) return;

    if (result.success) {
      _snack('Supplier deactivated.');
      _loadSuppliers();
    } else {
      _snack(result.message, error: true);
    }
  }


  Future<void> _importSuppliers() async {
    if (_importing) return;

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

      List<Map<String, dynamic>> rows = [];

      if (ext == 'csv') {
        rows = _parseSupplierCsv(bytes);
      } else if (ext == 'xlsx') {
        rows = _parseSupplierXlsx(bytes);
      } else {
        _snack('Only CSV and XLSX files are accepted.', error: true);
        return;
      }

      if (rows.isEmpty) {
        _snack('No valid supplier rows found. Supplier name is required.',
            error: true);
        return;
      }

      final confirmed = await _showImportPreview(rows, file.name);
      if (confirmed != true) return;

      setState(() => _importing = true);

      int successCount = 0;
      int failedCount = 0;
      final List<String> errors = [];

      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];

        final result = await DBService.instance.createSupplier(
          supplierCode: '',
          supplierName: r['supplier_name']?.toString() ?? '',
          contactPerson: r['contact_person']?.toString() ?? '',
          contactNumber: r['contact_number']?.toString() ?? '',
          email: r['email']?.toString() ?? '',
          address: r['address']?.toString() ?? '',
          status: r['status']?.toString() ?? 'ACTIVE',
          performedBy: _currentUserId,
        );

        if (result.success) {
          successCount++;
        } else {
          failedCount++;
          errors.add(
            'Row ${i + 2}: ${r['supplier_name'] ?? '-'} — ${result.message}',
          );
        }
      }

      if (!mounted) return;

      setState(() => _importing = false);

      await _loadSuppliers();

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

    final table = decoded
        .map<List<dynamic>>((row) => List<dynamic>.from(row))
        .toList();

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

    final headers = table.first
        .map((h) => _normalizeHeader(h?.toString() ?? ''))
        .toList();

    final int nameIndex = headers.indexOf('supplier_name');
    final int contactIndex = headers.indexOf('contact_person');
    final int numberIndex = headers.indexOf('contact_number');
    final int emailIndex = headers.indexOf('email');
    final int addressIndex = headers.indexOf('address');
    final int statusIndex = headers.indexOf('status');

    if (nameIndex < 0) {
      throw Exception('Missing required column: supplier_name');
    }

    final List<Map<String, dynamic>> rows = [];

    for (int i = 1; i < table.length; i++) {
      final row = table[i];

      String valueAt(int index) {
        if (index < 0) return '';
        if (index >= row.length) return '';
        return row[index]?.toString().trim() ?? '';
      }

      final supplierName = valueAt(nameIndex);
      if (supplierName.isEmpty) continue;

      String status = valueAt(statusIndex).toUpperCase();
      if (status.isEmpty) status = 'ACTIVE';
      if (status != 'ACTIVE' && status != 'INACTIVE') status = 'ACTIVE';

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

  Future<bool?> _showImportPreview(
      List<Map<String, dynamic>> rows,
      String fileName,
      ) {
    final previewRows = rows.take(10).toList();

    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: Text('Import Suppliers', style: TextStyle(color: _textHi)),
        content: SizedBox(
          width: 760,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'File: $fileName\n${rows.length} valid supplier row(s) found.',
                style: TextStyle(color: _textLo, fontSize: 13),
              ),
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
                        return DataRow(
                          cells: [
                            DataCell(Text(
                              r['supplier_name']?.toString() ?? '',
                              style: TextStyle(color: _textHi),
                            )),
                            DataCell(Text(
                              r['contact_person']?.toString() ?? '',
                              style: TextStyle(color: _textHi),
                            )),
                            DataCell(Text(
                              r['contact_number']?.toString() ?? '',
                              style: TextStyle(color: _textHi),
                            )),
                            DataCell(Text(
                              r['email']?.toString() ?? '',
                              style: TextStyle(color: _textHi),
                            )),
                            DataCell(Text(
                              r['status']?.toString() ?? 'ACTIVE',
                              style: TextStyle(color: _textHi),
                            )),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
              if (rows.length > 10) ...[
                const SizedBox(height: 8),
                Text(
                  'Showing first 10 rows only.',
                  style: TextStyle(color: _textLo, fontSize: 12),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Supplier codes will be auto-generated by the server.',
                style: TextStyle(color: _amber, fontSize: 12),
              ),
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
        title: Text('Import Result', style: TextStyle(color: _textHi)),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: _green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$successCount supplier(s) imported successfully.',
                      style: TextStyle(color: _textHi),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    failedCount > 0
                        ? Icons.warning_amber_rounded
                        : Icons.info_outline_rounded,
                    color: failedCount > 0 ? _amber : _textLo,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '$failedCount failed.',
                      style: TextStyle(color: _textHi),
                    ),
                  ),
                ],
              ),
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
                    child: Text(
                      errors.take(20).join('\n'),
                      style: TextStyle(color: _red, fontSize: 12),
                    ),
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
        title:
        Text('Supplier Import Template', style: TextStyle(color: _textHi)),
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

  @override
  Widget build(BuildContext context) {
    final suppliers = _filteredSuppliers;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          RefreshIndicator(
            color: _blue,
            backgroundColor: _surface,
            onRefresh: _loadSuppliers,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Header(
                    onRefresh: _loadSuppliers,
                    onAdd: canCreate ? () => _showSupplierDialog() : null,
                    onImport: canImport ? _importSuppliers : null,
                    onTemplate: canImport ? _showTemplateInfo : null,
                    importing: _importing,
                  ),
                  const SizedBox(height: 18),
                  _SearchBar(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _search = v),
                  ),
                  const SizedBox(height: 18),
                  if (_loading)
                    SizedBox(
                      height: 300,
                      child: Center(
                        child: CircularProgressIndicator(color: _blue),
                      ),
                    )
                  else if (_error != null)
                    _ErrorBox(message: _error!, onRetry: _loadSuppliers)
                  else
                    _SupplierTable(
                      suppliers: suppliers,
                      canEdit: canEdit,
                      canDelete: canDelete,
                      onEdit: (s) => _showSupplierDialog(supplier: s),
                      onDelete: _deactivateSupplier,
                    ),
                ],
              ),
            ),
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
                      Text(
                        'Importing suppliers...',
                        style: TextStyle(
                          color: _textHi,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback? onAdd;
  final VoidCallback? onImport;
  final VoidCallback? onTemplate;
  final bool importing;

  const _Header({
    required this.onRefresh,
    this.onAdd,
    this.onImport,
    this.onTemplate,
    this.importing = false,
  });

  @override
  Widget build(BuildContext context) {
    final isSmall = MediaQuery.of(context).size.width < 650;

    final buttons = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: _textHi,
            side: BorderSide(color: _border),
          ),
          onPressed: importing ? null : onRefresh,
          icon: const Icon(Icons.refresh_rounded, size: 16),
          label: const Text('Refresh'),
        ),
        if (onTemplate != null)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _textHi,
              side: BorderSide(color: _border),
            ),
            onPressed: importing ? null : onTemplate,
            icon: const Icon(Icons.description_rounded, size: 16),
            label: const Text('Template'),
          ),
        if (onImport != null)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _blue,
              side: BorderSide(color: _blue.withOpacity(0.4)),
            ),
            onPressed: importing ? null : onImport,
            icon: const Icon(Icons.upload_file_rounded, size: 16),
            label: const Text('Import CSV/XLSX'),
          ),
        if (onAdd != null)
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: _blue),
            onPressed: importing ? null : onAdd,
            icon: const Icon(Icons.add_rounded, size: 16),
            label: const Text('Add Supplier'),
          ),
      ],
    );

    if (isSmall) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TitleBlock(),
          const SizedBox(height: 12),
          buttons,
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _TitleBlock(),
        buttons,
      ],
    );
  }
}

class _TitleBlock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Suppliers',
          style: TextStyle(
            color: _textHi,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Manage supplier master records for deliveries and receiving.',
          style: TextStyle(color: _textLo, fontSize: 12),
        ),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(color: _textHi),
      decoration: InputDecoration(
        hintText: 'Search supplier code, name, contact, phone, or email...',
        hintStyle: TextStyle(color: _textLo),
        prefixIcon: Icon(Icons.search_rounded, color: _textLo),
        filled: true,
        fillColor: _surface,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: _blue),
        ),
      ),
    );
  }
}

class _SupplierTable extends StatelessWidget {
  final List<Map<String, dynamic>> suppliers;
  final bool canEdit;
  final bool canDelete;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>) onDelete;

  const _SupplierTable({
    required this.suppliers,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    if (suppliers.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            Icon(Icons.business_rounded, color: _textLo, size: 42),
            const SizedBox(height: 10),
            Text(
              'No suppliers found',
              style: TextStyle(
                color: _textHi,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Add or import suppliers to start using them in delivery in.',
              style: TextStyle(color: _textLo, fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(_bg),
            columnSpacing: 28,
            columns: const [
              DataColumn(label: Text('Code')),
              DataColumn(label: Text('Supplier')),
              DataColumn(label: Text('Contact')),
              DataColumn(label: Text('Phone')),
              DataColumn(label: Text('Email')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Actions')),
            ],
            rows: suppliers.map((s) {
              final status = s['status']?.toString() ?? 'ACTIVE';
              final isActive =
                  (s['status']?.toString().toUpperCase() ?? 'ACTIVE') == 'ACTIVE';

              return DataRow(
                cells: [
                  _cell(s['supplier_code']?.toString() ?? '-'),
                  _cell(s['supplier_name']?.toString() ?? '-'),
                  _cell(s['contact_person']?.toString() ?? '-'),
                  _cell(s['contact_number']?.toString() ?? '-'),
                  _cell(s['email']?.toString() ?? '-'),
                  DataCell(
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: (isActive ? _green : _amber).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          color: isActive ? _green : _amber,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  DataCell(
                    Row(
                      children: [
                        if (canEdit)
                          IconButton(
                            tooltip: 'Edit',
                            onPressed: () => onEdit(s),
                            icon: Icon(
                              Icons.edit_rounded,
                              color: _blue,
                              size: 18,
                            ),
                          ),
                        if (canDelete)
                          IconButton(
                            tooltip: isActive ? 'Deactivate' : 'Activate',
                            onPressed: () => onDelete(s),
                            icon: Icon(
                              isActive ? Icons.block_rounded : Icons.check_circle_rounded,
                              color: isActive ? _red : _green,
                              size: 18,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  DataCell _cell(String text) {
    return DataCell(
      Text(
        text,
        style: TextStyle(color: _textHi, fontSize: 12),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final int maxLines;
  final bool requiredField;

  const _Field({
    required this.controller,
    required this.label,
    this.hint,
    this.maxLines = 1,
    this.requiredField = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      style: TextStyle(color: _textHi),
      validator: (v) {
        if (requiredField && (v == null || v.trim().isEmpty)) {
          return '$label is required';
        }
        return null;
      },
      decoration: _inputDecoration(label, hint: hint),
    );
  }
}

InputDecoration _inputDecoration(String label, {String? hint}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: TextStyle(color: _textLo),
    hintStyle: TextStyle(color: _textLo.withOpacity(0.7)),
    filled: true,
    fillColor: _bg,
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: _border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: _blue),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: _red),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: _red),
    ),
  );
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorBox({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, color: _textLo, size: 42),
          const SizedBox(height: 10),
          Text(
            message,
            style: TextStyle(color: _textLo, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}