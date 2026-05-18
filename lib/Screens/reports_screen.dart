import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as excel;

import '../db/env.dart';
import '../Utils/app_theme.dart';

final _peso = NumberFormat('#,##0.00', 'en_PH');
final _dateFmt = DateFormat('MMM dd, yyyy');
final _fileFmt = DateFormat('MMMdd_yyyy');

final List<int> _limitOptions = [10, 20, 50, 100];

class ReportFilterState {
  DateTime? dateFrom;
  DateTime? dateTo;
  int? storeId;
  int? warehouseId;
  int threshold;
  int page;
  int limit;

  ReportFilterState({
    this.dateFrom,
    this.dateTo,
    this.storeId,
    this.warehouseId,
    this.threshold = 10,
    this.page = 1,
    this.limit = 10,
  });
}

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
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

List<Map<String, dynamic>> _toList(dynamic v) =>
    (v as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ??
        [];

bool get _isWindows {
  try {
    return !kIsWeb && Platform.isWindows;
  } catch (_) {
    return false;
  }
}

enum ReportType {
  dailySales,
  salesPerClerk,
  promoSales,
  transfer,
  refund,
  disposal,
  lowStock,
  badOrder,
}

extension ReportTypeExt on ReportType {
  String get label => switch (this) {
    ReportType.dailySales => 'Daily Sales Report',
    ReportType.salesPerClerk => 'Sales Per Clerk',
    ReportType.promoSales => 'Promo Sales Report',
    ReportType.transfer => 'Warehouse Transfer Report',
    ReportType.refund => 'Refund Report',
    ReportType.disposal => 'Disposal Report',
    ReportType.lowStock => 'Low Stock Alert',
    ReportType.badOrder => 'Bad Order Report',
  };

  String get apiKey => switch (this) {
    ReportType.dailySales => 'daily_sales',
    ReportType.salesPerClerk => 'sales_per_clerk',
    ReportType.promoSales => 'promo_sales',
    ReportType.transfer => 'transfer',
    ReportType.refund => 'refund',
    ReportType.disposal => 'disposal',
    ReportType.lowStock => 'low_stock',
    ReportType.badOrder => 'bad_order',
  };

  IconData get icon => switch (this) {
    ReportType.dailySales => Icons.bar_chart_rounded,
    ReportType.salesPerClerk => Icons.people_rounded,
    ReportType.promoSales => Icons.local_offer_rounded,
    ReportType.transfer => Icons.swap_horiz_rounded,
    ReportType.refund => Icons.assignment_return_rounded,
    ReportType.disposal => Icons.delete_sweep_rounded,
    ReportType.lowStock => Icons.warning_amber_rounded,
    ReportType.badOrder => Icons.inventory_2_rounded,
  };

  Color get color => switch (this) {
    ReportType.dailySales => AppColors.blue,
    ReportType.salesPerClerk => AppColors.green,
    ReportType.promoSales => AppColors.teal,
    ReportType.transfer => AppColors.purple,
    ReportType.refund => AppColors.amber,
    ReportType.disposal => AppColors.orange,
    ReportType.lowStock => AppColors.red,
    ReportType.badOrder => AppColors.purple,
  };
}

Future<Map<String, dynamic>> _fetchReport(
    ReportType type, {
      String dateFrom = '',
      String dateTo = '',
      int storeId = 0,
      int warehouseId = 0,
      int threshold = 10,
      int page = 1,
      int limit = 10,
    }) async {
  final params = <String, String>{
    'report': type.apiKey,
    'page': '$page',
    'limit': '$limit',
  };

  if (dateFrom.isNotEmpty) params['date_from'] = dateFrom;
  if (dateTo.isNotEmpty) params['date_to'] = dateTo;
  if (storeId > 0) params['store_id'] = '$storeId';
  if (warehouseId > 0) params['warehouse_id'] = '$warehouseId';
  if (type == ReportType.lowStock) params['threshold'] = '$threshold';

  final uri =
  Uri.parse('${ENV.API_BASE_URL}/reports.php').replace(queryParameters: params);

  final response = await http.get(uri).timeout(const Duration(seconds: 30));
  return jsonDecode(response.body) as Map<String, dynamic>;
}

class ReportsScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;

  const ReportsScreen({super.key, this.currentUser});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportType _selected = ReportType.dailySales;
  bool _loading = false;
  String? _error;
  Map<String, dynamic> _data = {};

  final Map<ReportType, ReportFilterState> _filters = {
    for (final type in ReportType.values) type: ReportFilterState(),
  };

  ReportFilterState get _filter => _filters[_selected]!;

  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _warehouses = [];

  bool _exportingPdf = false;

  @override
  void initState() {
    super.initState();

    final allowed = _allowedReports;

    if (allowed.isNotEmpty) {
      _selected = allowed.first;
      _load();
    } else {
      _loading = false;
      _error = 'You do not have permission to view reports.';
    }
  }

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

  String _permissionForReport(ReportType type) {
    switch (type) {
      case ReportType.dailySales:
        return 'REPORT_DAILY_SALES';
      case ReportType.salesPerClerk:
        return 'REPORT_SALES_PER_CLERK';
      case ReportType.promoSales:
        return 'REPORT_PROMO_SALES';
      case ReportType.transfer:
        return 'REPORT_WAREHOUSE_TRANSFER';
      case ReportType.refund:
        return 'REPORT_REFUND';
      case ReportType.disposal:
        return 'REPORT_DISPOSAL';
      case ReportType.lowStock:
        return 'REPORT_LOW_STOCK';
      case ReportType.badOrder:
        return 'REPORT_BAD_ORDER';
    }
  }

  bool get canViewReportsModule => hasPermission('REPORT_VIEW');

  bool canViewReport(ReportType type) {
    return hasPermission(_permissionForReport(type));
  }

  List<ReportType> get _allowedReports {
    return ReportType.values.where(canViewReport).toList();
  }

  bool get canExportReports {
    return canViewReport(_selected);
  }

  bool get _selectedHasItemBreakdown {
    return [
      ReportType.dailySales,
      ReportType.promoSales,   // ← ADD
      ReportType.transfer,
      ReportType.refund,
      ReportType.disposal,
      ReportType.badOrder,
    ].contains(_selected);
  }

  Future<void> _showReportExportOptions() async {
    String format = 'pdf';
    bool includeBreakdown = true;

    await showDialog(
      context: context,
      builder: (_) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final t = themeNotifier.theme;

            return AlertDialog(
              backgroundColor: t.surface,
              title: Text(
                'Export Report',
                style: TextStyle(
                  color: t.textHi,
                  fontWeight: FontWeight.w800,
                ),
              ),
              content: SizedBox(
                width: 370,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Format',
                      style: TextStyle(
                        color: t.textHi,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    RadioListTile<String>(
                      value: 'pdf',
                      groupValue: format,
                      activeColor: t.blue,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setDialogState(() => format = v!),
                      title: Text('PDF', style: TextStyle(color: t.textHi)),
                    ),
                    RadioListTile<String>(
                      value: 'xlsx',
                      groupValue: format,
                      activeColor: t.green,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: (v) => setDialogState(() => format = v!),
                      title: Text('Excel', style: TextStyle(color: t.textHi)),
                    ),
                    if (_selectedHasItemBreakdown) ...[
                      const Divider(height: 24),
                      CheckboxListTile(
                        value: includeBreakdown,
                        activeColor: t.green,
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        onChanged: (v) {
                          setDialogState(() => includeBreakdown = v ?? false);
                        },
                        title: Text(
                          'Include item breakdown',
                          style: TextStyle(color: t.textHi),
                        ),
                        subtitle: Text(
                          'Adds item-level rows when this report has item details.',
                          style: TextStyle(color: t.textLo, fontSize: 11),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(color: t.textLo)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.green,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () async {
                    Navigator.pop(context);

                    if (format == 'pdf') {
                      await _exportPdf(includeBreakdown: includeBreakdown);
                    } else {
                      await _exportXlsx(includeBreakdown: includeBreakdown);
                    }
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

  Future<void> _load() async {
    if (!canViewReport(_selected)) {
      setState(() {
        _loading = false;
        _error = 'You do not have permission to view this report.';
        _data = {};
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final f = _filter;

      final dfStr =
      f.dateFrom != null ? DateFormat('yyyy-MM-dd').format(f.dateFrom!) : '';
      final dtStr =
      f.dateTo != null ? DateFormat('yyyy-MM-dd').format(f.dateTo!) : '';

      final result = await _fetchReport(
        _selected,
        dateFrom: dfStr,
        dateTo: dtStr,
        storeId: f.storeId ?? 0,
        warehouseId: f.warehouseId ?? 0,
        threshold: f.threshold,
        page: f.page,
        limit: f.limit,
      );

      if (!mounted) return;

      setState(() {
        _loading = false;

        if (result['success'] == true) {
          _data = result;
          if (result['stores'] != null) _stores = _toList(result['stores']);
          if (result['warehouses'] != null) {
            _warehouses = _toList(result['warehouses']);
          }
        } else {
          _error = result['message'] ?? 'Unknown error';
          _data = result;
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Error: $e';
      });
    }
  }

  void _selectReport(ReportType type) {
    setState(() {
      _selected = type;
      _data = {};
    });
    _load();
  }

  Future<void> _pickDate({required bool isFrom, required AppTheme t}) async {
    final f = _filter;

    final initial =
    isFrom ? (f.dateFrom ?? DateTime.now()) : (f.dateTo ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: themeNotifier.isDark
            ? ThemeData.dark().copyWith(
          colorScheme: ColorScheme.dark(primary: t.blue),
        )
            : ThemeData.light().copyWith(
          colorScheme: ColorScheme.light(primary: t.blue),
        ),
        child: child!,
      ),
    );

    if (picked == null) return;

    setState(() {
      if (isFrom) {
        f.dateFrom = picked;
      } else {
        f.dateTo = picked;
      }
      f.page = 1;
    });

    _load();
  }

  void _showExportSnack(String path, String type) {
    final t = themeNotifier.theme;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$type saved: $path'),
        backgroundColor: t.green,
        action: SnackBarAction(
          label: 'Open',
          textColor: Colors.white,
          onPressed: () => OpenFile.open(path),
        ),
      ),
    );
  }

  Future<void> _exportXlsx({bool includeBreakdown = true}) async {
    try {
      final rows = _toList(
        _selected == ReportType.lowStock ? _data['all'] : _data['rows'],
      );

      final book = excel.Excel.createExcel();
      book.rename('Sheet1', 'Report');
      final sheet = book['Report'];

      excel.Sheet? breakdownSheet;
      if (includeBreakdown && _selectedHasItemBreakdown) {
        breakdownSheet = book['Breakdown'];
      }

      final titleStyle = excel.CellStyle(
        bold: true,
        fontSize: 16,
        fontColorHex: excel.ExcelColor.fromHexString('#1F3864'),
        horizontalAlign: excel.HorizontalAlign.Center,
        verticalAlign: excel.VerticalAlign.Center,
      );

      final subtitleStyle = excel.CellStyle(
        fontSize: 11,
        fontColorHex: excel.ExcelColor.fromHexString('#44546A'),
        horizontalAlign: excel.HorizontalAlign.Center,
        verticalAlign: excel.VerticalAlign.Center,
      );

      final metaStyle = excel.CellStyle(
        fontSize: 9,
        fontColorHex: excel.ExcelColor.fromHexString('#808080'),
        horizontalAlign: excel.HorizontalAlign.Center,
        verticalAlign: excel.VerticalAlign.Center,
      );

      final headerStyle = excel.CellStyle(
        bold: true,
        fontSize: 10,
        fontColorHex: excel.ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: excel.ExcelColor.fromHexString('#1F3864'),
        horizontalAlign: excel.HorizontalAlign.Center,
        verticalAlign: excel.VerticalAlign.Center,
        textWrapping: excel.TextWrapping.WrapText,
      );

      final rowStyle = excel.CellStyle(
        fontSize: 10,
        backgroundColorHex: excel.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: excel.HorizontalAlign.Left,
        verticalAlign: excel.VerticalAlign.Center,
      );

      final rowAltStyle = excel.CellStyle(
        fontSize: 10,
        backgroundColorHex: excel.ExcelColor.fromHexString('#DCE6F1'),
        horizontalAlign: excel.HorizontalAlign.Left,
        verticalAlign: excel.VerticalAlign.Center,
      );

      final rightStyle = excel.CellStyle(
        fontSize: 10,
        backgroundColorHex: excel.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: excel.HorizontalAlign.Right,
        verticalAlign: excel.VerticalAlign.Center,
      );

      final rightAltStyle = excel.CellStyle(
        fontSize: 10,
        backgroundColorHex: excel.ExcelColor.fromHexString('#DCE6F1'),
        horizontalAlign: excel.HorizontalAlign.Right,
        verticalAlign: excel.VerticalAlign.Center,
      );

      final centerStyle = excel.CellStyle(
        fontSize: 10,
        backgroundColorHex: excel.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: excel.HorizontalAlign.Center,
        verticalAlign: excel.VerticalAlign.Center,
      );

      final centerAltStyle = excel.CellStyle(
        fontSize: 10,
        backgroundColorHex: excel.ExcelColor.fromHexString('#DCE6F1'),
        horizontalAlign: excel.HorizontalAlign.Center,
        verticalAlign: excel.VerticalAlign.Center,
      );

      void setCell(
          excel.Sheet target,
          int col,
          int row,
          excel.CellValue value,
          excel.CellStyle style,
          ) {
        target
            .cell(
          excel.CellIndex.indexByColumnRow(
            columnIndex: col,
            rowIndex: row,
          ),
        )
          ..value = value
          ..cellStyle = style;
      }

      void writeTitle(excel.Sheet target, int lastCol, String title) {
        target.merge(
          excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
          excel.CellIndex.indexByColumnRow(columnIndex: lastCol, rowIndex: 0),
        );

        setCell(target, 0, 0, excel.TextCellValue("THREE E'S TOYS"), titleStyle);
        target.setRowHeight(0, 28);

        target.merge(
          excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1),
          excel.CellIndex.indexByColumnRow(columnIndex: lastCol, rowIndex: 1),
        );

        setCell(target, 0, 1, excel.TextCellValue(title), subtitleStyle);
        target.setRowHeight(1, 20);

        target.merge(
          excel.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2),
          excel.CellIndex.indexByColumnRow(columnIndex: lastCol, rowIndex: 2),
        );

        setCell(
          target,
          0,
          2,
          excel.TextCellValue(
            'Generated on: ${DateFormat('MMMM d, yyyy  hh:mm a').format(DateTime.now())}',
          ),
          metaStyle,
        );

        target.setRowHeight(2, 18);
        target.setRowHeight(3, 8);
      }

      void writeHeader(
          excel.Sheet target,
          List<String> headers,
          int rowIndex,
          ) {
        for (int c = 0; c < headers.length; c++) {
          setCell(
            target,
            c,
            rowIndex,
            excel.TextCellValue(headers[c]),
            headerStyle,
          );
        }

        target.setRowHeight(rowIndex, 28);
      }

      List<String> headers = [];
      List<List<dynamic>> dataRows = [];
      List<int> rightCols = [];
      List<int> centerCols = [];

      switch (_selected) {
        case ReportType.dailySales:
          headers = [
            'Date',
            'Transactions',
            'Customers',
            'Gross',
            'Refunds',
            'Net Sales',
          ];
          rightCols = [3, 4, 5];
          centerCols = [1, 2];
          dataRows = rows.map((r) {
            return [
              r['sale_date']?.toString() ?? '-',
              _toInt(r['transaction_count']),
              _toInt(r['unique_customers']),
              _toDouble(r['gross_sales']),
              _toDouble(r['refunds']),
              _toDouble(r['net_sales']),
            ];
          }).toList();
          break;

        case ReportType.salesPerClerk:
          headers = [
            'Clerk Name',
            'Transactions',
            'Gross',
            'Refunds',
            'Net Sales',
            'Avg Sale',
          ];
          rightCols = [2, 3, 4, 5];
          centerCols = [1];
          dataRows = rows.map((r) {
            return [
              r['full_name']?.toString() ?? '-',
              _toInt(r['transaction_count']),
              _toDouble(r['gross_sales']),
              _toDouble(r['refunds']),
              _toDouble(r['net_sales']),
              _toDouble(r['avg_sale']),
            ];
          }).toList();
          break;

        case ReportType.promoSales:
          headers = [
            'Promo No.', 'Promo Name', 'Supplier', 'Type',
            'Date From', 'Date To', 'Status', 'Txns', 'Qty', 'Discount', 'Revenue',
          ];
          rightCols = [9, 10];
          centerCols = [7, 8];
          dataRows = rows.map((r) {
            return [
              r['promo_no']?.toString() ?? '-',
              r['promo_name']?.toString() ?? '-',
              r['supplier_name']?.toString() ?? '-',
              r['calculation_name']?.toString() ?? '-',
              _formatDateStr(r['date_from']?.toString()),
              _formatDateStr(r['date_to']?.toString()),
              r['promo_status']?.toString() ?? '-',
              _toInt(r['transaction_count']),
              _toDouble(r['total_qty']),
              _toDouble(r['total_discount']),
              _toDouble(r['total_revenue']),
            ];
          }).toList();
          break;

        case ReportType.transfer:
          headers = [
            'Transfer No.',
            'Date',
            'Warehouse',
            'Store',
            'By',
            'Value',
          ];
          rightCols = [5];
          dataRows = rows.map((r) {
            return [
              r['transfer_no']?.toString() ?? '-',
              _formatDateStr(r['transfer_date']?.toString()),
              r['warehouse_name']?.toString() ?? '-',
              r['store_name']?.toString() ?? '-',
              r['transferred_by']?.toString() ?? '-',
              _toDouble(r['total_value']),
            ];
          }).toList();
          break;

        case ReportType.refund:
          headers = [
            'Refund ID',
            'Txn No.',
            'Type',
            'Store',
            'Original Cashier',
            'Processed By',
            'Amount',
          ];
          rightCols = [6];
          centerCols = [0];
          dataRows = rows.map((r) {
            return [
              _toInt(r['refund_id']),
              r['transaction_no']?.toString() ?? '-',
              r['refund_type']?.toString() ?? '-',
              r['store_name']?.toString() ?? '-',
              r['original_cashier']?.toString() ?? '-',
              r['processed_by']?.toString() ?? '-',
              _toDouble(r['total_amount']),
            ];
          }).toList();
          break;

        case ReportType.disposal:
          headers = [
            'Date',
            'Store',
            'Reason',
            'Disposed By',
            'Items',
            'Total Loss',
          ];
          rightCols = [5];
          centerCols = [4];
          dataRows = rows.map((r) {
            return [
              _formatDateStr(r['disposal_date']?.toString()),
              r['store_name']?.toString() ?? '-',
              r['reason']?.toString() ?? '-',
              r['disposed_by']?.toString() ?? '-',
              _toInt(r['item_count']),
              _toDouble(r['total_loss']),
            ];
          }).toList();
          break;

        case ReportType.lowStock:
          headers = [
            'Source',
            'Location',
            'Code',
            'Description',
            'Qty',
            'Unit Price',
          ];
          rightCols = [5];
          centerCols = [4];
          dataRows = rows.map((r) {
            return [
              r['source']?.toString() ?? '-',
              r['location_name']?.toString() ?? '-',
              r['product_code']?.toString() ?? '-',
              _cleanItemName(r['item_description']),
              _toInt(r['quantity']),
              _toDouble(r['unit_price']),
            ];
          }).toList();
          break;

        case ReportType.badOrder:
          headers = [
            'BO No.',
            'Date',
            'Store',
            'Supplier',
            'Created By',
            'Items',
            'Qty',
            'Amount',
          ];
          rightCols = [7];
          centerCols = [5, 6];
          dataRows = rows.map((r) {
            return [
              r['bo_no']?.toString() ?? '-',
              _formatDateStr(r['created_at']?.toString()),
              r['store_name']?.toString() ?? '-',
              r['supplier_name']?.toString().isNotEmpty == true
                  ? r['supplier_name'].toString()
                  : '-',
              r['created_by']?.toString() ?? '-',
              _toInt(r['item_count']),
              _toDouble(r['total_qty']),
              _toDouble(r['total_amount']),
            ];
          }).toList();
          break;
      }

      for (int c = 0; c < headers.length; c++) {
        sheet.setColumnWidth(c, c == 3 ? 35 : 20);
      }

      writeTitle(sheet, headers.length - 1, _selected.label);
      writeHeader(sheet, headers, 4);

      for (int r = 0; r < dataRows.length; r++) {
        final row = dataRows[r];
        final rowIndex = r + 5;
        final isAlt = r.isOdd;

        for (int c = 0; c < row.length; c++) {
          final value = row[c];
          final style = rightCols.contains(c)
              ? (isAlt ? rightAltStyle : rightStyle)
              : centerCols.contains(c)
              ? (isAlt ? centerAltStyle : centerStyle)
              : (isAlt ? rowAltStyle : rowStyle);

          if (value is int) {
            setCell(sheet, c, rowIndex, excel.IntCellValue(value), style);
          } else if (value is double) {
            setCell(sheet, c, rowIndex, excel.DoubleCellValue(value), style);
          } else {
            setCell(
              sheet,
              c,
              rowIndex,
              excel.TextCellValue(value.toString()),
              style,
            );
          }
        }

        sheet.setRowHeight(rowIndex, 20);
      }

      if (includeBreakdown &&
          _selectedHasItemBreakdown &&
          breakdownSheet != null) {
        switch (_selected) {
          case ReportType.dailySales:
            final itemRows = _toList(_data['all_items']);

            for (int c = 0; c < 4; c++) {
              breakdownSheet.setColumnWidth(c, c == 1 ? 45 : 20);
            }

            writeTitle(
              breakdownSheet,
              3,
              '${_selected.label} - Item Breakdown',
            );

            writeHeader(
              breakdownSheet,
              ['Code', 'Item Name', 'Qty Sold', 'Revenue'],
              4,
            );

            for (int i = 0; i < itemRows.length; i++) {
              final item = itemRows[i];
              final row = i + 5;
              final isAlt = i.isOdd;

              setCell(
                breakdownSheet,
                0,
                row,
                excel.TextCellValue(item['product_code']?.toString() ?? '-'),
                isAlt ? rowAltStyle : rowStyle,
              );

              setCell(
                breakdownSheet,
                1,
                row,
                excel.TextCellValue(_cleanItemName(item['item_name'])),
                isAlt ? rowAltStyle : rowStyle,
              );

              setCell(
                breakdownSheet,
                2,
                row,
                excel.DoubleCellValue(_toDouble(item['total_qty'])),
                isAlt ? centerAltStyle : centerStyle,
              );

              setCell(
                breakdownSheet,
                3,
                row,
                excel.DoubleCellValue(_toDouble(item['total_revenue'])),
                isAlt ? rightAltStyle : rightStyle,
              );
            }
            break;

          case ReportType.promoSales:
            for (int c = 0; c < 8; c++) {
              breakdownSheet.setColumnWidth(c, c == 2 ? 45 : 20);
            }

            writeTitle(breakdownSheet, 7, '${_selected.label} - Item Breakdown');
            writeHeader(breakdownSheet, [
              'Promo No.', 'Product Code', 'Item Name',
              'Orig Price', 'Promo Price', 'Qty Sold', 'Discount', 'Remaining',
            ], 4);

            int row = 5;
            int i = 0;

            for (final promo in rows) {
              for (final item in _toList(promo['items'])) {
                final isAlt = i.isOdd;
                final remaining = item['promo_qty_remaining'];
                final limit     = item['promo_qty_limit'];
                final promoPrice = item['promo_price'];

                setCell(breakdownSheet, 0, row,
                    excel.TextCellValue(promo['promo_no']?.toString() ?? '-'),
                    isAlt ? rowAltStyle : rowStyle);
                setCell(breakdownSheet, 1, row,
                    excel.TextCellValue(item['product_code']?.toString() ?? '-'),
                    isAlt ? rowAltStyle : rowStyle);
                setCell(breakdownSheet, 2, row,
                    excel.TextCellValue(_cleanItemName(item['item_name'])),
                    isAlt ? rowAltStyle : rowStyle);
                setCell(breakdownSheet, 3, row,
                    excel.DoubleCellValue(_toDouble(item['original_price'])),
                    isAlt ? rightAltStyle : rightStyle);
                setCell(breakdownSheet, 4, row,
                    promoPrice != null
                        ? excel.DoubleCellValue(_toDouble(promoPrice))
                        : excel.TextCellValue('—'),
                    isAlt ? rightAltStyle : rightStyle);
                setCell(breakdownSheet, 5, row,
                    excel.DoubleCellValue(_toDouble(item['qty_sold'])),
                    isAlt ? centerAltStyle : centerStyle);
                setCell(breakdownSheet, 6, row,
                    excel.DoubleCellValue(_toDouble(item['total_discount'])),
                    isAlt ? rightAltStyle : rightStyle);
                setCell(breakdownSheet, 7, row,
                    remaining != null
                        ? excel.TextCellValue(
                        '${(remaining as num).toStringAsFixed(0)} / ${(limit as num).toStringAsFixed(0)}')
                        : excel.TextCellValue('—'),
                    isAlt ? centerAltStyle : centerStyle);

                row++;
                i++;
              }
            }
            break;
          case ReportType.transfer:
            for (int c = 0; c < 6; c++) {
              breakdownSheet.setColumnWidth(c, c == 2 ? 45 : 20);
            }

            writeTitle(
              breakdownSheet,
              5,
              '${_selected.label} - Item Breakdown',
            );

            writeHeader(
              breakdownSheet,
              [
                'Transfer No.',
                'Product Code',
                'Item Name',
                'Qty',
                'Unit Price',
                'Subtotal',
              ],
              4,
            );

            int row = 5;
            int i = 0;

            for (final tr in rows) {
              for (final item in _toList(tr['items'])) {
                final isAlt = i.isOdd;

                setCell(
                  breakdownSheet,
                  0,
                  row,
                  excel.TextCellValue(tr['transfer_no']?.toString() ?? '-'),
                  isAlt ? rowAltStyle : rowStyle,
                );

                setCell(
                  breakdownSheet,
                  1,
                  row,
                  excel.TextCellValue(item['product_code']?.toString() ?? '-'),
                  isAlt ? rowAltStyle : rowStyle,
                );

                setCell(
                  breakdownSheet,
                  2,
                  row,
                  excel.TextCellValue(_cleanItemName(item['item_description'])),
                  isAlt ? rowAltStyle : rowStyle,
                );

                setCell(
                  breakdownSheet,
                  3,
                  row,
                  excel.DoubleCellValue(_toDouble(item['quantity'])),
                  isAlt ? centerAltStyle : centerStyle,
                );

                setCell(
                  breakdownSheet,
                  4,
                  row,
                  excel.DoubleCellValue(_toDouble(item['unit_price'])),
                  isAlt ? rightAltStyle : rightStyle,
                );

                setCell(
                  breakdownSheet,
                  5,
                  row,
                  excel.DoubleCellValue(_toDouble(item['subtotal'])),
                  isAlt ? rightAltStyle : rightStyle,
                );

                row++;
                i++;
              }
            }
            break;

          case ReportType.refund:
            for (int c = 0; c < 7; c++) {
              breakdownSheet.setColumnWidth(c, c == 2 ? 45 : 20);
            }

            writeTitle(
              breakdownSheet,
              6,
              '${_selected.label} - Item Breakdown',
            );

            writeHeader(
              breakdownSheet,
              [
                'Refund #',
                'Product Code',
                'Item Name',
                'Qty',
                'Unit Price',
                'Subtotal',
                'Status',
              ],
              4,
            );

            int row = 5;
            int i = 0;

            for (final refund in rows) {
              for (final item in _toList(refund['items'])) {
                final isAlt = i.isOdd;

                setCell(
                  breakdownSheet,
                  0,
                  row,
                  excel.TextCellValue('#${_toInt(refund['refund_id'])}'),
                  isAlt ? rowAltStyle : rowStyle,
                );

                setCell(
                  breakdownSheet,
                  1,
                  row,
                  excel.TextCellValue(item['product_code']?.toString() ?? '-'),
                  isAlt ? rowAltStyle : rowStyle,
                );

                setCell(
                  breakdownSheet,
                  2,
                  row,
                  excel.TextCellValue(_cleanItemName(item['item_name'])),
                  isAlt ? rowAltStyle : rowStyle,
                );

                setCell(
                  breakdownSheet,
                  3,
                  row,
                  excel.DoubleCellValue(_toDouble(item['quantity'])),
                  isAlt ? centerAltStyle : centerStyle,
                );

                setCell(
                  breakdownSheet,
                  4,
                  row,
                  excel.DoubleCellValue(_toDouble(item['unit_price'])),
                  isAlt ? rightAltStyle : rightStyle,
                );

                setCell(
                  breakdownSheet,
                  5,
                  row,
                  excel.DoubleCellValue(_toDouble(item['subtotal'])),
                  isAlt ? rightAltStyle : rightStyle,
                );

                setCell(
                  breakdownSheet,
                  6,
                  row,
                  excel.TextCellValue(item['status']?.toString() ?? '-'),
                  isAlt ? rowAltStyle : rowStyle,
                );

                row++;
                i++;
              }
            }
            break;

          case ReportType.disposal:
            for (int c = 0; c < 6; c++) {
              breakdownSheet.setColumnWidth(c, c == 2 ? 45 : 20);
            }

            writeTitle(
              breakdownSheet,
              5,
              '${_selected.label} - Item Breakdown',
            );

            writeHeader(
              breakdownSheet,
              [
                'Date',
                'Product Code',
                'Item Name',
                'Qty',
                'Unit Price',
                'Subtotal',
              ],
              4,
            );

            int row = 5;
            int i = 0;

            for (final disposal in rows) {
              for (final item in _toList(disposal['items'])) {
                final isAlt = i.isOdd;

                setCell(
                  breakdownSheet,
                  0,
                  row,
                  excel.TextCellValue(
                    _formatDateStr(disposal['disposal_date']?.toString()),
                  ),
                  isAlt ? rowAltStyle : rowStyle,
                );

                setCell(
                  breakdownSheet,
                  1,
                  row,
                  excel.TextCellValue(item['product_code']?.toString() ?? '-'),
                  isAlt ? rowAltStyle : rowStyle,
                );

                setCell(
                  breakdownSheet,
                  2,
                  row,
                  excel.TextCellValue(
                    _cleanItemName(
                      item['item_description'] ?? item['item_name'],
                    ),
                  ),
                  isAlt ? rowAltStyle : rowStyle,
                );

                setCell(
                  breakdownSheet,
                  3,
                  row,
                  excel.DoubleCellValue(_toDouble(item['quantity'])),
                  isAlt ? centerAltStyle : centerStyle,
                );

                setCell(
                  breakdownSheet,
                  4,
                  row,
                  excel.DoubleCellValue(_toDouble(item['unit_price'])),
                  isAlt ? rightAltStyle : rightStyle,
                );

                setCell(
                  breakdownSheet,
                  5,
                  row,
                  excel.DoubleCellValue(
                    _toDouble(item['subtotal'] ?? item['total_loss']),
                  ),
                  isAlt ? rightAltStyle : rightStyle,
                );

                row++;
                i++;
              }
            }
            break;

          case ReportType.badOrder:
            for (int c = 0; c < 7; c++) {
              breakdownSheet.setColumnWidth(c, c == 2 ? 45 : 20);
            }

            writeTitle(
              breakdownSheet,
              6,
              '${_selected.label} - Item Breakdown',
            );

            writeHeader(
              breakdownSheet,
              [
                'BO No.',
                'Product Code',
                'Item Name',
                'Qty',
                'Unit Price',
                'Subtotal',
                'Reason',
              ],
              4,
            );

            int row = 5;
            int i = 0;

            for (final bo in rows) {
              for (final item in _toList(bo['items'])) {
                final isAlt = i.isOdd;

                setCell(
                  breakdownSheet,
                  0,
                  row,
                  excel.TextCellValue(bo['bo_no']?.toString() ?? '-'),
                  isAlt ? rowAltStyle : rowStyle,
                );

                setCell(
                  breakdownSheet,
                  1,
                  row,
                  excel.TextCellValue(item['product_code']?.toString() ?? '-'),
                  isAlt ? rowAltStyle : rowStyle,
                );

                setCell(
                  breakdownSheet,
                  2,
                  row,
                  excel.TextCellValue(_cleanItemName(item['item_description'])),
                  isAlt ? rowAltStyle : rowStyle,
                );

                setCell(
                  breakdownSheet,
                  3,
                  row,
                  excel.DoubleCellValue(_toDouble(item['quantity'])),
                  isAlt ? centerAltStyle : centerStyle,
                );

                setCell(
                  breakdownSheet,
                  4,
                  row,
                  excel.DoubleCellValue(_toDouble(item['unit_price'])),
                  isAlt ? rightAltStyle : rightStyle,
                );

                setCell(
                  breakdownSheet,
                  5,
                  row,
                  excel.DoubleCellValue(_toDouble(item['subtotal'])),
                  isAlt ? rightAltStyle : rightStyle,
                );

                setCell(
                  breakdownSheet,
                  6,
                  row,
                  excel.TextCellValue(item['remarks']?.toString() ?? '-'),
                  isAlt ? rowAltStyle : rowStyle,
                );

                row++;
                i++;
              }
            }
            break;

          case ReportType.salesPerClerk:
          case ReportType.lowStock:
          case ReportType.promoSales:
            break;
        }
      }

      final userProfile =
          Platform.environment['USERPROFILE'] ?? 'C:/Users/Default';
      final reportsDir = Directory('$userProfile/Documents/PO Reports');

      if (!await reportsDir.exists()) {
        await reportsDir.create(recursive: true);
      }

      final fileName =
          '${_selected.apiKey}_${_fileFmt.format(DateTime.now())}.xlsx';
      final file = File('${reportsDir.path}/$fileName');

      final bytes = book.save();
      if (bytes == null) throw Exception('Failed to generate XLSX file.');

      await file.writeAsBytes(bytes);

      if (!mounted) return;
      _showExportSnack(file.path, 'XLSX');
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('XLSX failed: $e'),
          backgroundColor: themeNotifier.theme.red,
        ),
      );
    }
  }

  Future<void> _exportPdf({bool includeBreakdown = true}) async {
    setState(() => _exportingPdf = true);

    try {
      final path = await _buildPdf(includeBreakdown: includeBreakdown);
      _showExportSnack(path, 'PDF');
    } catch (e) {
      final t = themeNotifier.theme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF failed: $e'),
          backgroundColor: t.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<String> _buildPdf({bool includeBreakdown = true}) async {
    final pdf = pw.Document();
    final now = DateTime.now();
    final f = _filter;

    const white = PdfColors.black;
    const dark = PdfColors.black;
    const gray = PdfColor.fromInt(0xFF555555);
    const alt = PdfColor.fromInt(0xFFF7F7F7);

    String dateLabel = 'All Dates';

    if (f.dateFrom != null && f.dateTo != null) {
      dateLabel = '${_dateFmt.format(f.dateFrom!)} - ${_dateFmt.format(f.dateTo!)}';
    } else if (f.dateFrom != null) {
      dateLabel = 'From ${_dateFmt.format(f.dateFrom!)}';
    } else if (f.dateTo != null) {
      dateLabel = 'Up to ${_dateFmt.format(f.dateTo!)}';
    }

    pw.Widget hCell(String text, {bool right = false, bool center = false}) {
      return pw.Text(
        text,
        textAlign: right
            ? pw.TextAlign.right
            : center
            ? pw.TextAlign.center
            : pw.TextAlign.left,
        style: pw.TextStyle(
          color: PdfColors.white,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
        ),
      );
    }

    pw.Widget banner() {
      return pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(
              color: PdfColors.black,
              width: 1,
            ),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  "THREE E'S TOYS",
                  style: pw.TextStyle(
                    color: PdfColors.black,
                    fontSize: 16,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  _selected.label.toUpperCase(),
                  style: pw.TextStyle(
                    color: PdfColors.black,
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'Period: $dateLabel',
                  style: const pw.TextStyle(
                    color: PdfColors.black,
                    fontSize: 9,
                  ),
                ),
                pw.Text(
                  'Generated: ${DateFormat('MMMM d, yyyy hh:mm a').format(now)}',
                  style: const pw.TextStyle(
                    color: PdfColors.black,
                    fontSize: 9,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    pw.Widget footer(pw.Context ctx) {
      return pw.Column(
        children: [
          pw.Divider(color: gray, thickness: 0.5),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                "Three E's Toys - ${_selected.label}",
                style: const pw.TextStyle(color: gray, fontSize: 8),
              ),
              pw.Text(
                'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
                style: const pw.TextStyle(color: gray, fontSize: 8),
              ),
            ],
          ),
        ],
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
        header: (_) => pw.Column(children: [banner(), pw.SizedBox(height: 12)]),
        footer: footer,
        build: (_) {
          switch (_selected) {
            case ReportType.dailySales:
              return _buildDailySalesPdf(hCell, white, dark, alt, includeBreakdown);
            case ReportType.salesPerClerk:
              return _buildClerkSalesPdf(hCell, white, dark, alt);
            case ReportType.promoSales:
              return _buildPromoSalesPdf(hCell, white, dark, alt, includeBreakdown);
            case ReportType.transfer:
              return _buildTransferPdf(hCell, white, dark, alt, includeBreakdown);
            case ReportType.refund:
              return _buildRefundPdf(hCell, white, dark, alt, includeBreakdown);
            case ReportType.disposal:
              return _buildDisposalPdf(hCell, white, dark, alt, includeBreakdown);
            case ReportType.lowStock:
              return _buildLowStockPdf(hCell, white, dark, alt);
            case ReportType.badOrder:
              return _buildBadOrderPdf(hCell, white, dark, alt, includeBreakdown);
          }
        },
      ),
    );

    final userProfile = Platform.environment['USERPROFILE'] ?? 'C:/Users/Default';
    final reportsDir = Directory('$userProfile/Documents/PO Reports');

    if (!await reportsDir.exists()) {
      await reportsDir.create(recursive: true);
    }

    final fileName = '${_selected.apiKey}_${_fileFmt.format(DateTime.now())}.pdf';
    final file = File('${reportsDir.path}/$fileName');

    await file.writeAsBytes(await pdf.save());
    return file.path;
  }

  List<pw.Widget> _buildPromoSalesPdf(
      pw.Widget Function(String, {bool right, bool center}) hCell,
      PdfColor white,
      PdfColor dark,
      PdfColor alt,
      bool includeBreakdown,
      ) {
    final rows = _toList(_data['rows']);
    final summary = Map<String, dynamic>.from(_data['summary'] as Map? ?? {});

    final promoCount    = _toInt(summary['promo_count']);
    final totalQty      = _toDouble(summary['total_qty']);
    final totalDiscount = _toDouble(summary['total_discount']);
    final totalRevenue  = _toDouble(summary['total_revenue']);

    final widgets = <pw.Widget>[
      _pdfSummaryRow([
        ['Promos Used',    '$promoCount'],
        ['Total Qty',      totalQty.toStringAsFixed(0)],
        ['Total Discount', 'PHP ${_peso.format(totalDiscount)}'],
        ['Total Revenue',  'PHP ${_peso.format(totalRevenue)}'],
      ]),
      pw.SizedBox(height: 14),
      pw.Text('Promo Sales Summary',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      _pdfHeaderRow(hCell,
        ['Promo No.', 'Promo Name', 'Supplier', 'Type', 'Date Range',
          'Txns', 'Qty', 'Discount', 'Revenue'],
        [2, 3, 2, 2, 3, 1, 1, 2, 2],
      ),
    ];

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      final dateRange =
          '${_formatDateStr(r['date_from']?.toString())} – ${_formatDateStr(r['date_to']?.toString())}';

      widgets.add(_pdfDataRow([
        r['promo_no']?.toString() ?? '-',
        r['promo_name']?.toString() ?? '-',
        r['supplier_name']?.toString() ?? '-',
        r['calculation_name']?.toString() ?? '-',
        dateRange,
        '${_toInt(r['transaction_count'])}',
        _toDouble(r['total_qty']).toStringAsFixed(0),
        'PHP ${_peso.format(_toDouble(r['total_discount']))}',
        'PHP ${_peso.format(_toDouble(r['total_revenue']))}',
      ], [2, 3, 2, 2, 3, 1, 1, 2, 2], i, dark, alt));
    }

    if (!includeBreakdown) return widgets;

    widgets.addAll([
      pw.SizedBox(height: 16),
      pw.Text('Promo Item Breakdown',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
      pw.SizedBox(height: 6),
      _pdfHeaderRow(hCell,
        ['Promo No.', 'Code', 'Item Name', 'Orig Price', 'Promo Price',
          'Qty Sold', 'Discount', 'Remaining'],
        [2, 2, 4, 2, 2, 1, 2, 2],
      ),
    ]);

    int itemIndex = 0;
    for (final promo in rows) {
      for (final item in _toList(promo['items'])) {
        final remaining = item['promo_qty_remaining'];
        final limit     = item['promo_qty_limit'];
        final promoPrice = item['promo_price'];

        widgets.add(_pdfDataRow([
          promo['promo_no']?.toString() ?? '-',
          item['product_code']?.toString() ?? '-',
          _cleanItemName(item['item_name']),
          'PHP ${_peso.format(_toDouble(item['original_price']))}',
          promoPrice != null
              ? 'PHP ${_peso.format(_toDouble(promoPrice))}'
              : '—',
          _toDouble(item['qty_sold']).toStringAsFixed(0),
          'PHP ${_peso.format(_toDouble(item['total_discount']))}',
          remaining != null
              ? '${(remaining as num).toStringAsFixed(0)} / ${(limit as num).toStringAsFixed(0)}'
              : '—',
        ], [2, 2, 4, 2, 2, 1, 2, 2], itemIndex, dark, alt));

        itemIndex++;
      }
    }

    return widgets;
  }
  List<pw.Widget> _buildBadOrderPdf(
      pw.Widget Function(String, {bool right, bool center}) hCell,
      PdfColor white,
      PdfColor dark,
      PdfColor alt,
      bool includeBreakdown,
      ) {
    final rows = _toList(_data['rows']);
    final summary = Map<String, dynamic>.from(_data['summary'] as Map? ?? {});

    final count = _toInt(summary['count'] ?? rows.length);
    final totalQty = _toDouble(summary['total_qty']);
    final totalAmount = _toDouble(summary['total_amount']);

    final widgets = <pw.Widget>[
      _pdfSummaryRow([
        ['Bad Orders', '$count'],
        ['Total Qty', totalQty.toStringAsFixed(0)],
        ['Total Amount', 'PHP ${_peso.format(totalAmount)}'],
      ]),
      pw.SizedBox(height: 14),
      pw.Text(
        'Bad Order Summary',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      _pdfHeaderRow(
        hCell,
        ['BO No.', 'Date', 'Store', 'Supplier', 'Created By', 'Amount'],
        [2, 2, 2, 2, 2, 2],
      ),
    ];

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];

      widgets.add(
        _pdfDataRow(
          [
            r['bo_no']?.toString() ?? '-',
            _formatDateStr(r['created_at']?.toString()),
            r['store_name']?.toString() ?? '-',
            r['supplier_name']?.toString().isNotEmpty == true ? r['supplier_name'].toString() : '-',
            r['created_by']?.toString() ?? '-',
            'PHP ${_peso.format(_toDouble(r['total_amount']))}',
          ],
          [2, 2, 2, 2, 2, 2],
          i,
          dark,
          alt,
        ),
      );
    }

    if (!includeBreakdown) return widgets;

    widgets.addAll([
      pw.SizedBox(height: 16),
      pw.Text(
        'Bad Order Item Breakdown',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      _pdfHeaderRow(
        hCell,
        ['BO No.', 'Code', 'Item Name', 'Qty', 'Unit Price', 'Subtotal', 'Reason'],
        [2, 2, 4, 1, 2, 2, 2],
      ),
    ]);

    int itemIndex = 0;

    for (final bo in rows) {
      final items = _toList(bo['items']);

      for (final item in items) {
        widgets.add(
          _pdfDataRow(
            [
              bo['bo_no']?.toString() ?? '-',
              item['product_code']?.toString() ?? '-',
              _cleanItemName(item['item_description']),
              _toDouble(item['quantity']).toStringAsFixed(0),
              'PHP ${_peso.format(_toDouble(item['unit_price']))}',
              'PHP ${_peso.format(_toDouble(item['subtotal']))}',
              item['remarks']?.toString() ?? '-',
            ],
            [2, 2, 4, 1, 2, 2, 2],
            itemIndex,
            dark,
            alt,
          ),
        );

        itemIndex++;
      }
    }

    return widgets;
  }

  List<pw.Widget> _buildDailySalesPdf(
      pw.Widget Function(String, {bool right, bool center}) hCell,
      PdfColor white,
      PdfColor dark,
      PdfColor alt,
      bool includeBreakdown,
      ) {
    final rows = _toList(_data['rows']);
    final top = _toList(_data['top_products']);
    final allItems = _toList(_data['all_items']);

    final summary = Map<String, dynamic>.from(_data['summary'] as Map? ?? {});
    final gross = _toDouble(summary['grand_gross_sales']);
    final refunds = _toDouble(summary['grand_refunds']);
    final net = _toDouble(summary['grand_net_sales']);
    final transactions = _toInt(summary['grand_transactions']);
    final customers = _toInt(summary['grand_customers']);

    final widgets = <pw.Widget>[
      _pdfSummaryRow([
        ['Transactions', '$transactions'],
        ['Customers', '$customers'],
        ['Gross Sales', 'PHP ${_peso.format(gross)}'],
        ['Refunds', 'PHP ${_peso.format(refunds)}'],
        ['Net Sales', 'PHP ${_peso.format(net)}'],
      ]),
      pw.SizedBox(height: 14),

      pw.Text(
        'Daily Sales Summary',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      _pdfHeaderRow(
        hCell,
        ['Date', 'Transactions', 'Customers', 'Gross', 'Refunds', 'Net Sales'],
        [2, 1, 1, 2, 2, 2],
      ),
    ];

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      widgets.add(
        _pdfDataRow(
          [
            r['sale_date']?.toString() ?? '-',
            '${_toInt(r['transaction_count'])}',
            '${_toInt(r['unique_customers'])}',
            'PHP ${_peso.format(_toDouble(r['gross_sales']))}',
            'PHP ${_peso.format(_toDouble(r['refunds']))}',
            'PHP ${_peso.format(_toDouble(r['net_sales']))}',
          ],
          [2, 1, 1, 2, 2, 2],
          i,
          dark,
          alt,
        ),
      );
    }

    if (!includeBreakdown) return widgets;

    if (top.isNotEmpty) {
      widgets.addAll([
        pw.SizedBox(height: 16),
        pw.Text(
          'Top 10 Products',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        _pdfHeaderRow(
          hCell,
          ['Code', 'Item Name', 'Qty Sold', 'Revenue'],
          [2, 4, 1, 2],
        ),
      ]);

      for (int i = 0; i < top.length; i++) {
        final r = top[i];
        widgets.add(
          _pdfDataRow(
            [
              r['product_code']?.toString() ?? '-',
              _cleanItemName(r['item_name']),
              _toDouble(r['total_qty']).toStringAsFixed(0),
              'PHP ${_peso.format(_toDouble(r['total_revenue']))}',
            ],
            [2, 4, 1, 2],
            i,
            dark,
            alt,
          ),
        );
      }
    }

    if (allItems.isNotEmpty) {
      widgets.addAll([
        pw.SizedBox(height: 16),
        pw.Text(
          'Full Item Sales Breakdown',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        _pdfHeaderRow(
          hCell,
          ['Code', 'Item Name', 'Qty Sold', 'Revenue'],
          [2, 4, 1, 2],
        ),
      ]);

      for (int i = 0; i < allItems.length; i++) {
        final r = allItems[i];
        widgets.add(
          _pdfDataRow(
            [
              r['product_code']?.toString() ?? '-',
              _cleanItemName(r['item_name']),
              _toDouble(r['total_qty']).toStringAsFixed(0),
              'PHP ${_peso.format(_toDouble(r['total_revenue']))}',
            ],
            [2, 4, 1, 2],
            i,
            dark,
            alt,
          ),
        );
      }
    }

    return widgets;
  }

  List<pw.Widget> _buildClerkSalesPdf(
      pw.Widget Function(String, {bool right, bool center}) hCell,
      PdfColor white,
      PdfColor dark,
      PdfColor alt,
      ) {
    final rows = _toList(_data['rows']);
    final daily = _toList(_data['daily']);

    final gross = _toDouble(_data['grand_gross_total']);
    final refunds = _toDouble(_data['grand_refunds']);
    final net = _toDouble(_data['grand_net_total']);

    final widgets = <pw.Widget>[
      _pdfSummaryRow([
        ['Gross Sales', 'PHP ${_peso.format(gross)}'],
        ['Refunds', 'PHP ${_peso.format(refunds)}'],
        ['Net Sales', 'PHP ${_peso.format(net)}'],
      ]),
      pw.SizedBox(height: 14),

      pw.Text(
        'Clerk Sales Summary',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      _pdfHeaderRow(
        hCell,
        ['Clerk Name', 'Transactions', 'Gross', 'Refunds', 'Net Sales', 'Avg Sale'],
        [3, 1, 2, 2, 2, 2],
      ),
    ];

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];

      widgets.add(
        _pdfDataRow(
          [
            r['full_name']?.toString() ?? '-',
            '${_toInt(r['transaction_count'])}',
            'PHP ${_peso.format(_toDouble(r['gross_sales']))}',
            'PHP ${_peso.format(_toDouble(r['refunds']))}',
            'PHP ${_peso.format(_toDouble(r['net_sales']))}',
            'PHP ${_peso.format(_toDouble(r['avg_sale']))}',
          ],
          [3, 1, 2, 2, 2, 2],
          i,
          dark,
          alt,
        ),
      );
    }

    if (daily.isNotEmpty) {
      widgets.addAll([
        pw.SizedBox(height: 16),
        pw.Text(
          'Daily Breakdown Per Clerk',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        _pdfHeaderRow(
          hCell,
          ['Date', 'Clerk Name', 'Transactions', 'Gross', 'Refunds', 'Net Sales'],
          [2, 3, 1, 2, 2, 2],
        ),
      ]);

      for (int i = 0; i < daily.length; i++) {
        final r = daily[i];

        widgets.add(
          _pdfDataRow(
            [
              _formatDateStr(r['sale_date']?.toString()),
              r['full_name']?.toString() ?? '-',
              '${_toInt(r['transaction_count'])}',
              'PHP ${_peso.format(_toDouble(r['gross_sales']))}',
              'PHP ${_peso.format(_toDouble(r['refunds']))}',
              'PHP ${_peso.format(_toDouble(r['net_sales']))}',
            ],
            [2, 3, 1, 2, 2, 2],
            i,
            dark,
            alt,
          ),
        );
      }
    }

    return widgets;
  }

  List<pw.Widget> _buildTransferPdf(
      pw.Widget Function(String, {bool right, bool center}) hCell,
      PdfColor white,
      PdfColor dark,
      PdfColor alt,
      bool includeBreakdown,
      ) {
    final rows = _toList(_data['rows']);
    final summary = Map<String, dynamic>.from(_data['summary'] as Map? ?? {});
    final grand = _toDouble(summary['grand_total'] ?? _data['grand_total']);
    final transferCount = _toInt(summary['transfer_count'] ?? rows.length);
    final totalItems = _toInt(summary['total_items']);

    final widgets = <pw.Widget>[
      _pdfSummaryRow([
        ['Transfers', '$transferCount'],
        ['Total Items', '$totalItems'],
        ['Total Value', 'PHP ${_peso.format(grand)}'],
      ]),
      pw.SizedBox(height: 14),

      pw.Text(
        'Transfer Summary',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      _pdfHeaderRow(
        hCell,
        ['Transfer No.', 'Date', 'Warehouse', 'Store', 'By', 'Value'],
        [2, 2, 2, 2, 2, 2],
      ),
    ];

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];

      widgets.add(
        _pdfDataRow(
          [
            r['transfer_no']?.toString() ?? '-',
            _formatDateStr(r['transfer_date']?.toString()),
            r['warehouse_name']?.toString() ?? '-',
            r['store_name']?.toString() ?? '-',
            r['transferred_by']?.toString() ?? '-',
            'PHP ${_peso.format(_toDouble(r['total_value']))}',
          ],
          [2, 2, 2, 2, 2, 2],
          i,
          dark,
          alt,
        ),
      );
    }

    if (!includeBreakdown) return widgets;

    widgets.addAll([
      pw.SizedBox(height: 16),
      pw.Text(
        'Transfer Item Breakdown',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      _pdfHeaderRow(
        hCell,
        ['Transfer No.', 'Code', 'Item Name', 'Qty', 'Unit Price', 'Subtotal'],
        [2, 2, 4, 1, 2, 2],
      ),
    ]);

    int itemIndex = 0;

    for (final tr in rows) {
      final items = _toList(tr['items']);

      for (final it in items) {
        widgets.add(
          _pdfDataRow(
            [
              tr['transfer_no']?.toString() ?? '-',
              it['product_code']?.toString() ?? '-',
              _cleanItemName(it['item_description']),
              _toDouble(it['quantity']).toStringAsFixed(0),
              'PHP ${_peso.format(_toDouble(it['unit_price']))}',
              'PHP ${_peso.format(_toDouble(it['subtotal']))}',
            ],
            [2, 2, 4, 1, 2, 2],
            itemIndex,
            dark,
            alt,
          ),
        );

        itemIndex++;
      }
    }

    return widgets;
  }

  List<pw.Widget> _buildRefundPdf(
      pw.Widget Function(String, {bool right, bool center}) hCell,
      PdfColor white,
      PdfColor dark,
      PdfColor alt,
      bool includeBreakdown,
      ) {
    final rows = _toList(_data['rows']);
    final summary = Map<String, dynamic>.from(_data['summary'] as Map? ?? {});

    final total = _toDouble(summary['total_refunded']);
    final count = _toInt(summary['count'] ?? rows.length);
    final totalItems = _toDouble(summary['total_items']);

    final widgets = <pw.Widget>[
      _pdfSummaryRow([
        ['Refunds', '$count'],
        ['Total Items', totalItems.toStringAsFixed(0)],
        ['Total Refunded', 'PHP ${_peso.format(total)}'],
      ]),
      pw.SizedBox(height: 14),

      pw.Text(
        'Refund Summary',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      _pdfHeaderRow(
        hCell,
        ['#', 'Txn No.', 'Type', 'Store', 'Original Cashier', 'Processed By', 'Amount'],
        [1, 2, 1, 2, 2, 2, 2],
      ),
    ];

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];

      widgets.add(
        _pdfDataRow(
          [
            '#${_toInt(r['refund_id'])}',
            r['transaction_no']?.toString() ?? '-',
            r['refund_type']?.toString() ?? '-',
            r['store_name']?.toString() ?? '-',
            r['original_cashier']?.toString() ?? '-',
            r['processed_by']?.toString() ?? '-',
            'PHP ${_peso.format(_toDouble(r['total_amount']))}',
          ],
          [1, 2, 1, 2, 2, 2, 2],
          i,
          dark,
          alt,
        ),
      );
    }

    if (!includeBreakdown) return widgets;

    widgets.addAll([
      pw.SizedBox(height: 16),
      pw.Text(
        'Refund Item Breakdown',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      _pdfHeaderRow(
        hCell,
        ['Refund #', 'Code', 'Item Name', 'Qty', 'Unit Price', 'Subtotal', 'Status'],
        [1, 2, 4, 1, 2, 2, 2],
      ),
    ]);

    int itemIndex = 0;

    for (final refund in rows) {
      final items = _toList(refund['items']);

      for (final item in items) {
        widgets.add(
          _pdfDataRow(
            [
              '#${_toInt(refund['refund_id'])}',
              item['product_code']?.toString() ?? '-',
              _cleanItemName(item['item_name']),
              _toDouble(item['quantity']).toStringAsFixed(0),
              'PHP ${_peso.format(_toDouble(item['unit_price']))}',
              'PHP ${_peso.format(_toDouble(item['subtotal']))}',
              item['status']?.toString() ?? '-',
            ],
            [1, 2, 4, 1, 2, 2, 2],
            itemIndex,
            dark,
            alt,
          ),
        );

        itemIndex++;
      }
    }

    return widgets;
  }

  List<pw.Widget> _buildDisposalPdf(
      pw.Widget Function(String, {bool right, bool center}) hCell,
      PdfColor white,
      PdfColor dark,
      PdfColor alt,
      bool includeBreakdown,
      ) {
    final rows = _toList(_data['rows']);
    final summary = Map<String, dynamic>.from(_data['summary'] as Map? ?? {});

    final totalLoss = _toDouble(summary['total_loss']);
    final totalItems = _toDouble(summary['total_items']);
    final count = _toInt(summary['count'] ?? rows.length);

    final widgets = <pw.Widget>[
      _pdfSummaryRow([
        ['Disposals', '$count'],
        ['Total Items', totalItems.toStringAsFixed(0)],
        ['Total Loss', 'PHP ${_peso.format(totalLoss)}'],
      ]),
      pw.SizedBox(height: 14),

      pw.Text(
        'Disposal Summary',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      _pdfHeaderRow(
        hCell,
        ['Date', 'Warehouse', 'Reason', 'Disposed By', 'Items', 'Total Loss'],
        [2, 2, 3, 2, 1, 2],
      ),
    ];

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];

      widgets.add(
        _pdfDataRow(
          [
            _formatDateStr(r['disposal_date']?.toString()),
            r['store_name']?.toString() ?? '-',
            r['reason']?.toString() ?? '-',
            r['disposed_by']?.toString() ?? '-',
            '${_toInt(r['item_count'])}',
            'PHP ${_peso.format(_toDouble(r['total_loss']))}',
          ],
          [2, 2, 3, 2, 1, 2],
          i,
          dark,
          alt,
        ),
      );
    }

    if (!includeBreakdown) return widgets;

    widgets.addAll([
      pw.SizedBox(height: 16),
      pw.Text(
        'Disposal Item Breakdown',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      _pdfHeaderRow(
        hCell,
        ['Date', 'Code', 'Item Name', 'Qty', 'Unit Price', 'Subtotal'],
        [2, 2, 4, 1, 2, 2],
      ),
    ]);

    int itemIndex = 0;

    for (final disposal in rows) {
      final items = _toList(disposal['items']);

      for (final item in items) {
        widgets.add(
          _pdfDataRow(
            [
              _formatDateStr(disposal['disposal_date']?.toString()),
              item['product_code']?.toString() ?? '-',
              _cleanItemName(item['item_description'] ?? item['item_name']),
              _toDouble(item['quantity']).toStringAsFixed(0),
              'PHP ${_peso.format(_toDouble(item['unit_price']))}',
              'PHP ${_peso.format(_toDouble(item['subtotal']))}',
            ],
            [2, 2, 4, 1, 2, 2],
            itemIndex,
            dark,
            alt,
          ),
        );

        itemIndex++;
      }
    }

    return widgets;
  }

  List<pw.Widget> _buildLowStockPdf(
      pw.Widget Function(String, {bool right, bool center}) hCell,
      PdfColor white,
      PdfColor dark,
      PdfColor alt,
      ) {
    final rows = _toList(_data['all']);
    final counts = Map<String, dynamic>.from(_data['counts'] as Map? ?? {});
    final threshold = _toInt(_data['threshold']);

    final widgets = <pw.Widget>[
      _pdfSummaryRow([
        ['Threshold', '$threshold units'],
        ['Warehouse Alerts', '${_toInt(counts['warehouse'])}'],
        ['Store Alerts', '${_toInt(counts['store'])}'],
        ['Total Alerts', '${_toInt(counts['total'])}'],
      ]),
      pw.SizedBox(height: 14),

      pw.Text(
        'Low Stock Items',
        style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),

      _pdfHeaderRow(
        hCell,
        ['Source', 'Location', 'Code', 'Description', 'Qty', 'Unit Price'],
        [1, 2, 2, 4, 1, 2],
      ),
    ];

    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];

      widgets.add(
        _pdfDataRow(
          [
            r['source']?.toString() ?? '-',
            r['location_name']?.toString() ?? '-',
            r['product_code']?.toString() ?? '-',
            _cleanItemName(r['item_description']),
            '${_toInt(r['quantity'])}',
            'PHP ${_peso.format(_toDouble(r['unit_price']))}',
          ],
          [1, 2, 2, 4, 1, 2],
          i,
          dark,
          alt,
        ),
      );
    }

    return widgets;
  }

  pw.Widget _pdfSummaryRow(List<List<String>> items) {
    return pw.Row(
      children: items.map((e) {
        return pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 8),
            padding: const pw.EdgeInsets.all(10),
            decoration: const pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF4F4F4),
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(6)),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  e[0],
                  style: const pw.TextStyle(
                    color: PdfColor.fromInt(0xFF777777),
                    fontSize: 8,
                  ),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  e[1],
                  style: pw.TextStyle(
                    color: PdfColor.fromInt(0xFFEFEFEF),
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  pw.Widget _pdfHeaderRow(
      pw.Widget Function(String, {bool right, bool center}) hCell,
      List<String> headers,
      List<int> flexes,
      ) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColors.black,
        border: pw.Border.all(color: PdfColors.black, width: 0.7),
      ),
      child: pw.Row(
        children: List.generate(
          headers.length,
              (i) => pw.Expanded(
            flex: flexes[i],
            child: pw.Container(
              padding: const pw.EdgeInsets.all(8),
              child: hCell(headers[i]),
            ),
          ),
        ),
      ),
    );
  }

  pw.Widget _pdfDataRow(
      List<String> cells,
      List<int> flexes,
      int index,
      PdfColor dark,
      PdfColor alt,
      ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: pw.BoxDecoration(
        color: index.isOdd ? alt : PdfColors.white,
        border: const pw.Border(
          bottom: pw.BorderSide(color: PdfColor.fromInt(0xFFDDDDDD), width: 0.5),
        ),
      ),
      child: pw.Row(
        children: List.generate(
          cells.length,
              (i) => pw.Expanded(
            flex: flexes[i],
            child: pw.Text(
              cells[i],
              style: pw.TextStyle(fontSize: 8, color: dark),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: themeNotifier,
      builder: (_, __, ___) {
        final t = themeNotifier.theme;
        final screenWidth = MediaQuery.of(context).size.width;
        final isMobile = screenWidth < 600;

        if (isMobile) {
          return Scaffold(
            backgroundColor: t.bg,
            body: Column(
              children: [
                _buildTopBar(t),
                _buildFilterBar(t),
                Expanded(child: _buildContent(t)),
              ],
            ),
            bottomNavigationBar: _buildMobileReportPicker(t),
          );
        }

        return Scaffold(
          backgroundColor: t.bg,
          body: Row(
            children: [
              _buildSidebar(t),
              Expanded(
                child: Column(
                  children: [
                    _buildTopBar(t),
                    _buildFilterBar(t),
                    Expanded(child: _buildContent(t)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebar(AppTheme t) {
    return Container(
      width: _isWindows ? 220 : 64,
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(right: BorderSide(color: t.border)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          if (_isWindows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'Reports',
                style: TextStyle(
                  color: t.textLo,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ..._allowedReports.map(
                (type) => _SidebarItem(
              type: type,
              selected: _selected == type,
              compact: !_isWindows,
              onTap: () => _selectReport(type),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileReportPicker(AppTheme t) {
    final allowed = _allowedReports;
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: allowed.map((type) {
              final selected = _selected == type;
              final c = type.color;
              return GestureDetector(
                onTap: () => _selectReport(type),
                child: Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? c.withOpacity(0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? c.withOpacity(0.5)
                          : t.border,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(type.icon,
                          color: selected ? c : t.textLo, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        type.label,
                        style: TextStyle(
                          color: selected ? c : t.textLo,
                          fontSize: 12,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(AppTheme t) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 24, 16, isMobile ? 16 : 24, 12),
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
                      _selected.label,
                      style: TextStyle(
                        color: t.textHi,
                        fontSize: isMobile ? 18 : 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Three E's Toys — Generated ${DateFormat('MMMM d, yyyy').format(DateTime.now())}",
                      style: TextStyle(color: t.textLo, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (canExportReports)
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                  onPressed: _showReportExportOptions,
                  icon: const Icon(Icons.file_download_rounded, size: 16),
                  label: const Text('Export',
                      style: TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ],
      ),
    );
  }
  Widget _buildFilterBar(AppTheme t) {
    final f = _filter;
    final showDates = true;
    final showStore = [
      ReportType.dailySales,
      ReportType.salesPerClerk,
      ReportType.promoSales,   // ← ADD

      ReportType.refund,
      ReportType.disposal,
      ReportType.badOrder,
    ].contains(_selected);

    final showWarehouse = [
      ReportType.transfer,
      ReportType.disposal,
    ].contains(_selected);

    final showThreshold = _selected == ReportType.lowStock;

    return Container(
      padding: EdgeInsets.fromLTRB(
          MediaQuery.of(context).size.width < 600 ? 12 : 24, 0,
          MediaQuery.of(context).size.width < 600 ? 12 : 24, 14),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          if (showDates) ...[
            _DateChip(
              t: t,
              label: f.dateFrom != null
                  ? 'From: ${_dateFmt.format(f.dateFrom!)}'
                  : 'Date From',
              active: f.dateFrom != null,
              onTap: () => _pickDate(isFrom: true, t: t),
              onClear: f.dateFrom != null
                  ? () {
                setState(() {
                  f.dateFrom = null;
                  f.page = 1;
                });
                _load();
              }
                  : null,
            ),
            _DateChip(
              t: t,
              label: f.dateTo != null
                  ? 'To: ${_dateFmt.format(f.dateTo!)}'
                  : 'Date To',
              active: f.dateTo != null,
              onTap: () => _pickDate(isFrom: false, t: t),
              onClear: f.dateTo != null
                  ? () {
                setState(() {
                  f.dateTo = null;
                  f.page = 1;
                });
                _load();
              }
                  : null,
            ),
          ],
          if (showStore && _stores.isNotEmpty)
            _FilterDropdown<int>(
              t: t,
              value: f.storeId ?? 0,
              items: [0, ..._stores.map((s) => _toInt(s['store_id']))],
              labelOf: (id) {
                if (id == 0) return 'All Stores';
                final store = _stores.firstWhere(
                      (s) => _toInt(s['store_id']) == id,
                  orElse: () => {},
                );
                final name = store['store_name'] as String? ?? 'Store $id';
                final address = store['address'] as String? ?? '';
                return address.isNotEmpty ? '$name – $address' : name;
              },
              onChanged: (v) {
                setState(() {
                  f.storeId = v == 0 ? null : v;
                  f.page = 1;
                });
                _load();
              },
            ),
          if (showWarehouse && _warehouses.isNotEmpty)
            _FilterDropdown<int>(
              t: t,
              value: f.warehouseId ?? 0,
              items: [
                0,
                ..._warehouses.map((w) => _toInt(w['warehouse_id'])),
              ],
              labelOf: (id) {
                if (id == 0) return 'All Warehouses';
                final wh = _warehouses.firstWhere(
                      (w) => _toInt(w['warehouse_id']) == id,
                  orElse: () => {},
                );
                return wh['warehouse_name'] as String? ?? 'Warehouse $id';
              },
              onChanged: (v) {
                setState(() {
                  f.warehouseId = v == 0 ? null : v;
                  f.page = 1;
                });
                _load();
              },
            ),
          if (showThreshold)
            _ThresholdChip(
              t: t,
              value: f.threshold,
              onChanged: (v) {
                setState(() {
                  f.threshold = v;
                  f.page = 1;
                });
                _load();
              },
            ),
          GestureDetector(
            onTap: () {
              setState(() {
                f.dateFrom = null;
                f.dateTo = null;
                f.storeId = null;
                f.warehouseId = null;
                f.threshold = 10;
                f.page = 1;
              });
              _load();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: t.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.red.withOpacity(0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.clear_all_rounded, color: t.red, size: 16),
                  const SizedBox(width: 6),
                  Text(
                    'Reset',
                    style: TextStyle(color: t.red, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AppTheme t) {
    if (_loading) {
      return Center(child: CircularProgressIndicator(color: t.blue));
    }

    if (_error != null && _data.isEmpty) {
      return _ErrorView(message: _error!, onRetry: _load);
    }

    return RefreshIndicator(
      color: t.blue,
      backgroundColor: t.surface,
      onRefresh: _load,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildReportBody(),
            const SizedBox(height: 12),
            _ReportPagination(
              page: _filter.page,
              limit: _filter.limit,
              total: _toInt(_data['total']),
              limitOptions: _limitOptions,
              onPageChanged: (p) {
                setState(() => _filter.page = p);
                _load();
              },
              onLimitChanged: (l) {
                setState(() {
                  _filter.limit = l;
                  _filter.page = 1;
                });
                _load();
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildReportBody() {
    switch (_selected) {
      case ReportType.dailySales:
        return _DailySalesView(data: _data);
      case ReportType.salesPerClerk:
        return _SalesPerClerkView(data: _data);
      case ReportType.promoSales:
        return _PromoSalesView(data: _data);
      case ReportType.transfer:
        return _TransferView(data: _data);
      case ReportType.refund:
        return _RefundView(data: _data);
      case ReportType.disposal:
        return _DisposalView(data: _data);
      case ReportType.lowStock:
        return _LowStockView(data: _data, threshold: _filter.threshold);
      case ReportType.badOrder:
        return _BadOrderView(data: _data);
    }
  }
}

class _DailySalesView extends StatelessWidget {
  final Map<String, dynamic> data;

  const _DailySalesView({required this.data});

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;
    final rows = _toList(data['rows']);
    final top = _toList(data['top_products']);
    final summary = Map<String, dynamic>.from(data['summary'] as Map? ?? {});

    final grossTotal = _toDouble(summary['grand_gross_sales']);
    final refundTotal = _toDouble(summary['grand_refunds']);
    final netTotal = _toDouble(summary['grand_net_sales']);
    final grandT = _toInt(summary['grand_transactions']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              label: 'Total Days',
              value: '${rows.length}',
              color: t.blue,
              icon: Icons.calendar_today_rounded,
            ),
            _SummaryCard(
              label: 'Transactions',
              value: '$grandT',
              color: t.green,
              icon: Icons.receipt_long_rounded,
            ),
            _SummaryCard(
              label: 'Gross Sales',
              value: '₱${_peso.format(grossTotal)}',
              color: t.amber,
              icon: Icons.payments_rounded,
            ),
            _SummaryCard(
              label: 'Refunds',
              value: '₱${_peso.format(refundTotal)}',
              color: t.red,
              icon: Icons.money_off_rounded,
            ),
            _SummaryCard(
              label: 'Net Sales',
              value: '₱${_peso.format(netTotal)}',
              color: t.green,
              icon: Icons.trending_up_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _TableContainer(
          t: t,
          headers: const [
            'Date',
            'Transactions',
            'Customers',
            'Gross',
            'Refunds',
            'Net Sales',
          ],
          flexes: const [2, 1, 1, 2, 2, 2],
          aligns: const [
            TextAlign.left,
            TextAlign.center,
            TextAlign.center,
            TextAlign.right,
            TextAlign.right,
            TextAlign.right,
          ],
          rows: rows.map((r) {
            return [
              r['sale_date'] as String? ?? '-',
              '${_toInt(r['transaction_count'])}',
              '${_toInt(r['unique_customers'])}',
              '₱${_peso.format(_toDouble(r['gross_sales']))}',
              '₱${_peso.format(_toDouble(r['refunds']))}',
              '₱${_peso.format(_toDouble(r['net_sales']))}',
            ];
          }).toList(),
          valueAligns: const [
            TextAlign.left,
            TextAlign.center,
            TextAlign.center,
            TextAlign.right,
            TextAlign.right,
            TextAlign.right,
          ],
          accentColumn: 0,
          accentColor: t.blue,
        ),
        if (top.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Top 10 Products',
            style: TextStyle(
              color: t.textHi,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          _TableContainer(
            t: t,
            headers: const ['Code', 'Item Name', 'Qty Sold', 'Revenue'],
            flexes: const [1, 3, 1, 2],
            aligns: const [
              TextAlign.left,
              TextAlign.left,
              TextAlign.center,
              TextAlign.right,
            ],
            rows: top.map((item) {
              return [
                item['product_code'] as String? ?? '-',
                _cleanItemName(item['item_name']),
                '${_toDouble(item['total_qty']).toStringAsFixed(0)}',
                '₱${_peso.format(_toDouble(item['total_revenue']))}',
              ];
            }).toList(),
            valueAligns: const [
              TextAlign.left,
              TextAlign.left,
              TextAlign.center,
              TextAlign.right,
            ],
            accentColumn: 0,
            accentColor: t.blue,
          ),
        ],
        const SizedBox(height: 24),
      ],
    );
  }
}

class _SalesPerClerkView extends StatelessWidget {
  final Map<String, dynamic> data;

  const _SalesPerClerkView({required this.data});

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;
    final rows = _toList(data['rows']);

    final grossTotal = _toDouble(data['grand_gross_total']);
    final refundTotal = _toDouble(data['grand_refunds']);
    final netTotal = _toDouble(data['grand_net_total']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              label: 'Clerks Active',
              value: '${rows.length}',
              color: t.green,
              icon: Icons.badge_rounded,
            ),
            _SummaryCard(
              label: 'Gross Sales',
              value: '₱${_peso.format(grossTotal)}',
              color: t.blue,
              icon: Icons.payments_rounded,
            ),
            _SummaryCard(
              label: 'Refunds',
              value: '₱${_peso.format(refundTotal)}',
              color: t.red,
              icon: Icons.money_off_rounded,
            ),
            _SummaryCard(
              label: 'Net Sales',
              value: '₱${_peso.format(netTotal)}',
              color: t.green,
              icon: Icons.trending_up_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _TableContainer(
          t: t,
          headers: const [
            'Clerk Name',
            'Transactions',
            'Gross',
            'Refunds',
            'Net Sales',
          ],
          flexes: const [3, 1, 2, 2, 2],
          aligns: const [
            TextAlign.left,
            TextAlign.center,
            TextAlign.right,
            TextAlign.right,
            TextAlign.right,
          ],
          rows: rows.map((r) {
            return [
              r['full_name'] as String? ?? '-',
              '${_toInt(r['transaction_count'])}',
              '₱${_peso.format(_toDouble(r['gross_sales']))}',
              '₱${_peso.format(_toDouble(r['refunds']))}',
              '₱${_peso.format(_toDouble(r['net_sales']))}',
            ];
          }).toList(),
          valueAligns: const [
            TextAlign.left,
            TextAlign.center,
            TextAlign.right,
            TextAlign.right,
            TextAlign.right,
          ],
          accentColumn: 0,
          accentColor: t.green,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _TransferView extends StatelessWidget {
  final Map<String, dynamic> data;

  const _TransferView({required this.data});

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;
    final rows = _toList(data['rows']);
    final summary = Map<String, dynamic>.from(data['summary'] as Map? ?? {});
    final grand = _toDouble(summary['grand_total'] ?? data['grand_total']);
    final transferCount = _toInt(summary['transfer_count'] ?? rows.length);
    final totalItems = _toInt(summary['total_items']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              label: 'Transfers',
              value: '$transferCount',
              color: t.purple,
              icon: Icons.swap_horiz_rounded,
            ),
            _SummaryCard(
              label: 'Items Transferred',
              value: '$totalItems',
              color: t.green,
              icon: Icons.inventory_2_rounded,
            ),
            _SummaryCard(
              label: 'Total Value',
              value: '₱${_peso.format(grand)}',
              color: t.blue,
              icon: Icons.payments_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),

        if (rows.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.border),
            ),
            child: Center(
              child: Text(
                'No transfer found for the selected filters.',
                style: TextStyle(color: t.textLo, fontSize: 13),
              ),
            ),
          ),

        ...rows.map((r) {
          final items = _toList(r['items']);
          final transferNo = r['transfer_no']?.toString() ?? '-';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.purple.withOpacity(0.25)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                childrenPadding: EdgeInsets.zero,
                iconColor: t.purple,
                collapsedIconColor: t.textLo,
                title: Row(
                  children: [
                    Flexible(
                      child: Text(
                        transferNo,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: t.purple,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: _StatusBadge(
                        r['status']?.toString() ?? '',
                        color: t.purple,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: t.green.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.green.withOpacity(0.25)),
                      ),
                      child: Text(
                        '${items.length} item${items.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: t.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.warehouse_rounded, size: 13, color: t.textLo),
                          const SizedBox(width: 5),
                          Text(r['warehouse_name']?.toString() ?? '-',
                              style: TextStyle(color: t.textLo, fontSize: 12)),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_forward_rounded, size: 13, color: t.purple),
                          const SizedBox(width: 5),
                          Icon(Icons.store_rounded, size: 13, color: t.textLo),
                          const SizedBox(width: 5),
                          Text(r['store_name']?.toString() ?? '-',
                              style: TextStyle(color: t.textLo, fontSize: 12)),
                        ],
                      ),
                      Text(
                        _formatDateStr(r['transfer_date']?.toString()),
                        style: TextStyle(color: t.textLo, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                trailing: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 90),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '₱${_peso.format(_toDouble(r['total_value'] ?? r['total_amount'] ?? _toList(r['items']).fold<double>(0, (sum, it) => sum + _toDouble(it['subtotal']))))}',
                        style: TextStyle(
                          color: t.textHi,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                children: [
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('No items found in this transfer.',
                          style: TextStyle(color: t.textLo, fontSize: 12)),
                    )
                  else
                    Builder(builder: (context) {
                      final isMobile = MediaQuery.of(context).size.width < 600;
                      if (isMobile) {
                        return Column(
                          children: items.map((it) {
                            return Container(
                              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: t.bg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: t.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(it['product_code']?.toString() ?? '-',
                                      style: TextStyle(color: t.purple, fontSize: 12, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(_cleanItemName(it['item_description']),
                                      style: TextStyle(color: t.textHi, fontSize: 12)),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      Text('Qty: ${_toDouble(it['quantity']).toStringAsFixed(0)}',
                                          style: TextStyle(color: t.textLo, fontSize: 11)),
                                      Text('₱${_peso.format(_toDouble(it['unit_price']))} / unit',
                                          style: TextStyle(color: t.textLo, fontSize: 11)),
                                      Text('Subtotal: ₱${_peso.format(_toDouble(it['subtotal']))}',
                                          style: TextStyle(color: t.textHi, fontSize: 12, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      }
                      return Column(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          color: t.purple.withOpacity(0.08),
                          child: Row(children: [
                            Expanded(flex: 2, child: Text('Code', style: TextStyle(color: t.textHi, fontSize: 11, fontWeight: FontWeight.w700))),
                            Expanded(flex: 5, child: Text('Item Name', style: TextStyle(color: t.textHi, fontSize: 11, fontWeight: FontWeight.w700))),
                            Expanded(flex: 1, child: Text('Qty', textAlign: TextAlign.center, style: TextStyle(color: t.textHi, fontSize: 11, fontWeight: FontWeight.w700))),
                            Expanded(flex: 2, child: Text('Subtotal', textAlign: TextAlign.right, style: TextStyle(color: t.textHi, fontSize: 11, fontWeight: FontWeight.w700))),
                          ]),
                        ),
                        ...items.asMap().entries.map((e) {
                          final it = e.value;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: e.key.isOdd ? Colors.white.withOpacity(0.02) : Colors.transparent,
                              border: e.key < items.length - 1 ? Border(bottom: BorderSide(color: t.border)) : null,
                            ),
                            child: Row(children: [
                              Expanded(flex: 2, child: Text(it['product_code']?.toString() ?? '-', style: TextStyle(color: t.purple, fontSize: 12, fontWeight: FontWeight.w700))),
                              Expanded(flex: 5, child: Text(_cleanItemName(it['item_description']), style: TextStyle(color: t.textHi, fontSize: 12))),
                              Expanded(flex: 1, child: Text(_toDouble(it['quantity']).toStringAsFixed(0), textAlign: TextAlign.center, style: TextStyle(color: t.textLo, fontSize: 12))),
                              Expanded(flex: 2, child: Text('₱${_peso.format(_toDouble(it['subtotal']))}', textAlign: TextAlign.right, style: TextStyle(color: t.textHi, fontSize: 12, fontWeight: FontWeight.w700))),
                            ]),
                          );
                        }),
                      ]);
                    }),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 16),
      ],
    );
  }
}
class _RefundView extends StatelessWidget {
  final Map<String, dynamic> data;

  const _RefundView({required this.data});

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;

    if (data['success'] == false) {
      return _NotReadyView(
        message: data['message'] ?? 'Refunds table not set up yet.',
        sql: 'refunds + refund_items',
      );
    }

    final rows = _toList(data['rows']);
    final total = _toDouble(data['summary']?['total_refunded']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              label: 'Refunds',
              value: '${rows.length}',
              color: t.amber,
              icon: Icons.assignment_return_rounded,
            ),
            _SummaryCard(
              label: 'Total Refunded',
              value: '₱${_peso.format(total)}',
              color: t.red,
              icon: Icons.money_off_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _TableContainer(
          t: t,
          headers: const [
            '#',
            'Txn No.',
            'Type',
            'Store',
            'Original Cashier',
            'Processed By',
            'Amount',
          ],
          flexes: const [1, 2, 1, 2, 2, 2, 2],
          aligns: const [
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.right,
          ],
          rows: rows.map((r) {
            return [
              '#${_toInt(r['refund_id'])}',
              r['transaction_no'] as String? ?? '-',
              r['refund_type'] as String? ?? '-',
              r['store_name'] as String? ?? '-',
              r['original_cashier'] as String? ?? '-',
              r['processed_by'] as String? ?? '-',
              '₱${_peso.format(_toDouble(r['total_amount']))}',
            ];
          }).toList(),
          valueAligns: const [
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.right,
          ],
          accentColor: t.amber,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _DisposalView extends StatelessWidget {
  final Map<String, dynamic> data;

  const _DisposalView({required this.data});

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;

    if (data['success'] == false) {
      return _NotReadyView(
        message: data['message'] ?? 'Disposals table not set up yet.',
        sql: 'disposals + disposal_items',
      );
    }

    final rows = _toList(data['rows']);
    final total = _toDouble(data['summary']?['total_loss']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              label: 'Disposals',
              value: '${rows.length}',
              color: t.orange,
              icon: Icons.delete_sweep_rounded,
            ),
            _SummaryCard(
              label: 'Total Loss',
              value: '₱${_peso.format(total)}',
              color: t.red,
              icon: Icons.trending_down_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        _TableContainer(
          t: t,
          headers: const [
            'Date',
            'Store Name',
            'Reason',
            'Disposed By',
            'Items',
            'Total Loss',
          ],
          flexes: const [2, 2, 3, 2, 1, 2],
          aligns: const [
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.center,
            TextAlign.right,
          ],
          rows: rows.map((r) {
            return [
              _formatDateStr(r['disposal_date'] as String?),
              r['store_name'] as String? ?? '-',
              r['reason'] as String? ?? '-',
              r['disposed_by'] as String? ?? '-',
              '${_toInt(r['item_count'])}',
              '₱${_peso.format(_toDouble(r['total_loss']))}',
            ];
          }).toList(),
          valueAligns: const [
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.left,
            TextAlign.center,
            TextAlign.right,
          ],
          accentColor: t.orange,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _LowStockView extends StatelessWidget {
  final Map<String, dynamic> data;
  final int threshold;

  const _LowStockView({
    required this.data,
    required this.threshold,
  });

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;
    final all = _toList(data['all']);
    final counts = Map<String, dynamic>.from(data['counts'] as Map? ?? {});

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              label: 'Warehouse',
              value: '${_toInt(counts['warehouse'])} items',
              color: t.blue,
              icon: Icons.warehouse_rounded,
            ),
            _SummaryCard(
              label: 'Store',
              value: '${_toInt(counts['store'])} items',
              color: t.green,
              icon: Icons.store_rounded,
            ),
            _SummaryCard(
              label: 'Total Alerts',
              value: '${_toInt(counts['total'])}',
              color: t.red,
              icon: Icons.warning_amber_rounded,
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          'Items at or below $threshold units',
          style: TextStyle(
            color: t.red.withOpacity(0.8),
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 10),
        ...all.map((r) {
          final qty = _toInt(r['quantity']);
          final pct = (qty / threshold).clamp(0.0, 1.0);

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: t.red.withOpacity(qty == 0 ? 0.5 : 0.2),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: t.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.red.withOpacity(0.3)),
                  ),
                  child: Center(
                    child: Text(
                      '$qty',
                      style: TextStyle(
                        color: qty == 0 ? t.red : t.amber,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            r['product_code'] as String? ?? '-',
                            style: TextStyle(
                              color: t.blue,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _StatusBadge(
                            r['source'] as String? ?? '',
                            color: r['source'] == 'Warehouse'
                                ? t.blue
                                : t.green,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _cleanItemName(r['item_description']),
                        style: TextStyle(
                          color: t.textHi,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        r['location_name'] as String? ?? '-',
                        style: TextStyle(
                          color: t.textLo,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct,
                          minHeight: 4,
                          backgroundColor: t.red.withOpacity(0.15),
                          valueColor: AlwaysStoppedAnimation<Color>(
                            qty == 0 ? t.red : t.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '₱${_peso.format(_toDouble(r['unit_price']))}',
                  style: TextStyle(color: t.textLo, fontSize: 12),
                ),
              ],
            ),
          );
        }),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _NotReadyView extends StatelessWidget {
  final String message;
  final String sql;

  const _NotReadyView({
    required this.message,
    required this.sql,
  });

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.amber.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.construction_rounded, color: t.amber, size: 22),
              const SizedBox(width: 10),
              Text(
                'Tables Not Yet Created',
                style: TextStyle(
                  color: t.amber,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: TextStyle(color: t.textLo, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.bg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Required tables: $sql',
              style: TextStyle(
                color: t.textHi,
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final ReportType type;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.type,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;
    final c = type.color;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 0 : 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: selected ? c.withOpacity(0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected ? Border.all(color: c.withOpacity(0.35)) : null,
        ),
        child: compact
            ? Center(
          child: Icon(
            type.icon,
            color: selected ? c : t.textLo,
            size: 20,
          ),
        )
            : Row(
          children: [
            Icon(
              type.icon,
              color: selected ? c : t.textLo,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                type.label,
                style: TextStyle(
                  color: selected ? c : t.textLo,
                  fontSize: 12,
                  fontWeight:
                  selected ? FontWeight.w700 : FontWeight.normal,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: color.withOpacity(0.75),
                  fontSize: 10,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  final Color color;

  const _StatusBadge(
      this.status, {
        this.color = AppColors.blue,
      });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TableContainer extends StatelessWidget {
  final AppTheme t;
  final List<String> headers;
  final List<int> flexes;
  final List<TextAlign> aligns;
  final List<TextAlign> valueAligns;
  final List<List<String>> rows;
  final int? accentColumn;
  final Color accentColor;

  const _TableContainer({
    required this.t,
    required this.headers,
    required this.flexes,
    required this.aligns,
    required this.valueAligns,
    required this.rows,
    this.accentColumn = 0,
    this.accentColor = AppColors.blue,
  });

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;

    if (rows.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.border),
        ),
        child: Center(
          child: Text(
            'No data found for the selected filters.',
            style: TextStyle(color: t.textLo, fontSize: 13),
          ),
        ),
      );
    }

    if (isMobile) {
      return Column(
        children: rows.asMap().entries.map((entry) {
          final i = entry.key;
          final row = entry.value;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(headers.length, (j) {
                final isAccent = j == accentColumn;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          headers[j],
                          style: TextStyle(
                            color: t.textLo,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          row[j],
                          style: TextStyle(
                            color: isAccent ? accentColor : t.textHi,
                            fontSize: 12,
                            fontWeight: isAccent
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          );
        }).toList(),
      );
    }

    // Desktop table (unchanged)
    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: t.blue.withOpacity(0.12),
              borderRadius:
              const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: List.generate(
                headers.length,
                    (i) => Expanded(
                  flex: flexes[i],
                  child: Text(
                    headers[i],
                    textAlign: aligns[i],
                    style: TextStyle(
                      color: t.textHi,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
          ...rows.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            return Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: i.isOdd
                    ? Colors.white.withOpacity(0.02)
                    : Colors.transparent,
                border: i < rows.length - 1
                    ? Border(bottom: BorderSide(color: t.border))
                    : null,
              ),
              child: Row(
                children: List.generate(
                  row.length,
                      (j) => Expanded(
                    flex: flexes[j],
                    child: Text(
                      row[j],
                      textAlign: valueAligns[j],
                      style: TextStyle(
                        color: j == accentColumn ? accentColor : t.textHi,
                        fontSize: 12,
                        fontWeight: j == accentColumn
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _FilterDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T) labelOf;
  final void Function(T?) onChanged;
  final AppTheme t;

  const _FilterDropdown({
    required this.t,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          dropdownColor: t.surface,
          style: TextStyle(color: t.textHi, fontSize: 12),
          icon: Icon(Icons.expand_more_rounded, color: t.textLo, size: 18),
          items: items
              .map(
                (it) => DropdownMenuItem<T>(
              value: it,
              child: Text(labelOf(it)),
            ),
          )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _DateChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final AppTheme t;

  const _DateChip({
    required this.t,
    required this.label,
    required this.active,
    required this.onTap,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active ? t.blue.withOpacity(0.12) : t.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? t.blue.withOpacity(0.4) : t.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.calendar_today_rounded,
              color: active ? t.blue : t.textLo,
              size: 15,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? t.blue : t.textLo,
                fontSize: 12,
              ),
            ),
            if (onClear != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onClear,
                child: Icon(
                  Icons.close_rounded,
                  color: t.textLo,
                  size: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThresholdChip extends StatelessWidget {
  final AppTheme t;
  final int value;
  final void Function(int) onChanged;

  const _ThresholdChip({
    required this.t,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: t.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.red.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded, color: t.red, size: 15),
          const SizedBox(width: 8),
          Text(
            'Threshold:',
            style: TextStyle(color: t.textLo, fontSize: 12),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              dropdownColor: t.surface,
              style: TextStyle(
                color: t.red,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
              icon: Icon(
                Icons.expand_more_rounded,
                color: t.textLo,
                size: 16,
              ),
              items: [5, 10, 15, 20, 25, 50]
                  .map(
                    (v) => DropdownMenuItem(
                  value: v,
                  child: Text('$v'),
                ),
              )
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
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
    final t = themeNotifier.theme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, color: t.textLo, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              style: TextStyle(color: t.textLo, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: t.blue),
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

String _formatDateStr(String? raw) {
  if (raw == null || raw.isEmpty) return '-';

  try {
    return _dateFmt.format(DateTime.parse(raw));
  } catch (_) {
    return raw;
  }
}

class _BadOrderView extends StatelessWidget {
  final Map<String, dynamic> data;

  const _BadOrderView({required this.data});

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;
    final rows = _toList(data['rows']);
    final summary = Map<String, dynamic>.from(data['summary'] as Map? ?? {});

    final count = _toInt(summary['count'] ?? rows.length);
    final totalQty = _toDouble(summary['total_qty']);
    final totalAmount = _toDouble(summary['total_amount']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              label: 'Bad Orders',
              value: '$count',
              color: t.purple,
              icon: Icons.inventory_2_rounded,
            ),
            _SummaryCard(
              label: 'Total Qty',
              value: totalQty.toStringAsFixed(0),
              color: t.green,
              icon: Icons.format_list_numbered_rounded,
            ),
            _SummaryCard(
              label: 'Total Amount',
              value: '₱${_peso.format(totalAmount)}',
              color: t.red,
              icon: Icons.trending_down_rounded,
            ),
          ],
        ),

        const SizedBox(height: 20),

        if (rows.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.border),
            ),
            child: Center(
              child: Text(
                'No bad order records found.',
                style: TextStyle(color: t.textLo, fontSize: 13),
              ),
            ),
          ),

        ...rows.map((r) {
          final items = _toList(r['items']);
          final boNo = r['bo_no']?.toString() ?? '-';

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.purple.withOpacity(0.25)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                childrenPadding: EdgeInsets.zero,
                iconColor: t.purple,
                collapsedIconColor: t.textLo,

                title: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      boNo,
                      style: TextStyle(
                        color: t.purple,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    _StatusBadge(
                      r['status']?.toString() ?? '',
                      color: t.purple,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: t.green.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: t.green.withOpacity(0.25),
                        ),
                      ),
                      child: Text(
                        '${items.length} item${items.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: t.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.store_rounded, size: 13, color: t.textLo),
                          const SizedBox(width: 5),
                          Text(r['store_name']?.toString() ?? '-',
                              style: TextStyle(color: t.textLo, fontSize: 12)),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.person_rounded, size: 13, color: t.textLo),
                          const SizedBox(width: 5),
                          Text(r['created_by']?.toString() ?? '-',
                              style: TextStyle(color: t.textLo, fontSize: 12)),
                        ],
                      ),
                      Text(
                        _formatDateStr(r['created_at']?.toString()),
                        style: TextStyle(color: t.textLo, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₱${_peso.format(_toDouble(r['total_amount']))}',
                      style: TextStyle(
                        color: t.textHi,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Icon(Icons.expand_more_rounded, color: t.textLo),
                  ],
                ),

                children: [
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No items found in this bad order.',
                        style: TextStyle(
                          color: t.textLo,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      color: t.purple.withOpacity(0.08),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              'Code',
                              style: TextStyle(
                                color: t.textHi,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),

                          Expanded(
                            flex: 5,
                            child: Text(
                              'Item Name',
                              style: TextStyle(
                                color: t.textHi,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),

                          Expanded(
                            flex: 1,
                            child: Text(
                              'Qty',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: t.textHi,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),

                          Expanded(
                            flex: 2,
                            child: Text(
                              'Subtotal',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: t.textHi,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    ...items.asMap().entries.map((e) {
                      final it = e.value;

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: e.key.isOdd
                              ? Colors.white.withOpacity(0.02)
                              : Colors.transparent,
                          border: e.key < items.length - 1
                              ? Border(
                            bottom: BorderSide(color: t.border),
                          )
                              : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: Text(
                                it['product_code']?.toString() ?? '-',
                                style: TextStyle(
                                  color: t.purple,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),

                            Expanded(
                              flex: 5,
                              child: Text(
                                _cleanItemName(
                                  it['item_description'],
                                ),
                                style: TextStyle(
                                  color: t.textHi,
                                  fontSize: 12,
                                ),
                              ),
                            ),

                            Expanded(
                              flex: 1,
                              child: Text(
                                _toDouble(it['quantity'])
                                    .toStringAsFixed(0),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: t.textLo,
                                  fontSize: 12,
                                ),
                              ),
                            ),

                            Expanded(
                              flex: 2,
                              child: Text(
                                '₱${_peso.format(_toDouble(it['subtotal']))}',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  color: t.textHi,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 16),
      ],
    );
  }
}

class _PromoSalesView extends StatelessWidget {
  final Map<String, dynamic> data;

  const _PromoSalesView({required this.data});

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;
    final rows = _toList(data['rows']);
    final summary = Map<String, dynamic>.from(data['summary'] as Map? ?? {});

    final promoCount  = _toInt(summary['promo_count']);
    final totalQty    = _toDouble(summary['total_qty']);
    final totalDiscount = _toDouble(summary['total_discount']);
    final totalRevenue  = _toDouble(summary['total_revenue']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SummaryCard(
              label: 'Promos Used',
              value: '$promoCount',
              color: t.teal,
              icon: Icons.local_offer_rounded,
            ),
            _SummaryCard(
              label: 'Total Qty Sold',
              value: totalQty.toStringAsFixed(0),
              color: t.green,
              icon: Icons.format_list_numbered_rounded,
            ),
            _SummaryCard(
              label: 'Total Discount',
              value: '₱${_peso.format(totalDiscount)}',
              color: t.amber,
              icon: Icons.discount_rounded,
            ),
            _SummaryCard(
              label: 'Total Revenue',
              value: '₱${_peso.format(totalRevenue)}',
              color: t.blue,
              icon: Icons.payments_rounded,
            ),
          ],
        ),

        const SizedBox(height: 20),

        if (rows.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.border),
            ),
            child: Center(
              child: Text(
                'No promo sales found for the selected filters.',
                style: TextStyle(color: t.textLo, fontSize: 13),
              ),
            ),
          ),

        ...rows.map((r) {
          final items = _toList(r['items']);
          final promoName = r['promo_name']?.toString() ?? '-';
          final promoNo   = r['promo_no']?.toString() ?? '-';
          final status    = r['promo_status']?.toString() ?? '';
          final supplier  = r['supplier_name']?.toString() ?? '-';
          final calcName  = r['calculation_name']?.toString() ?? 'Promo Price';
          final dateFrom  = _formatDateStr(r['date_from']?.toString());
          final dateTo    = _formatDateStr(r['date_to']?.toString());

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: t.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.teal.withOpacity(0.25)),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
                splashColor: Colors.transparent,
                highlightColor: Colors.transparent,
              ),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 6),
                childrenPadding: EdgeInsets.zero,
                iconColor: t.teal,
                collapsedIconColor: t.textLo,

                title: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      promoNo,
                      style: TextStyle(
                        color: t.teal,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    _StatusBadge(status, color: t.teal),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: t.green.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: t.green.withOpacity(0.25)),
                      ),
                      child: Text(
                        '${items.length} product${items.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: t.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        promoName,
                        style: TextStyle(
                          color: t.textHi,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.business_rounded, size: 12, color: t.textLo),
                              const SizedBox(width: 4),
                              Text(supplier,
                                  style: TextStyle(color: t.textLo, fontSize: 11)),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tag_rounded, size: 12, color: t.textLo),
                              const SizedBox(width: 4),
                              Text(calcName,
                                  style: TextStyle(color: t.textLo, fontSize: 11)),
                            ],
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.date_range_rounded, size: 12, color: t.textLo),
                              const SizedBox(width: 4),
                              Text('$dateFrom – $dateTo',
                                  style: TextStyle(color: t.textLo, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '₱${_peso.format(_toDouble(r['total_revenue']))}',
                      style: TextStyle(
                        color: t.textHi,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '−₱${_peso.format(_toDouble(r['total_discount']))}',
                      style: TextStyle(color: t.amber, fontSize: 10),
                    ),
                  ],
                ),

                children: [
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'No product breakdown available.',
                        style: TextStyle(color: t.textLo, fontSize: 12),
                      ),
                    )
                  else
                    Builder(builder: (context) {
                      final isMobile = MediaQuery.of(context).size.width < 600;
                      if (isMobile) {
                        return Column(
                          children: items.map((it) {
                            final promoPrice = it['promo_price'];
                            final remaining = it['promo_qty_remaining'];
                            final limit = it['promo_qty_limit'];
                            return Container(
                              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: t.bg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: t.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(it['product_code']?.toString() ?? '-',
                                      style: TextStyle(color: t.teal, fontSize: 12, fontWeight: FontWeight.w700)),
                                  const SizedBox(height: 4),
                                  Text(_cleanItemName(it['item_name']),
                                      style: TextStyle(color: t.textHi, fontSize: 12)),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 12,
                                    runSpacing: 4,
                                    children: [
                                      Text('Orig: ₱${_peso.format(_toDouble(it['original_price']))}',
                                          style: TextStyle(color: t.textLo, fontSize: 11)),
                                      if (promoPrice != null)
                                        Text('Promo: ₱${_peso.format(_toDouble(promoPrice))}',
                                            style: TextStyle(color: t.green, fontSize: 11, fontWeight: FontWeight.w600)),
                                      Text('Qty: ${_toDouble(it['qty_sold']).toStringAsFixed(0)}',
                                          style: TextStyle(color: t.textLo, fontSize: 11)),
                                      Text('Discount: ₱${_peso.format(_toDouble(it['total_discount']))}',
                                          style: TextStyle(color: t.amber, fontSize: 11)),
                                      if (remaining != null)
                                        Text('Remaining: ${(remaining as num).toStringAsFixed(0)} / ${(limit as num).toStringAsFixed(0)}',
                                            style: TextStyle(color: t.textLo, fontSize: 11)),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      }
                      // Desktop layout
                      return Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            color: t.teal.withOpacity(0.08),
                            child: Row(children: [
                              Expanded(flex: 2, child: Text('Code', style: TextStyle(color: t.textHi, fontSize: 11, fontWeight: FontWeight.w700))),
                              Expanded(flex: 4, child: Text('Item Name', style: TextStyle(color: t.textHi, fontSize: 11, fontWeight: FontWeight.w700))),
                              Expanded(flex: 2, child: Text('Orig Price', textAlign: TextAlign.right, style: TextStyle(color: t.textHi, fontSize: 11, fontWeight: FontWeight.w700))),
                              Expanded(flex: 2, child: Text('Promo Price', textAlign: TextAlign.right, style: TextStyle(color: t.textHi, fontSize: 11, fontWeight: FontWeight.w700))),
                              Expanded(flex: 1, child: Text('Qty', textAlign: TextAlign.center, style: TextStyle(color: t.textHi, fontSize: 11, fontWeight: FontWeight.w700))),
                              Expanded(flex: 2, child: Text('Discount', textAlign: TextAlign.right, style: TextStyle(color: t.textHi, fontSize: 11, fontWeight: FontWeight.w700))),
                              Expanded(flex: 2, child: Text('Remaining', textAlign: TextAlign.center, style: TextStyle(color: t.textHi, fontSize: 11, fontWeight: FontWeight.w700))),
                            ]),
                          ),
                          ...items.asMap().entries.map((e) {
                            final it = e.value;
                            final remaining = it['promo_qty_remaining'];
                            final limit = it['promo_qty_limit'];
                            final promoPrice = it['promo_price'];
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: e.key.isOdd ? Colors.white.withOpacity(0.02) : Colors.transparent,
                                border: e.key < items.length - 1 ? Border(bottom: BorderSide(color: t.border)) : null,
                              ),
                              child: Row(children: [
                                Expanded(flex: 2, child: Text(it['product_code']?.toString() ?? '-', style: TextStyle(color: t.teal, fontSize: 12, fontWeight: FontWeight.w700))),
                                Expanded(flex: 4, child: Text(_cleanItemName(it['item_name']), style: TextStyle(color: t.textHi, fontSize: 12))),
                                Expanded(flex: 2, child: Text('₱${_peso.format(_toDouble(it['original_price']))}', textAlign: TextAlign.right, style: TextStyle(color: t.textLo, fontSize: 12))),
                                Expanded(flex: 2, child: Text(promoPrice != null ? '₱${_peso.format(_toDouble(promoPrice))}' : '—', textAlign: TextAlign.right, style: TextStyle(color: t.green, fontSize: 12, fontWeight: FontWeight.w600))),
                                Expanded(flex: 1, child: Text(_toDouble(it['qty_sold']).toStringAsFixed(0), textAlign: TextAlign.center, style: TextStyle(color: t.textLo, fontSize: 12))),
                                Expanded(flex: 2, child: Text('₱${_peso.format(_toDouble(it['total_discount']))}', textAlign: TextAlign.right, style: TextStyle(color: t.amber, fontSize: 12))),
                                Expanded(flex: 2, child: Text(remaining != null ? '${(remaining as num).toStringAsFixed(0)} / ${(limit as num).toStringAsFixed(0)}' : '—', textAlign: TextAlign.center, style: TextStyle(color: remaining != null && (remaining as num) <= 0 ? t.red : t.textLo, fontSize: 12))),
                              ]),
                            );
                          }),
                        ],
                      );
                    }),
                ],
              ),
            ),
          );
        }),

        const SizedBox(height: 16),
      ],
    );
  }
}
class _ReportPagination extends StatelessWidget {
  final int page;
  final int limit;
  final int total;
  final List<int> limitOptions;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<int> onLimitChanged;

  const _ReportPagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.limitOptions,
    required this.onPageChanged,
    required this.onLimitChanged,
  });

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;
    final totalPages = total <= 0 ? 1 : (total / limit).ceil();

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          'Total: $total',
          style: TextStyle(color: t.textHi, fontSize: 13),
        ),
        const SizedBox(width: 12),
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: limit,
              dropdownColor: t.surface,
              style: TextStyle(color: t.textHi, fontSize: 13),
              items: limitOptions
                  .map(
                    (v) => DropdownMenuItem(
                  value: v,
                  child: Text('$v'),
                ),
              )
                  .toList(),
              onChanged: (v) {
                if (v != null) onLimitChanged(v);
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        IconButton(
          onPressed: page > 1 ? () => onPageChanged(page - 1) : null,
          icon: Icon(Icons.chevron_left_rounded, color: t.textHi),
        ),
        Text(
          '$page / $totalPages',
          style: TextStyle(
            color: t.textHi,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        IconButton(
          onPressed: page < totalPages ? () => onPageChanged(page + 1) : null,
          icon: Icon(Icons.chevron_right_rounded, color: t.textHi),
        ),
      ],
    );
  }
}