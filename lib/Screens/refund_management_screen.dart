import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../DB/DBResult.dart';
import '../Utils/app_theme.dart';

double _toDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

List<Map<String, dynamic>> _toList(dynamic v) =>
    (v as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];

final _peso = NumberFormat('#,##0.00', 'en_PH');
final _dtFmt = DateFormat('MMM dd, yyyy hh:mm a');

class RefundManagementScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;
  const RefundManagementScreen({super.key, this.currentUser});

  @override
  State<RefundManagementScreen> createState() => _RefundManagementScreenState();
}

class _RefundManagementScreenState extends State<RefundManagementScreen> {
  final _txnCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();

  bool _loading = false;
  bool _processing = false;
  String? _error;

  Map<String, dynamic>? _transaction;
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _history = [];

  final Map<int, TextEditingController> _qtyCtrls = {};

  @override
  void dispose() {
    _txnCtrl.dispose();
    _reasonCtrl.dispose();
    for (final c in _qtyCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _lookup() async {
    FocusScope.of(context).unfocus();
    final txnNo = _txnCtrl.text.trim();

    if (txnNo.isEmpty) {
      setState(() => _error = 'Please enter a transaction number.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _transaction = null;
      _items = [];
      _history = [];
      for (final c in _qtyCtrls.values) {
        c.dispose();
      }
      _qtyCtrls.clear();
    });

    final res = await DBService.instance.refundLookup(transactionNo: txnNo);

    if (!mounted) return;

    if (!res.success || res.data == null) {
      setState(() {
        _loading = false;
        _error = res.message;
      });
      return;
    }

    final tx = Map<String, dynamic>.from(res.data!['transaction'] as Map);
    final items = _toList(res.data!['items']);
    final history = _toList(res.data!['refund_history']);

    for (final item in items) {
      final itemId = _toInt(item['item_id']);
      _qtyCtrls[itemId] = TextEditingController(text: '');
    }

    setState(() {
      _loading = false;
      _transaction = tx;
      _items = items;
      _history = history;
      _reasonCtrl.text = '';
    });
  }

  double _lineRefundAmount(Map<String, dynamic> item) {
    final itemId = _toInt(item['item_id']);
    final qty = double.tryParse(_qtyCtrls[itemId]?.text.trim() ?? '') ?? 0;
    final unitPrice = _toDouble(item['unit_price']);
    return qty * unitPrice;
  }

  double get _refundTotal {
    double total = 0;
    for (final item in _items) {
      total += _lineRefundAmount(item);
    }
    return total;
  }

  bool get _hasRefundInput {
    for (final item in _items) {
      final itemId = _toInt(item['item_id']);
      final qty = double.tryParse(_qtyCtrls[itemId]?.text.trim() ?? '') ?? 0;
      if (qty > 0) return true;
    }
    return false;
  }

  Future<void> _processRefund() async {
    if (_transaction == null) return;

    final reason = _reasonCtrl.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a refund reason.')),
      );
      return;
    }

    final selectedItems = <Map<String, dynamic>>[];

    for (final item in _items) {
      final itemId = _toInt(item['item_id']);
      final soldQty = _toDouble(item['quantity']);
      final refundQty = double.tryParse(_qtyCtrls[itemId]?.text.trim() ?? '') ?? 0;

      if (refundQty <= 0) continue;

      if (refundQty > soldQty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Refund qty exceeds sold qty for ${item['item_name']}')),
        );
        return;
      }

      selectedItems.add({
        'item_id': itemId,
        'refund_qty': refundQty,
      });
    }

    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one refund quantity.')),
      );
      return;
    }

    final currentTxnTotal = _toDouble(_transaction!['total_amount']);
    if (_refundTotal > currentTxnTotal) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Refund total cannot exceed transaction total.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        final t = themeNotifier.theme;
        return AlertDialog(
          backgroundColor: t.surface,
          title: Text('Confirm Refund', style: TextStyle(color: t.textHi)),
          content: Text(
            'Process refund amount of ₱${_peso.format(_refundTotal)}?',
            style: TextStyle(color: t.textLo),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Process'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _processing = true);

    final res = await DBService.instance.processRefund(
      transactionId: _toInt(_transaction!['transaction_id']),
      userId: _toInt(widget.currentUser?['user_id']),
      reason: reason,
      items: selectedItems,
    );

    if (!mounted) return;

    setState(() => _processing = false);

    if (!res.success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.message)),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(res.message)),
    );

    await _lookup();
  }

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;

    return Container(
      color: t.bg,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Refund Management',
                style: TextStyle(
                  color: t.textHi,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                )),
            const SizedBox(height: 6),
            Text(
              'Validate refund cost against sales cost, process the refund, and track who refunded each transaction.',
              style: TextStyle(color: t.textLo, fontSize: 13),
            ),
            const SizedBox(height: 20),

            _card(
              t,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Search Transaction',
                      style: TextStyle(
                        color: t.textHi,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      )),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _txnCtrl,
                          style: TextStyle(color: t.textHi),
                          decoration: InputDecoration(
                            hintText: 'Enter transaction no. e.g. TRX-000025',
                            hintStyle: TextStyle(color: t.textLo),
                            filled: true,
                            fillColor: t.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onSubmitted: (_) => _lookup(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _loading ? null : _lookup,
                          icon: _loading
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.search),
                          label: const Text('Search'),
                        ),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: t.red)),
                  ],
                ],
              ),
            ),

            if (_transaction != null) ...[
              const SizedBox(height: 18),
              _buildTransactionCard(t),
              const SizedBox(height: 18),
              _buildItemsCard(t),
              const SizedBox(height: 18),
              _buildReasonCard(t),
              const SizedBox(height: 18),
              _buildHistoryCard(t),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(AppTheme t) {
    return _card(
      t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Transaction Details',
              style: TextStyle(color: t.textHi, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 14),
          Wrap(
            runSpacing: 12,
            spacing: 20,
            children: [
              _infoChip(t, 'Transaction No', '${_transaction!['transaction_no']}'),
              _infoChip(t, 'Store', '${_transaction!['store_name']}'),
              _infoChip(t, 'Cashier', '${_transaction!['cashier_name']}'),
              _infoChip(t, 'Customer', '${_transaction!['customer_name']}'),
              _infoChip(t, 'Original Total', '₱${_peso.format(_toDouble(_transaction!['total_amount']))}'),
              _infoChip(t, 'Date', _formatDate(_transaction!['created_at']?.toString())),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCard(AppTheme t) {
    return _card(
      t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Sold Items / Refund Validation',
              style: TextStyle(color: t.textHi, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 8),
          Text(
            'Refund amount is validated using the original sales unit price per item.',
            style: TextStyle(color: t.textLo, fontSize: 12),
          ),
          const SizedBox(height: 16),

          Container(
            decoration: BoxDecoration(
              border: Border.all(color: t.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                _tableHeader(t),
                ..._items.map((item) => _tableRow(t, item)),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                'Refund Total: ',
                style: TextStyle(color: t.textLo, fontSize: 14),
              ),
              Text(
                '₱${_peso.format(_refundTotal)}',
                style: TextStyle(
                  color: t.red,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReasonCard(AppTheme t) {
    return _card(
      t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Process Refund',
              style: TextStyle(color: t.textHi, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 12),
          TextField(
            controller: _reasonCtrl,
            maxLines: 3,
            style: TextStyle(color: t.textHi),
            decoration: InputDecoration(
              hintText: 'Enter reason for refund',
              hintStyle: TextStyle(color: t.textLo),
              filled: true,
              fillColor: t.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: (!_hasRefundInput || _processing) ? null : _processRefund,
              icon: _processing
                  ? const SizedBox(
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.assignment_return_rounded),
              label: const Text('Process Refund'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard(AppTheme t) {
    return _card(
      t,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Refund History',
              style: TextStyle(color: t.textHi, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 14),
          if (_history.isEmpty)
            Text('No refund history for this transaction yet.',
                style: TextStyle(color: t.textLo))
          else
            ..._history.map((r) {
              final items = _toList(r['items']);
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: t.bg.withOpacity(0.45),
                  border: Border.all(color: t.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ExpansionTile(
                  collapsedIconColor: t.textLo,
                  iconColor: t.textHi,
                  title: Text(
                    'Refund #${_toInt(r['refund_id'])}  •  ₱${_peso.format(_toDouble(r['total_amount']))}',
                    style: TextStyle(color: t.textHi, fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'By ${r['processed_by'] ?? '-'} • ${_formatDate(r['refund_date']?.toString())} • ${r['reason'] ?? '-'}',
                    style: TextStyle(color: t.textLo, fontSize: 12),
                  ),
                  children: items.map((it) {
                    return ListTile(
                      dense: true,
                      title: Text(
                        '${it['item_name']}',
                        style: TextStyle(color: t.textHi),
                      ),
                      subtitle: Text(
                        '${it['product_code']} • Qty ${_toDouble(it['quantity']).toStringAsFixed(0)} • ₱${_peso.format(_toDouble(it['unit_price']))}',
                        style: TextStyle(color: t.textLo),
                      ),
                      trailing: Text(
                        '₱${_peso.format(_toDouble(it['subtotal']))}',
                        style: TextStyle(color: t.red, fontWeight: FontWeight.w700),
                      ),
                    );
                  }).toList(),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _tableHeader(AppTheme t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.blue.withOpacity(0.12),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Row(
        children: [
          _th('Code', 2, t),
          _th('Item', 4, t),
          _th('Price', 2, t, align: TextAlign.right),
          _th('Sold Qty', 2, t, align: TextAlign.center),
          _th('Refund Qty', 2, t, align: TextAlign.center),
          _th('Refund Amount', 2, t, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _tableRow(AppTheme t, Map<String, dynamic> item) {
    final itemId = _toInt(item['item_id']);
    final soldQty = _toDouble(item['quantity']);

    return StatefulBuilder(
      builder: (context, setLocal) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: Row(
            children: [
              _td('${item['product_code']}', 2, t),
              _td('${item['item_name']}', 4, t),
              _td('₱${_peso.format(_toDouble(item['unit_price']))}', 2, t, align: TextAlign.right),
              _td(soldQty.toStringAsFixed(0), 2, t, align: TextAlign.center),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: TextField(
                    controller: _qtyCtrls[itemId],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: t.textHi),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: t.surface,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                    ),
                    onChanged: (_) {
                      setLocal(() {});
                      setState(() {});
                    },
                  ),
                ),
              ),
              _td('₱${_peso.format(_lineRefundAmount(item))}', 2, t, align: TextAlign.right, color: t.red),
            ],
          ),
        );
      },
    );
  }

  Widget _th(String text, int flex, AppTheme t, {TextAlign align = TextAlign.left}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(color: t.textHi, fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  Widget _td(String text, int flex, AppTheme t, {TextAlign align = TextAlign.left, Color? color}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(color: color ?? t.textHi, fontSize: 12),
      ),
    );
  }

  Widget _card(AppTheme t, {required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.border),
      ),
      child: child,
    );
  }

  Widget _infoChip(AppTheme t, String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 170),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.bg.withOpacity(0.45),
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: t.textLo, fontSize: 11)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(color: t.textHi, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  String _formatDate(String? value) {
    if (value == null || value.isEmpty) return '-';
    try {
      return _dtFmt.format(DateTime.parse(value));
    } catch (_) {
      return value;
    }
  }
}