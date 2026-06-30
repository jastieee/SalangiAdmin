import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/DBResult.dart';
import '../Utils/app_theme.dart';

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:excel/excel.dart' as excel;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

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

final _peso = NumberFormat('#,##0.00');

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

String _cleanItemName(dynamic value) {
  var text = value?.toString() ?? '-';

  text = text
      .replaceAll('️', '')
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  text = text.replaceFirst(RegExp(r'\s*-\s+.*$'), '').trim();

  final cutPatterns = [
    RegExp(r'\s+!\s*.*$'),
    RegExp(r'\s+is the\s+.*$', caseSensitive: false),
    RegExp(r'\s+perfect for\s+.*$', caseSensitive: false),
    RegExp(r'\s+great for\s+.*$', caseSensitive: false),
    RegExp(r'\s+ideal for\s+.*$', caseSensitive: false),
    RegExp(r'\s+by\s+.*$', caseSensitive: false),
  ];

  for (final pattern in cutPatterns) {
    text = text.replaceFirst(pattern, '').trim();
  }

  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}
double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0.0;
}

String _na(dynamic v) {
  final s = v?.toString().trim() ?? '';
  return s.isEmpty ? 'N/A' : s;
}

String _formatDate(String? raw) {
  if (raw == null || raw.trim().isEmpty) return 'N/A';

  try {
    final dt = DateTime.parse(raw);
    return DateFormat('MMM d, yyyy h:mm a').format(dt);
  } catch (_) {
    return raw;
  }
}

class DeliveriesScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;

  const DeliveriesScreen({
    super.key,
    this.currentUser,
  });

  @override
  State<DeliveriesScreen> createState() => _DeliveriesScreenState();
}

class _DeliveriesScreenState extends State<DeliveriesScreen> {
  bool _loading = true;
  bool _detailLoading = false;
  String? _error;

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _supplierCtrl = TextEditingController();

  List<Map<String, dynamic>> _deliveries = [];
  List<Map<String, dynamic>> _warehouses = [];
  List<Map<String, dynamic>> _suppliers = [];

  Map<String, dynamic> _stats = {};
  Map<String, dynamic> _pagination = {};
  Map<String, dynamic> _detail = {};
  List<Map<String, dynamic>> _detailItems = [];

  String? _selectedStatus;
  int? _selectedWarehouseId;
  int? _selectedSupplierId;

  DateTime? _dateFrom;
  DateTime? _dateTo;

  int _page = 1;

  bool get canViewDeliveries => _hasPermission('DELIVERY_VIEW');

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _supplierCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _toList(dynamic v) {
    return (v as List?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ??
        [];
  }

  Future<Directory> _reportsDir() async {
    const folderName = 'Deliveries';

    if (kIsWeb) {
      throw Exception('Export not supported on web.');
    }

    // Windows
    if (Platform.isWindows) {
      final userProfile =
          Platform.environment['USERPROFILE'] ?? 'C:/Users/Default';
      final dir = Directory('$userProfile/Documents/Salangi/$folderName');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }

    // macOS / Linux
    if (Platform.isMacOS || Platform.isLinux) {
      final home = Platform.environment['HOME'] ?? '';
      final dir = Directory('$home/Documents/Salangi/$folderName');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }

    // Android — try public Documents first, fall back to app-scoped storage
    if (Platform.isAndroid) {
      await Permission.storage.request();

      try {
        final publicDir = Directory(
          '/storage/emulated/0/Documents/Salangi/$folderName',
        );
        if (!await publicDir.exists()) {
          await publicDir.create(recursive: true);
        }
        final probe = File('${publicDir.path}/.probe');
        await probe.writeAsString('ok');
        await probe.delete();
        return publicDir;
      } catch (_) {
        final ext = await getExternalStorageDirectory();
        final base =
            ext?.path ?? (await getApplicationDocumentsDirectory()).path;
        final dir = Directory('$base/Salangi/$folderName');
        if (!await dir.exists()) await dir.create(recursive: true);
        return dir;
      }
    }

    // iOS
    if (Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/Salangi/$folderName');
      if (!await dir.exists()) await dir.create(recursive: true);
      return dir;
    }

    // Fallback for any other platform
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/Salangi/$folderName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  void _showExportSnack(String path, String type) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$type saved: $path'),
        backgroundColor: _green,
        action: SnackBarAction(
          label: 'Open',
          textColor: Colors.white,
          onPressed: () => OpenFile.open(path),
        ),
      ),
    );
  }

  Future<void> _exportXlsxRows(
      List<Map<String, dynamic>> rows, {
        required bool includeItems,
      }) async {
    final book = excel.Excel.createExcel();
    book.rename('Sheet1', 'Deliveries');
    final sheet = book['Deliveries'];

    final titleStyle = excel.CellStyle(
      bold: true,
      fontSize: 16,
      fontColorHex: excel.ExcelColor.fromHexString('#1F3864'),
      horizontalAlign: excel.HorizontalAlign.Center,
    );

    final subtitleStyle = excel.CellStyle(
      fontSize: 11,
      fontColorHex: excel.ExcelColor.fromHexString('#44546A'),
      horizontalAlign: excel.HorizontalAlign.Center,
    );

    final headerStyle = excel.CellStyle(
      bold: true,
      fontSize: 10,
      fontColorHex: excel.ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: excel.ExcelColor.fromHexString('#1F3864'),
      horizontalAlign: excel.HorizontalAlign.Center,
    );

    final rowStyle = excel.CellStyle(fontSize: 10);
    final altStyle = excel.CellStyle(
      fontSize: 10,
      backgroundColorHex: excel.ExcelColor.fromHexString('#DCE6F1'),
    );

    void setCell(int col, int row, excel.CellValue value, excel.CellStyle style) {
      sheet.cell(excel.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row))
        ..value = value
        ..cellStyle = style;
    }

    for (int c = 0; c < 8; c++) {
      sheet.setColumnWidth(c, c == 2 ? 35 : 20);
    }

    sheet.merge(
      excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      excel.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 0),
    );
    setCell(0, 0, excel.TextCellValue("THREE E'S TOYS"), titleStyle);

    sheet.merge(
      excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
      excel.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 1),
    );
    setCell(0, 1, excel.TextCellValue('DELIVERY REPORT'), subtitleStyle);

    sheet.merge(
      excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2),
      excel.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 2),
    );
    setCell(
      0,
      2,
      excel.TextCellValue(
        'Generated on: ${DateFormat('MMMM d, yyyy hh:mm a').format(DateTime.now())}',
      ),
      subtitleStyle,
    );

    int rowCursor = 4;

    final totalDeliveries = rows.length;
    final totalItems = rows.fold<int>(
      0,
          (sum, d) => sum + _toInt(d['item_count']),
    );
    final totalAmount = rows.fold<double>(
      0,
          (sum, d) => sum + _toDouble(d['total_amount']),
    );

    final summary = [
      ['Total Deliveries', '$totalDeliveries'],
      ['Total Items', '$totalItems'],
      ['Total Cost', '₱${_peso.format(totalAmount)}'],
    ];

    for (int i = 0; i < summary.length; i++) {
      setCell(i * 2, rowCursor, excel.TextCellValue(summary[i][0]), headerStyle);
      setCell(i * 2 + 1, rowCursor, excel.TextCellValue(summary[i][1]), rowStyle);
    }

    rowCursor += 2;

    final headers = [
      'PO No.',
      'Supplier',
      'Sales Invoice',
      'DR No.',
      'Warehouse',
      'Date',
      'Items',
      'Total',
    ];

    for (int c = 0; c < headers.length; c++) {
      setCell(c, rowCursor, excel.TextCellValue(headers[c]), headerStyle);
    }

    rowCursor++;

    for (int r = 0; r < rows.length; r++) {
      final d = rows[r];
      final style = r.isOdd ? altStyle : rowStyle;

      final values = [
        _na(d['po_number']),
        _na(d['supplier_name']),
        _na(d['invoice_no']),
        _na(d['dr_no']),
        _na(d['warehouse_name']),
        _formatDate(d['delivery_date']?.toString()),
        '${_toInt(d['item_count'])}',
        _toDouble(d['total_amount']),
      ];

      for (int c = 0; c < values.length; c++) {
        final value = values[c];

        if (value is double) {
          setCell(c, rowCursor, excel.DoubleCellValue(value), style);
        } else {
          setCell(c, rowCursor, excel.TextCellValue(value.toString()), style);
        }
      }

      rowCursor++;
    }

    if (includeItems) {
      rowCursor += 2;

      sheet.merge(
        excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowCursor),
        excel.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowCursor),
      );
      setCell(
        0,
        rowCursor,
        excel.TextCellValue('Delivered Item Breakdown'),
        titleStyle,
      );

      rowCursor += 2;

      final itemHeaders = [
        'PO No.',
        'Product Code',
        'Description',
        'Qty',
        'Unit Cost',
        'Subtotal',
      ];

      for (int c = 0; c < itemHeaders.length; c++) {
        setCell(c, rowCursor, excel.TextCellValue(itemHeaders[c]), headerStyle);
      }

      rowCursor++;

      int itemIndex = 0;

      for (final d in rows) {
        final items = _toList(d['items']);

        for (final item in items) {
          final qty = _toDouble(item['quantity']);
          final subtotal = _toDouble(item['total_cost'] ?? item['subtotal']);
          final unitCost = qty > 0 ? subtotal / qty : _toDouble(item['unit_price']);
          final style = itemIndex.isOdd ? altStyle : rowStyle;

          final values = [
            _na(d['po_number']),
            _na(item['product_code']),
            _cleanItemName(item['item_description']),
            qty,
            unitCost,
            subtotal,
          ];

          for (int c = 0; c < values.length; c++) {
            final value = values[c];

            if (value is double) {
              setCell(c, rowCursor, excel.DoubleCellValue(value), style);
            } else {
              setCell(c, rowCursor, excel.TextCellValue(value.toString()), style);
            }
          }

          rowCursor++;
          itemIndex++;
        }
      }
    }

    final dir = await _reportsDir();
    final fileName =
        'deliveries_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx';
    final file = File('${dir.path}/$fileName');

    final bytes = book.save();
    if (bytes == null) return;

    await file.writeAsBytes(bytes);

    if (!mounted) return;
    _showExportSnack(file.path, 'Excel');
  }
  Future<void> _exportPdfRows(
      List<Map<String, dynamic>> rows, {
        required bool includeItems,
      }) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        build: (_) {
          final widgets = <pw.Widget>[
            pw.Text(
              "THREE E'S TOYS - DELIVERY REPORT",
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Generated: ${DateFormat('MMMM d, yyyy h:mm a').format(DateTime.now())}',
              style: const pw.TextStyle(fontSize: 9),
            ),
            pw.SizedBox(height: 12),
            pw.Table.fromTextArray(
              headers: [
                'PO No.',
                'Supplier',
                'SI',
                'DR',
                'Warehouse',
                'Date',
                'Items',
                'Total',
              ],
              data: rows.map((d) {
                return [
                  _na(d['po_number']),
                  _na(d['supplier_name']),
                  _na(d['invoice_no']),
                  _na(d['dr_no']),
                  _na(d['warehouse_name']),
                  _formatDate(d['delivery_date']?.toString()),
                  '${_toInt(d['item_count'])}',
                  'PHP ${_peso.format(_toDouble(d['total_amount']))}',
                ];
              }).toList(),
              headerStyle: pw.TextStyle(
                fontSize: 8,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.black),
              cellStyle: const pw.TextStyle(fontSize: 7),
            ),
          ];

          if (includeItems) {
            widgets.add(pw.SizedBox(height: 18));
            widgets.add(
              pw.Text(
                'Delivered Item Breakdown',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            );
            widgets.add(pw.SizedBox(height: 8));

            final itemRows = <List<String>>[];

            for (final d in rows) {
              final items = _toList(d['items']);

              for (final item in items) {
                final qty = _toDouble(item['quantity']);
                final subtotal = _toDouble(item['total_cost'] ?? item['subtotal']);
                final unitCost =
                qty > 0 ? subtotal / qty : _toDouble(item['unit_price']);

                itemRows.add([
                  _na(d['po_number']),
                  _na(item['product_code']),
                  _na(item['item_description']),
                  qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2),
                  'PHP ${_peso.format(unitCost)}',
                  'PHP ${_peso.format(subtotal)}',
                ]);
              }
            }

            widgets.add(
              pw.Table.fromTextArray(
                headers: [
                  'PO No.',
                  'Code',
                  'Description',
                  'Qty',
                  'Unit Cost',
                  'Subtotal',
                ],
                data: itemRows,
                headerStyle: pw.TextStyle(
                  fontSize: 8,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.white,
                ),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.black),
                cellStyle: const pw.TextStyle(fontSize: 7),
              ),
            );
          }

          return widgets;
        },
      ),
    );

    final dir = await _reportsDir();
    final fileName =
        'deliveries_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.pdf';
    final file = File('${dir.path}/$fileName');

    await file.writeAsBytes(await pdf.save());

    if (!mounted) return;
    _showExportSnack(file.path, 'PDF');
  }
  Future<List<Map<String, dynamic>>> _attachDeliveryItems(
      List<Map<String, dynamic>> deliveries,
      ) async {
    final output = <Map<String, dynamic>>[];

    for (final d in deliveries) {
      final result = await DBService.instance.fetchDeliveryDetails(
        deliveryId: _toInt(d['delivery_id']),
      );

      final detail = Map<String, dynamic>.from(d);
      detail['items'] = result.success ? _toList(result.data?['items']) : [];

      output.add(detail);
    }

    return output;
  }

  Future<void> _runExport({
    required String format,
    required String scope,
    required bool includeItems,
  }) async {
    final rows = scope == 'current'
        ? _deliveries
        : await _fetchAllFilteredDeliveries();

    final exportRows = includeItems
        ? await _attachDeliveryItems(rows)
        : rows;

    if (format == 'pdf') {
      await _exportPdfRows(exportRows, includeItems: includeItems);
    } else {
      await _exportXlsxRows(exportRows, includeItems: includeItems);
    }
  }




  Future<void> _showExportOptions() async {
    String format = 'pdf';
    String scope = 'current';
    bool includeItems = true;

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: _surface,
              title: Text(
                'Export Deliveries',
                style: TextStyle(
                  color: _textHi,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Format',
                        style: TextStyle(
                          color: _textHi,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    RadioListTile<String>(
                      value: 'pdf',
                      groupValue: format,
                      activeColor: _blue,
                      onChanged: (v) {
                        setDialogState(() => format = v!);
                      },
                      title: Text(
                        'PDF',
                        style: TextStyle(color: _textHi),
                      ),
                    ),

                    RadioListTile<String>(
                      value: 'xlsx',
                      groupValue: format,
                      activeColor: _green,
                      onChanged: (v) {
                        setDialogState(() => format = v!);
                      },
                      title: Text(
                        'Excel',
                        style: TextStyle(color: _textHi),
                      ),
                    ),

                    const Divider(height: 28),

                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Scope',
                        style: TextStyle(
                          color: _textHi,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),

                    const SizedBox(height: 8),

                    RadioListTile<String>(
                      value: 'current',
                      groupValue: scope,
                      activeColor: _blue,
                      onChanged: (v) {
                        setDialogState(() => scope = v!);
                      },
                      title: Text(
                        'Current Page Only',
                        style: TextStyle(color: _textHi),
                      ),
                    ),

                    RadioListTile<String>(
                      value: 'all',
                      groupValue: scope,
                      activeColor: _blue,
                      onChanged: (v) {
                        setDialogState(() => scope = v!);
                      },
                      title: Text(
                        'All Filtered Deliveries',
                        style: TextStyle(color: _textHi),
                      ),
                    ),

                    const Divider(height: 28),

                    CheckboxListTile(
                      value: includeItems,
                      activeColor: _green,
                      controlAffinity: ListTileControlAffinity.leading,
                      onChanged: (v) {
                        setDialogState(() {
                          includeItems = v ?? false;
                        });
                      },
                      title: Text(
                        'Include Delivered Items',
                        style: TextStyle(color: _textHi),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Cancel',
                    style: TextStyle(color: _textLo),
                  ),
                ),

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);

                    await _runExport(
                      format: format,
                      scope: scope,
                      includeItems: includeItems,
                    );
                  },
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('Export'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _fetchAllFilteredDeliveries() async {
    final dfStr =
    _dateFrom == null ? '' : DateFormat('yyyy-MM-dd').format(_dateFrom!);
    final dtStr =
    _dateTo == null ? '' : DateFormat('yyyy-MM-dd').format(_dateTo!);

    final result = await DBService.instance.fetchDeliveries(
      search: _searchCtrl.text.trim(),
      dateFrom: dfStr,
      dateTo: dtStr,
      status: '',
      warehouseId: _selectedWarehouseId ?? 0,
      supplierId: 0,
      supplierSearch: _supplierCtrl.text.trim(),
      page: 1,
      limit: 100000,
    );

    if (!result.success) return [];

    return _toList(result.data?['deliveries']);
  }
  Future<void> _load({int page = 1}) async {
    if (!canViewDeliveries) {
      setState(() {
        _loading = false;
        _error = 'You do not have permission to view deliveries.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _page = page;
    });

    final dfStr =
    _dateFrom == null ? '' : DateFormat('yyyy-MM-dd').format(_dateFrom!);
    final dtStr =
    _dateTo == null ? '' : DateFormat('yyyy-MM-dd').format(_dateTo!);

    final result = await DBService.instance.fetchDeliveries(
      search: _searchCtrl.text.trim(),
      dateFrom: dfStr,
      dateTo: dtStr,
      status: _selectedStatus ?? '',
      warehouseId: _selectedWarehouseId ?? 0,
      supplierId: 0,
      supplierSearch: _supplierCtrl.text.trim(),
      page: page,
    );

    if (!mounted) return;

    setState(() {
      _loading = false;

      if (result.success) {
        _deliveries = _toList(result.data?['deliveries']);
        _warehouses = _toList(result.data?['warehouses']);
        _suppliers = _toList(result.data?['suppliers']);
        _stats = Map<String, dynamic>.from(result.data?['stats'] as Map? ?? {});
        _pagination = Map<String, dynamic>.from(
          result.data?['pagination'] as Map? ?? {},
        );
      } else {
        _error = result.message;
      }
    });
  }

  Future<void> _openDetail(Map<String, dynamic> delivery) async {
    setState(() {
      _detailLoading = true;
      _detail = delivery;
      _detailItems = [];
    });

    final result = await DBService.instance.fetchDeliveryDetails(
      deliveryId: _toInt(delivery['delivery_id']),
    );

    if (!mounted) return;

    final loadedDetail = result.success
        ? Map<String, dynamic>.from(result.data?['delivery'] as Map? ?? delivery)
        : delivery;

    final loadedItems = result.success
        ? _toList(result.data?['items'])
        : <Map<String, dynamic>>[];

    setState(() {
      _detailLoading = false;
      _detail = loadedDetail;
      _detailItems = loadedItems;
    });

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _DetailDialog(
        detail: loadedDetail,
        items: loadedItems,
      ),
    );
  }

  void _resetFilters() {
    _searchCtrl.clear();

    setState(() {
      _selectedStatus = null;
      _selectedWarehouseId = null;
      _selectedSupplierId = null;
      _dateFrom = null;
      _dateTo = null;
    });

    _load();
  }



  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();

    final picked = await showDatePicker(
      context: context,
      initialDate: from ? (_dateFrom ?? now) : (_dateTo ?? now),
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _blue,
              surface: _surface,
              onSurface: _textHi,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;

    setState(() {
      if (from) {
        _dateFrom = picked;
      } else {
        _dateTo = picked;
      }
    });

    _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _deliveries.isEmpty) {
      return Center(child: CircularProgressIndicator(color: _blue));
    }

    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: () => _load());
    }

    return Scaffold(
      backgroundColor: _bg,
      body: RefreshIndicator(
        color: _blue,
        backgroundColor: _surface,
        onRefresh: () => _load(page: _page),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverToBoxAdapter(child: _buildStats()),
            SliverToBoxAdapter(child: _buildFilterBar()),
            SliverToBoxAdapter(child: _buildContent()),
            SliverToBoxAdapter(child: _buildPagination()),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
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
                      'Deliveries',
                      style: TextStyle(
                        color: _textHi,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Delivery receiving records with supplier, SI, DR, PO, warehouse, and total cost.',
                      style: TextStyle(color: _textLo, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh',
                icon: Icon(Icons.refresh_rounded, color: _textLo),
                onPressed: () => _load(page: _page),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                ),
                onPressed: _showExportOptions,
                icon: const Icon(Icons.file_download_rounded, size: 16),
                label: const Text('Export'),
              ),
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildStats() {
    final totalDeliveries = _toInt(_stats['total_deliveries']);
    final totalAmount = _toDouble(_stats['total_amount']);
    final totalItems = _toInt(_stats['total_items']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MiniStat(
            label: 'Deliveries',
            value: '$totalDeliveries',
            color: _blue,
            icon: Icons.local_shipping_rounded,
          ),
          _MiniStat(
            label: 'Total Items',
            value: '$totalItems',
            color: _green,
            icon: Icons.inventory_2_rounded,
          ),
          _MiniStat(
            label: 'Total Cost',
            value: '₱${_peso.format(totalAmount)}',
            color: _amber,
            icon: Icons.payments_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: _textHi, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search PO, SI, DR, or supplier…',
                hintStyle: TextStyle(color: _textLo, fontSize: 13),
                prefixIcon: Icon(Icons.search_rounded, color: _textLo),
                filled: true,
                fillColor: _surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _blue),
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          if (_warehouses.isNotEmpty)
            _FilterDropdown<int>(
              value: _selectedWarehouseId ?? 0,
              items: [
                0,
                ..._warehouses.map((w) => _toInt(w['warehouse_id'])),
              ],
              labelOf: (id) {
                if (id == 0) return 'All Warehouses';

                final found = _warehouses.firstWhere(
                      (w) => _toInt(w['warehouse_id']) == id,
                  orElse: () => {},
                );

                return found['warehouse_name']?.toString() ?? 'Warehouse $id';
              },
              onChanged: (v) {
                setState(() => _selectedWarehouseId = v == 0 ? null : v);
                _load();
              },
            ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: TextField(
              controller: _supplierCtrl,
              style: TextStyle(color: _textHi, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search supplier…',
                hintStyle: TextStyle(color: _textLo, fontSize: 13),
                prefixIcon: Icon(Icons.business_rounded, color: _textLo),
                filled: true,
                fillColor: _surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _blue),
                ),
              ),
              onSubmitted: (_) => _load(),
            ),
          ),
          _DateButton(
            label: _dateFrom == null
                ? 'Date From'
                : DateFormat('MMM d, yyyy').format(_dateFrom!),
            onTap: () => _pickDate(from: true),
          ),
          _DateButton(
            label: _dateTo == null
                ? 'Date To'
                : DateFormat('MMM d, yyyy').format(_dateTo!),
            onTap: () => _pickDate(from: false),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _textHi,
              side: BorderSide(color: _border),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            onPressed: () => _load(),
            icon: const Icon(Icons.filter_alt_rounded, size: 16),
            label: const Text('Apply'),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: _red,
              side: BorderSide(color: _red.withOpacity(0.4)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
            onPressed: _resetFilters,
            icon: const Icon(Icons.clear_rounded, size: 16),
            label: const Text('Reset'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return SizedBox(
        height: 260,
        child: Center(child: CircularProgressIndicator(color: _blue)),
      );
    }

    if (_deliveries.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(30),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _border),
          ),
          child: Column(
            children: [
              Icon(Icons.local_shipping_outlined, color: _textLo, size: 48),
              const SizedBox(height: 12),
              Text(
                'No deliveries found',
                style: TextStyle(
                  color: _textHi,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Try changing your filters.',
                style: TextStyle(color: _textLo, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 850;
    return isWide ? _buildTable() : _buildCards();
  }

  Widget _buildTable() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: const Row(
                children: [
                  _TableHead('PO No.', flex: 2),
                  _TableHead('Supplier', flex: 2),
                  _TableHead('Sales Invoice', flex: 2),
                  _TableHead('DR', flex: 2),
                  _TableHead('Warehouse', flex: 2),
                  _TableHead('Date', flex: 2),
                  _TableHead('Items', flex: 1, center: true),
                  _TableHead('Total', flex: 2, right: true),
                  _TableHead('', flex: 1),
                ],
              ),
            ),
            ..._deliveries.asMap().entries.map((entry) {
              final index = entry.key;
              final d = entry.value;

              return InkWell(
                onTap: () => _openDetail(d),
                child: Column(
                  children: [
                    if (index > 0) Divider(height: 1, color: _border),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              _na(d['po_number']),
                              style: TextStyle(
                                color: _blue,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _na(d['supplier_name']),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _textHi,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _na(d['invoice_no']),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _amber,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _na(d['dr_no']),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _teal,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _na(d['warehouse_name']),
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _textHi,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _formatDate(d['delivery_date']?.toString()),
                              style: TextStyle(
                                color: _textLo,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Text(
                              '${_toInt(d['item_count'])}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: _textHi,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Text(
                              '₱${_peso.format(_toDouble(d['total_amount']))}',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: _textHi,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 1,
                            child: Icon(
                              Icons.chevron_right_rounded,
                              color: _textLo,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildCards() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Column(
        children: _deliveries.map((d) {
          return InkWell(
            onTap: () => _openDetail(d),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _na(d['po_number']),
                          style: TextStyle(
                            color: _blue,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _CardRow(
                    icon: Icons.business_rounded,
                    label: 'Supplier: ${_na(d['supplier_name'])}',
                  ),
                  _CardRow(
                    icon: Icons.receipt_long_rounded,
                    label: 'SI: ${_na(d['invoice_no'])}',
                  ),
                  _CardRow(
                    icon: Icons.description_rounded,
                    label: 'DR: ${_na(d['dr_no'])}',
                  ),
                  _CardRow(
                    icon: Icons.warehouse_rounded,
                    label: 'Warehouse: ${_na(d['warehouse_name'])}',
                  ),
                  _CardRow(
                    icon: Icons.calendar_today_rounded,
                    label: _formatDate(d['delivery_date']?.toString()),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        '${_toInt(d['item_count'])} item(s)',
                        style: TextStyle(color: _textLo, fontSize: 12),
                      ),
                      const Spacer(),
                      Text(
                        '₱${_peso.format(_toDouble(d['total_amount']))}',
                        style: TextStyle(
                          color: _textHi,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPagination() {
    final totalPages = _toInt(_pagination['total_pages']);
    final totalRecords = _toInt(
      _pagination['total_records'] ?? _pagination['total_rows'],
    );

    if (totalPages <= 1) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            'Total: $totalRecords',
            style: TextStyle(color: _textLo, fontSize: 12),
          ),
          const SizedBox(width: 14),
          _PageButton(
            label: '<',
            enabled: _page > 1,
            onTap: () => _load(page: _page - 1),
          ),
          const SizedBox(width: 8),
          Text(
            'Page $_page of $totalPages',
            style: TextStyle(color: _textHi, fontSize: 13),
          ),
          const SizedBox(width: 8),
          _PageButton(
            label: '>',
            enabled: _page < totalPages,
            onTap: () => _load(page: _page + 1),
          ),
        ],
      ),
    );
  }
}

class _DetailSheet extends StatelessWidget {
  final bool loading;
  final Map<String, dynamic> detail;
  final List<Map<String, dynamic>> items;

  const _DetailSheet({
    required this.loading,
    required this.detail,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return SizedBox(
        height: MediaQuery.of(context).size.height * 0.45,
        child: Center(child: CircularProgressIndicator(color: _blue)),
      );
    }

    final total = _toDouble(detail['total_amount']);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (context, controller) {
        return SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _na(detail['po_number']),
                      style: TextStyle(
                        color: _textHi,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(detail['delivery_date']?.toString()),
                style: TextStyle(color: _textLo, fontSize: 12),
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetaTile(
                    label: 'Supplier',
                    value: _na(detail['supplier_name']),
                    icon: Icons.business_rounded,
                    color: _teal,
                  ),
                  _MetaTile(
                    label: 'Sales Invoice',
                    value: _na(detail['invoice_no']),
                    icon: Icons.receipt_long_rounded,
                    color: _amber,
                  ),
                  _MetaTile(
                    label: 'DR Number',
                    value: _na(detail['dr_no']),
                    icon: Icons.description_rounded,
                    color: _blue,
                  ),
                  _MetaTile(
                    label: 'Warehouse',
                    value: _na(detail['warehouse_name']),
                    icon: Icons.warehouse_rounded,
                    color: _green,
                  ),
                  _MetaTile(
                    label: 'Received By',
                    value: _na(detail['received_by']),
                    icon: Icons.person_rounded,
                    color: _red,
                  ),
                  _MetaTile(
                    label: 'Total Cost',
                    value: '₱${_peso.format(total)}',
                    icon: Icons.payments_rounded,
                    color: _amber,
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                'Items',
                style: TextStyle(
                  color: _textHi,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              if (items.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                  ),
                  child: Text(
                    'No items found.',
                    style: TextStyle(color: _textLo),
                  ),
                )
              else
                ...items.map((item) {
                  final qty = _toDouble(item['quantity']);
                  final totalCost = _toDouble(item['total_cost']);
                  final unitCost = qty > 0 ? totalCost / qty : 0;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _blue.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.inventory_2_rounded,
                            color: _blue,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _na(item['product_code']),
                                style: TextStyle(
                                  color: _teal,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _cleanItemName(item['item_description']),
                                style: TextStyle(
                                  color: _textHi,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Qty: ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2)} PCS',
                                style: TextStyle(
                                  color: _textLo,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₱${_peso.format(totalCost)}',
                              style: TextStyle(
                                color: _textHi,
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '₱${_peso.format(unitCost)} / unit',
                              style: TextStyle(
                                color: _textLo,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  const _FilterDropdown({
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: DropdownButton<T>(
        value: value,
        underline: const SizedBox(),
        dropdownColor: _surface,
        icon: Icon(Icons.keyboard_arrow_down_rounded, color: _textLo),
        style: TextStyle(color: _textHi, fontSize: 13),
        items: items
            .map(
              (item) => DropdownMenuItem<T>(
            value: item,
            child: Text(labelOf(item)),
          ),
        )
            .toList(),
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DateButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      style: OutlinedButton.styleFrom(
        foregroundColor: _textHi,
        side: BorderSide(color: _border),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      onPressed: onTap,
      icon: const Icon(Icons.calendar_today_rounded, size: 16),
      label: Text(label),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: _textLo, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _TableHead extends StatelessWidget {
  final String text;
  final int flex;
  final bool right;
  final bool center;

  const _TableHead(
      this.text, {
        this.flex = 1,
        this.right = false,
        this.center = false,
      });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: right
            ? TextAlign.right
            : center
            ? TextAlign.center
            : TextAlign.left,
        style: TextStyle(
          color: _textLo,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _CardRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CardRow({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          Icon(icon, color: _textLo, size: 15),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: _textLo, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;

  const _StatusBadge({
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final s = status.trim().toUpperCase();
    final color = s == 'POSTED'
        ? _green
        : s == 'CANCELLED'
        ? _red
        : _amber;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        s.isEmpty ? 'POSTED' : s,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _MetaTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _MetaTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: _textLo, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: _textHi,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailDialog extends StatelessWidget {
  final Map<String, dynamic> detail;
  final List<Map<String, dynamic>> items;

  const _DetailDialog({
    required this.detail,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width < 700;
    final total = _toDouble(detail['total_amount']);

    return Dialog(
      insetPadding: EdgeInsets.all(isMobile ? 0 : 28),
      backgroundColor: Colors.transparent,
      child: Container(
        width: isMobile ? double.infinity : 980,
        height: isMobile ? double.infinity : 680,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(isMobile ? 0 : 22),
          border: Border.all(color: _border),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 14, 16),
              decoration: BoxDecoration(
                color: _bg,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(isMobile ? 0 : 22),
                ),
                border: Border(bottom: BorderSide(color: _border)),
              ),
              child: Row(
                children: [
                  Icon(Icons.local_shipping_rounded, color: _blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Delivery Details - ${_na(detail['po_number'])}',
                      style: TextStyle(
                        color: _textHi,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _StatusBadge(status: detail['status']?.toString() ?? ''),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: _textLo),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MetaTile(
                          label: 'Supplier',
                          value: _na(detail['supplier_name']),
                          icon: Icons.business_rounded,
                          color: _teal,
                        ),
                        _MetaTile(
                          label: 'Sales Invoice',
                          value: _na(detail['invoice_no']),
                          icon: Icons.receipt_long_rounded,
                          color: _amber,
                        ),
                        _MetaTile(
                          label: 'DR Number',
                          value: _na(detail['dr_no']),
                          icon: Icons.description_rounded,
                          color: _blue,
                        ),
                        _MetaTile(
                          label: 'Warehouse',
                          value: _na(detail['warehouse_name']),
                          icon: Icons.warehouse_rounded,
                          color: _green,
                        ),
                        _MetaTile(
                          label: 'Received By',
                          value: _na(detail['received_by']),
                          icon: Icons.person_rounded,
                          color: _red,
                        ),
                        _MetaTile(
                          label: 'Delivery Date',
                          value: _formatDate(detail['delivery_date']?.toString()),
                          icon: Icons.calendar_today_rounded,
                          color: _blue,
                        ),
                        _MetaTile(
                          label: 'Total Cost',
                          value: '₱${_peso.format(total)}',
                          icon: Icons.payments_rounded,
                          color: _amber,
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    Row(
                      children: [
                        Text(
                          'Delivered Items',
                          style: TextStyle(
                            color: _textHi,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _blue.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${items.length}',
                            style: TextStyle(
                              color: _blue,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    if (items.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: _bg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: _border),
                        ),
                        child: Text(
                          'No items found.',
                          style: TextStyle(color: _textLo),
                        ),
                      )
                    else if (isMobile)
                      Column(
                        children: items.map((item) {
                          return _DeliveryItemCard(item: item);
                        }).toList(),
                      )
                    else
                      _DeliveryItemsTable(items: items),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeliveryItemsTable extends StatelessWidget {
  final List<Map<String, dynamic>> items;

  const _DeliveryItemsTable({
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(14),
              ),
            ),
            child: const Row(
              children: [
                _TableHead('Product Code', flex: 2),
                _TableHead('Description', flex: 4),
                _TableHead('Qty', flex: 1, center: true),
                _TableHead('Unit Cost', flex: 2, right: true),
                _TableHead('Total', flex: 2, right: true),
              ],
            ),
          ),
          ...items.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            final qty = _toDouble(item['quantity']);
            final totalCost = _toDouble(item['total_cost']);
            final unitCost = qty > 0 ? totalCost / qty : 0;

            return Column(
              children: [
                if (index > 0) Divider(height: 1, color: _border),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 13,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          _na(item['product_code']),
                          style: TextStyle(
                            color: _teal,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: Text(
                          _cleanItemName(item['item_description']),
                          style: TextStyle(
                            color: _textHi,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Text(
                          qty.toStringAsFixed(
                            qty == qty.roundToDouble() ? 0 : 2,
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: _textHi, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '₱${_peso.format(unitCost)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: _textLo, fontSize: 12),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '₱${_peso.format(totalCost)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: _textHi,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
class _DeliveryItemCard extends StatelessWidget {
  final Map<String, dynamic> item;

  const _DeliveryItemCard({
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final qty = _toDouble(item['quantity']);
    final totalCost = _toDouble(item['total_cost']);
    final unitCost = qty > 0 ? totalCost / qty : 0;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _na(item['product_code']),
            style: TextStyle(
              color: _teal,
              fontSize: 12,
              fontWeight: FontWeight.w800,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _na(item['item_description']),
            style: TextStyle(
              color: _textHi,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Qty: ${qty.toStringAsFixed(qty == qty.roundToDouble() ? 0 : 2)}',
                style: TextStyle(color: _textLo, fontSize: 12),
              ),
              const Spacer(),
              Text(
                '₱${_peso.format(totalCost)}',
                style: TextStyle(
                  color: _textHi,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              '₱${_peso.format(unitCost)} / unit',
              style: TextStyle(color: _textLo, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
class _PageButton extends StatelessWidget {
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  const _PageButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _surface,
          shape: BoxShape.circle,
          border: Border.all(color: _border),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: enabled ? _textHi : _textLo,
              fontWeight: FontWeight.w800,
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

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

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
}