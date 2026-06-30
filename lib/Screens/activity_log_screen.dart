// import 'package:flutter/material.dart';
// import 'package:flutter/foundation.dart';
// import 'dart:io';
//
// import '../db/DBResult.dart';
// import '../Utils/app_theme.dart';
// import 'inventory_screen.dart';
//
// // ── Palette ───────────────────────────────────────────────────────────────
// AppTheme get _t => themeNotifier.theme;
// Color get _bg => _t.bg;
// Color get _surface => _t.surface;
// Color get _border => _t.border;
// Color get _blue => _t.blue;
// Color get _green => _t.green;
// Color get _amber => _t.amber;
// Color get _red => _t.red;
// Color get _teal => _t.teal;
// Color get _textHi => _t.textHi;
// Color get _textLo => _t.textLo;
//
// int _toInt(dynamic v) {
//   if (v == null) return 0;
//   if (v is int) return v;
//   if (v is num) return v.toInt();
//   return int.tryParse(v.toString()) ?? 0;
// }
//
// String _toStr(dynamic v) => v?.toString() ?? '';
//
// String _dateOnly(DateTime d) =>
//     '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
//
// /// Pretty label for a module/sub_module pair, e.g. "INVENTORY · WAREHOUSE_STOCK".
// String _moduleLabel(Map<String, dynamic> log) {
//   final m = _toStr(log['module']);
//   final sm = _toStr(log['sub_module']);
//   if (m.isEmpty) return '—';
//   return sm.isEmpty ? m : '$m · $sm';
// }
//
// /// Colour + icon per action (CREATE/UPDATE/DELETE/SALE/REFUND/etc.)
// ({Color color, IconData icon}) _actionStyle(String action) {
//   final a = action.toUpperCase();
//   if (a.startsWith('CREATE') || a == 'INSERT' || a == 'RECEIVE') {
//     return (color: const Color(0xFF4CAF50), icon: Icons.add_circle_rounded);
//   }
//   if (a.startsWith('UPDATE')) {
//     return (color: const Color(0xFF378ADD), icon: Icons.edit_rounded);
//   }
//   if (a.startsWith('DELETE')) {
//     return (color: const Color(0xFFEF5350), icon: Icons.delete_rounded);
//   }
//   if (a.contains('CANCEL')) {
//     return (color: const Color(0xFFFFB300), icon: Icons.cancel_rounded);
//   }
//   if (a.contains('LOGIN') || a.contains('LOGOUT')) {
//     return (color: const Color(0xFF1D9E75), icon: Icons.login_rounded);
//   }
//   if (a == 'SALE') {
//     return (color: const Color(0xFF26A69A), icon: Icons.point_of_sale_rounded);
//   }
//   if (a == 'REFUND') {
//     return (color: const Color(0xFFFF7043), icon: Icons.assignment_return_rounded);
//   }
//   if (a == 'IMPORT' || a == 'EXPORT') {
//     return (color: const Color(0xFF8E7CC3), icon: Icons.swap_vert_rounded);
//   }
//   if (a == 'TRANSFER') {
//     return (color: const Color(0xFF42A5F5), icon: Icons.compare_arrows_rounded);
//   }
//   return (color: const Color(0xFF888780), icon: Icons.history_rounded);
// }
//
// class AuditLogScreen extends StatefulWidget {
//   final Map<String, dynamic>? currentUser;
//   const AuditLogScreen({super.key, this.currentUser});
//
//   @override
//   State<AuditLogScreen> createState() => _AuditLogScreenState();
// }
//
// class _AuditLogScreenState extends State<AuditLogScreen> {
//   bool _loading = true;
//   String? _error;
//
//   List<Map<String, dynamic>> _logs = [];
//   List<String> _availableActions = [];
//   List<String> _availableModules = [];
//
//   // ── Filters ──────────────────────────────────────────────────────────────
//   String _search = '';
//   String _action = 'ALL';
//   String _module = 'ALL';
//   DateTime? _dateFrom;
//   DateTime? _dateTo;
//
//   final _searchCtrl = TextEditingController();
//
//   // ── Pagination (server-side) ─────────────────────────────────────────────
//   int _page = 1;
//   int _limit = 50;
//   int _totalPages = 1;
//   int _total = 0;
//   final List<int> _pageSizeOptions = const [25, 50, 100, 200];
//
//   bool get _isWindows {
//     try { return !kIsWeb && Platform.isWindows; } catch (_) { return false; }
//   }
//
//   List<Map<String, dynamic>> get _permissions {
//     final rawAdmin = widget.currentUser?['admin_modules'];
//     final rawAll = widget.currentUser?['permissions'];
//     final raw = rawAdmin is List ? rawAdmin : rawAll;
//     return (raw as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
//   }
//
//   bool hasPermission(String moduleName) {
//     return _permissions.any((p) {
//       final name = p['module_name']?.toString().trim().toUpperCase() ?? '';
//       final canAccess = p['can_access'] == true || p['can_access'] == 1 || p['can_access'].toString() == '1';
//       return name == moduleName.trim().toUpperCase() && canAccess;
//     });
//   }
//
//   bool get canView => hasPermission('ACTIVITY_LOG_VIEW');
//
//   @override
//   void initState() {
//     super.initState();
//     _load();
//   }
//
//   @override
//   void dispose() {
//     _searchCtrl.dispose();
//     super.dispose();
//   }
//
//   Future<void> _load() async {
//     if (!canView) {
//       setState(() {
//         _loading = false;
//         _error = 'You do not have permission to view audit logs.';
//       });
//       return;
//     }
//
//     setState(() {
//       _loading = true;
//       _error = null;
//     });
//
//     final result = await DBService.instance.fetchAuditLogs(
//       search: _search,
//       module: _module == 'ALL' ? '' : _module,
//       action: _action == 'ALL' ? '' : _action,
//       dateFrom: _dateFrom != null ? _dateOnly(_dateFrom!) : '',
//       dateTo: _dateTo != null ? _dateOnly(_dateTo!) : '',
//       page: _page,
//       limit: _limit,
//     );
//
//     if (!mounted) return;
//
//     setState(() {
//       _loading = false;
//       if (result.success) {
//         final data = result.data ?? {};
//         _logs = (data['logs'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
//         _availableActions = (data['available_actions'] as List?)?.map((e) => e.toString()).toList() ?? [];
//         _availableModules = (data['available_modules'] as List?)?.map((e) => e.toString()).toList() ?? [];
//         final pagination = Map<String, dynamic>.from(data['pagination'] as Map? ?? {});
//         _total = _toInt(pagination['total']);
//         _totalPages = _toInt(pagination['total_pages']) <= 0 ? 1 : _toInt(pagination['total_pages']);
//       } else {
//         _error = result.message;
//       }
//     });
//   }
//
//   void _onSearchChanged(String v) {
//     _search = v;
//     _page = 1;
//     _debounceLoad();
//   }
//
//   // Simple manual debounce without extra deps
//   DateTime? _lastKeyAt;
//   Future<void> _debounceLoad() async {
//     final mark = DateTime.now();
//     _lastKeyAt = mark;
//     await Future.delayed(const Duration(milliseconds: 400));
//     if (_lastKeyAt == mark) _load();
//   }
//
//   Future<void> _pickDate(bool from) async {
//     final picked = await showDatePicker(
//       context: context,
//       initialDate: (from ? _dateFrom : _dateTo) ?? DateTime.now(),
//       firstDate: DateTime(2020),
//       lastDate: DateTime(2100),
//     );
//     if (picked == null) return;
//     setState(() {
//       if (from) {
//         _dateFrom = picked;
//         if (_dateTo != null && _dateTo!.isBefore(_dateFrom!)) _dateTo = _dateFrom;
//       } else {
//         _dateTo = picked;
//       }
//       _page = 1;
//     });
//     _load();
//   }
//
//   void _resetFilters() {
//     _searchCtrl.clear();
//     setState(() {
//       _search = '';
//       _action = 'ALL';
//       _module = 'ALL';
//       _dateFrom = null;
//       _dateTo = null;
//       _page = 1;
//     });
//     _load();
//   }
//
//   void _goToPage(int page) {
//     final safe = page.clamp(1, _totalPages);
//     if (safe == _page) return;
//     setState(() => _page = safe);
//     _load();
//   }
//
//   List<dynamic> _visiblePageItems() {
//     final total = _totalPages;
//     final current = _page;
//     if (total <= 7) return List<int>.generate(total, (i) => i + 1);
//     final items = <dynamic>[1];
//     if (current > 3) items.add('...');
//     final start = current <= 3 ? 2 : current - 1;
//     final end = current >= total - 2 ? total - 1 : current + 1;
//     for (int i = start; i <= end; i++) { if (i > 1 && i < total) items.add(i); }
//     if (current < total - 2) items.add('...');
//     items.add(total);
//     return items;
//   }
//
//   // ── UI ──────────────────────────────────────────────────────────────────
//   @override
//   Widget build(BuildContext context) {
//     if (_loading) return Center(child: CircularProgressIndicator(color: _blue));
//     if (_error != null) return _ErrorView(message: _error!, onRetry: _load);
//
//     return Scaffold(
//       backgroundColor: _bg,
//       body: Column(
//         children: [
//           _header(),
//           Expanded(child: _content()),
//         ],
//       ),
//     );
//   }
//
//   Widget _header() {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
//       child: Row(
//         children: [
//           Expanded(
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 Text('Audit Log',
//                     style: TextStyle(color: _textHi, fontSize: 24, fontWeight: FontWeight.w700)),
//                 const SizedBox(height: 2),
//                 Text(
//                   'Read-only audit trail of every action taken across the system.',
//                   style: TextStyle(color: _textLo, fontSize: 12),
//                 ),
//               ],
//             ),
//           ),
//           IconButton(
//             tooltip: 'Refresh',
//             icon: Icon(Icons.refresh_rounded, color: _textLo),
//             onPressed: _load,
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _content() {
//     return RefreshIndicator(
//       color: _blue,
//       backgroundColor: _surface,
//       onRefresh: _load,
//       child: CustomScrollView(
//         physics: const AlwaysScrollableScrollPhysics(),
//         slivers: [
//           SliverToBoxAdapter(child: _filters()),
//           SliverToBoxAdapter(child: _stats()),
//           const SliverToBoxAdapter(child: SizedBox(height: 8)),
//           _isWindows ? _buildTable() : _buildCards(),
//           SliverToBoxAdapter(child: _pagination()),
//           const SliverToBoxAdapter(child: SizedBox(height: 32)),
//         ],
//       ),
//     );
//   }
//
//   Widget _filters() {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           TextField(
//             controller: _searchCtrl,
//             style: TextStyle(color: _textHi, fontSize: 14),
//             decoration: InputDecoration(
//               hintText: 'Search user, description, or entity…',
//               hintStyle: TextStyle(color: _textLo, fontSize: 13),
//               prefixIcon: Icon(Icons.search_rounded, color: _textLo, size: 20),
//               filled: true,
//               fillColor: _surface,
//               border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
//               enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
//               focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _blue, width: 1.5)),
//               contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
//             ),
//             onChanged: _onSearchChanged,
//           ),
//           const SizedBox(height: 10),
//           Wrap(
//             spacing: 10,
//             runSpacing: 10,
//             crossAxisAlignment: WrapCrossAlignment.center,
//             children: [
//               // ── Module filter (NEW) ──────────────────────────────────────
//               SizedBox(
//                 width: 220,
//                 child: DropdownButtonFormField<String>(
//                   value: ['ALL', ..._availableModules].contains(_module) ? _module : 'ALL',
//                   isExpanded: true,
//                   dropdownColor: _surface,
//                   style: TextStyle(color: _textHi, fontSize: 13),
//                   decoration: InputDecoration(
//                     labelText: 'Module',
//                     labelStyle: TextStyle(color: _textLo, fontSize: 12),
//                     prefixIcon: Icon(Icons.dashboard_customize_rounded, color: _textLo, size: 18),
//                     filled: true,
//                     fillColor: _surface,
//                     enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
//                     focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _blue, width: 1.5)),
//                     contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
//                   ),
//                   items: [
//                     const DropdownMenuItem(value: 'ALL', child: Text('All Modules')),
//                     ..._availableModules.map((m) => DropdownMenuItem(
//                       value: m,
//                       child: Text(m, overflow: TextOverflow.ellipsis),
//                     )),
//                   ],
//                   onChanged: (v) {
//                     setState(() { _module = v ?? 'ALL'; _page = 1; });
//                     _load();
//                   },
//                 ),
//               ),
//               SizedBox(
//                 width: 220,
//                 child: DropdownButtonFormField<String>(
//                   value: ['ALL', ..._availableActions].contains(_action) ? _action : 'ALL',
//                   isExpanded: true,
//                   dropdownColor: _surface,
//                   style: TextStyle(color: _textHi, fontSize: 13),
//                   decoration: InputDecoration(
//                     labelText: 'Action',
//                     labelStyle: TextStyle(color: _textLo, fontSize: 12),
//                     prefixIcon: Icon(Icons.bolt_rounded, color: _textLo, size: 18),
//                     filled: true,
//                     fillColor: _surface,
//                     enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
//                     focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _blue, width: 1.5)),
//                     contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
//                   ),
//                   items: [
//                     const DropdownMenuItem(value: 'ALL', child: Text('All Actions')),
//                     ..._availableActions.map((a) => DropdownMenuItem(
//                       value: a,
//                       child: Text(a, overflow: TextOverflow.ellipsis),
//                     )),
//                   ],
//                   onChanged: (v) {
//                     setState(() { _action = v ?? 'ALL'; _page = 1; });
//                     _load();
//                   },
//                 ),
//               ),
//               SizedBox(width: 170, child: _dateBox('Date From', _dateFrom, () => _pickDate(true))),
//               SizedBox(width: 170, child: _dateBox('Date To', _dateTo, () => _pickDate(false))),
//               OutlinedButton.icon(
//                 style: OutlinedButton.styleFrom(
//                   side: BorderSide(color: _border),
//                   shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//                   padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
//                 ),
//                 onPressed: _resetFilters,
//                 icon: Icon(Icons.restart_alt_rounded, size: 18, color: _textLo),
//                 label: Text('Reset', style: TextStyle(color: _textLo)),
//               ),
//             ],
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _dateBox(String label, DateTime? date, VoidCallback onTap) {
//     return InkWell(
//       onTap: onTap,
//       borderRadius: BorderRadius.circular(12),
//       child: InputDecorator(
//         decoration: InputDecoration(
//           labelText: label,
//           labelStyle: TextStyle(color: _textLo),
//           prefixIcon: Icon(Icons.calendar_today_rounded, color: _textLo, size: 18),
//           filled: true,
//           fillColor: _surface,
//           enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _border)),
//           focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: _blue)),
//           contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
//         ),
//         child: Text(
//           date != null ? _dateOnly(date) : 'Any',
//           style: TextStyle(color: date != null ? _textHi : _textLo),
//         ),
//       ),
//     );
//   }
//
//   Widget _stats() {
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
//       child: Wrap(
//         spacing: 8,
//         runSpacing: 8,
//         children: [
//           _MiniStat(label: 'Total Logs', value: '$_total', color: _blue),
//           _MiniStat(label: 'Showing', value: '${_logs.length}', color: _teal),
//           _MiniStat(label: 'Page', value: '$_page / $_totalPages', color: _green),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildTable() {
//     return SliverToBoxAdapter(
//       child: Padding(
//         padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
//         child: Container(
//           decoration: BoxDecoration(
//             color: _surface,
//             borderRadius: BorderRadius.circular(14),
//             border: Border.all(color: _border),
//           ),
//           child: Column(
//             children: [
//               Padding(
//                 padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
//                 child: Row(children: const [
//                   SizedBox(width: 150, child: _TH('TIMESTAMP')),
//                   Expanded(flex: 2, child: _TH('USER')),
//                   Expanded(flex: 3, child: _TH('MODULE')),
//                   SizedBox(width: 120, child: _TH('ACTION')),
//                   Expanded(flex: 5, child: _TH('DESCRIPTION')),
//                   SizedBox(width: 110, child: _TH('IP ADDRESS')),
//                 ]),
//               ),
//               Divider(height: 1, color: _border),
//               if (_logs.isEmpty)
//                 Padding(padding: const EdgeInsets.all(32), child: Text('No activity found', style: TextStyle(color: _textLo)))
//               else
//                 ..._logs.asMap().entries.map((e) {
//                   final idx = e.key;
//                   final log = e.value;
//                   return Column(children: [
//                     if (idx > 0) Divider(height: 1, color: _border),
//                     _LogTableRow(log: log),
//                   ]);
//                 }),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   Widget _buildCards() {
//     if (_logs.isEmpty) {
//       return SliverFillRemaining(
//         child: Center(child: Text('No activity found', style: TextStyle(color: _textLo))),
//       );
//     }
//     return SliverList(
//       delegate: SliverChildBuilderDelegate(
//             (context, index) => Padding(
//           padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
//           child: _LogCard(log: _logs[index]),
//         ),
//         childCount: _logs.length,
//       ),
//     );
//   }
//
//   Widget _pagination() {
//     if (_logs.isEmpty) return const SizedBox.shrink();
//     final items = _visiblePageItems();
//     return Padding(
//       padding: const EdgeInsets.fromLTRB(24, 18, 24, 0),
//       child: Wrap(
//         alignment: WrapAlignment.end,
//         crossAxisAlignment: WrapCrossAlignment.center,
//         spacing: 12,
//         runSpacing: 10,
//         children: [
//           Text('Total: $_total', style: TextStyle(color: _textHi, fontSize: 14)),
//           Container(
//             padding: const EdgeInsets.symmetric(horizontal: 10),
//             decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
//             child: DropdownButton<int>(
//               value: _limit,
//               underline: const SizedBox(),
//               dropdownColor: _surface,
//               icon: Icon(Icons.keyboard_arrow_down_rounded, color: _textLo),
//               style: TextStyle(color: _textHi, fontSize: 14),
//               items: _pageSizeOptions.map((size) => DropdownMenuItem<int>(value: size, child: Text('$size'))).toList(),
//               onChanged: (value) {
//                 if (value == null) return;
//                 setState(() { _limit = value; _page = 1; });
//                 _load();
//               },
//             ),
//           ),
//           Row(mainAxisSize: MainAxisSize.min, children: [
//             _PageNavButton(label: '<', enabled: _page > 1, onTap: () => _goToPage(_page - 1)),
//             const SizedBox(width: 6),
//             ...items.map((item) {
//               if (item == '...') {
//                 return Padding(
//                   padding: const EdgeInsets.symmetric(horizontal: 4),
//                   child: Text('...', style: TextStyle(color: _textLo, fontSize: 14)),
//                 );
//               }
//               final page = item as int;
//               return Padding(
//                 padding: const EdgeInsets.only(right: 6),
//                 child: _PageTab(label: '$page', active: page == _page, onTap: () => _goToPage(page)),
//               );
//             }),
//             _PageNavButton(label: '>', enabled: _page < _totalPages, onTap: () => _goToPage(_page + 1)),
//           ]),
//         ],
//       ),
//     );
//   }
// }
//
// // ─────────────────────────────────────────────────────────────────────────
// //  Row / Card widgets
// // ─────────────────────────────────────────────────────────────────────────
//
// class _LogTableRow extends StatelessWidget {
//   final Map<String, dynamic> log;
//   const _LogTableRow({required this.log});
//
//   bool get _hasDiff => log['before'] != null || log['after'] != null;
//
//   @override
//   Widget build(BuildContext context) {
//     final action = _toStr(log['action']);
//     final style = _actionStyle(action);
//     final userName = _toStr(log['user_name']).isNotEmpty ? _toStr(log['user_name']) : _toStr(log['user_username']);
//
//     return Theme(
//       data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
//       child: ExpansionTile(
//         tilePadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
//         childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
//         maintainState: false,
//         title: Row(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             SizedBox(
//               width: 150,
//               child: Text(_toStr(log['created_at']), style: TextStyle(color: _textLo, fontSize: 12)),
//             ),
//             Expanded(
//               flex: 2,
//               child: Text(userName.isEmpty ? 'System' : userName,
//                   style: TextStyle(color: _textHi, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
//             ),
//             Expanded(
//               flex: 3,
//               child: Text(_moduleLabel(log), style: TextStyle(color: _textLo, fontSize: 12), overflow: TextOverflow.ellipsis),
//             ),
//             SizedBox(
//               width: 120,
//               child: _ActionChip(action: action, color: style.color, icon: style.icon),
//             ),
//             Expanded(
//               flex: 5,
//               child: Text(_toStr(log['description']), style: TextStyle(color: _textHi, fontSize: 12), softWrap: true),
//             ),
//             SizedBox(
//               width: 110,
//               child: Text(_toStr(log['ip_address']).isEmpty ? '—' : _toStr(log['ip_address']),
//                   style: TextStyle(color: _textLo, fontSize: 11, fontFamily: 'monospace')),
//             ),
//           ],
//         ),
//         trailing: _hasDiff
//             ? Icon(Icons.expand_more_rounded, color: _textLo, size: 20)
//             : const SizedBox(width: 1),
//         children: _hasDiff ? [_DiffView(log: log)] : const [],
//       ),
//     );
//   }
// }
//
// class _LogCard extends StatelessWidget {
//   final Map<String, dynamic> log;
//   const _LogCard({required this.log});
//
//   bool get _hasDiff => log['before'] != null || log['after'] != null;
//
//   @override
//   Widget build(BuildContext context) {
//     final action = _toStr(log['action']);
//     final style = _actionStyle(action);
//     final userName = _toStr(log['user_name']).isNotEmpty ? _toStr(log['user_name']) : _toStr(log['user_username']);
//
//     return Container(
//       margin: const EdgeInsets.only(bottom: 10),
//       padding: const EdgeInsets.all(14),
//       decoration: BoxDecoration(
//         color: _surface,
//         borderRadius: BorderRadius.circular(14),
//         border: Border.all(color: _border),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               _ActionChip(action: action, color: style.color, icon: style.icon),
//               const Spacer(),
//               Text(_toStr(log['created_at']), style: TextStyle(color: _textLo, fontSize: 11)),
//             ],
//           ),
//           const SizedBox(height: 8),
//           Text(userName.isEmpty ? 'System' : userName,
//               style: TextStyle(color: _textHi, fontSize: 14, fontWeight: FontWeight.w700)),
//           const SizedBox(height: 4),
//           Text(_toStr(log['description']), style: TextStyle(color: _textHi, fontSize: 13)),
//           const SizedBox(height: 8),
//           Row(
//             children: [
//               Icon(Icons.dashboard_customize_rounded, size: 13, color: _textLo),
//               const SizedBox(width: 4),
//               Flexible(
//                 child: Text(_moduleLabel(log), style: TextStyle(color: _textLo, fontSize: 11), overflow: TextOverflow.ellipsis),
//               ),
//               const SizedBox(width: 14),
//               Icon(Icons.lan_rounded, size: 13, color: _textLo),
//               const SizedBox(width: 4),
//               Text(_toStr(log['ip_address']).isEmpty ? '—' : _toStr(log['ip_address']),
//                   style: TextStyle(color: _textLo, fontSize: 11, fontFamily: 'monospace')),
//             ],
//           ),
//           if (_hasDiff) ...[
//             const SizedBox(height: 10),
//             _DiffView(log: log),
//           ],
//         ],
//       ),
//     );
//   }
// }
//
// /// Renders a before → after comparison from the log's `before` / `after` maps.
// class _DiffView extends StatelessWidget {
//   final Map<String, dynamic> log;
//   const _DiffView({required this.log});
//
//   Map<String, dynamic> _asMap(dynamic v) {
//     if (v is Map) return Map<String, dynamic>.from(v);
//     return {};
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final before = _asMap(log['before']);
//     final after = _asMap(log['after']);
//
//     // Union of keys across before + after, so added/removed fields still show.
//     final keys = <String>{...before.keys, ...after.keys}.toList()..sort();
//     if (keys.isEmpty) return const SizedBox.shrink();
//
//     return Container(
//       width: double.infinity,
//       margin: const EdgeInsets.only(top: 6),
//       padding: const EdgeInsets.all(12),
//       decoration: BoxDecoration(
//         color: _bg,
//         borderRadius: BorderRadius.circular(10),
//         border: Border.all(color: _border),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text('CHANGES',
//               style: TextStyle(color: _textLo, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
//           const SizedBox(height: 8),
//           ...keys.map((k) {
//             final b = before.containsKey(k) ? _toStr(before[k]) : '';
//             final a = after.containsKey(k) ? _toStr(after[k]) : '';
//             final changed = b != a;
//             return Padding(
//               padding: const EdgeInsets.only(bottom: 6),
//               child: Row(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   SizedBox(
//                     width: 130,
//                     child: Text(k, style: TextStyle(color: _textLo, fontSize: 11, fontWeight: FontWeight.w600)),
//                   ),
//                   Expanded(
//                     child: Wrap(
//                       crossAxisAlignment: WrapCrossAlignment.center,
//                       children: [
//                         if (b.isNotEmpty)
//                           Text(b, style: TextStyle(
//                             color: changed ? _red : _textLo,
//                             fontSize: 11,
//                             decoration: changed ? TextDecoration.lineThrough : null,
//                           )),
//                         if (changed) ...[
//                           Padding(
//                             padding: const EdgeInsets.symmetric(horizontal: 6),
//                             child: Icon(Icons.arrow_forward_rounded, size: 12, color: _textLo),
//                           ),
//                           Text(a.isEmpty ? '(empty)' : a, style: TextStyle(color: _green, fontSize: 11, fontWeight: FontWeight.w600)),
//                         ] else if (b.isEmpty)
//                           Text(a.isEmpty ? '—' : a, style: TextStyle(color: _textHi, fontSize: 11)),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             );
//           }),
//         ],
//       ),
//     );
//   }
// }
//
// class _ActionChip extends StatelessWidget {
//   final String action;
//   final Color color;
//   final IconData icon;
//   const _ActionChip({required this.action, required this.color, required this.icon});
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//       decoration: BoxDecoration(
//         color: color.withOpacity(0.12),
//         borderRadius: BorderRadius.circular(8),
//         border: Border.all(color: color.withOpacity(0.35)),
//       ),
//       child: Row(mainAxisSize: MainAxisSize.min, children: [
//         Icon(icon, size: 12, color: color),
//         const SizedBox(width: 4),
//         Flexible(
//           child: Text(action, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
//         ),
//       ]),
//     );
//   }
// }
//
// class _MiniStat extends StatelessWidget {
//   final String label, value;
//   final Color color;
//   const _MiniStat({required this.label, required this.value, required this.color});
//
//   @override
//   Widget build(BuildContext context) {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
//       decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: _border)),
//       child: Row(mainAxisSize: MainAxisSize.min, children: [
//         Text(value, style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
//         const SizedBox(width: 6),
//         Text(label, style: TextStyle(color: _textLo, fontSize: 12)),
//       ]),
//     );
//   }
// }
//
// class _PageNavButton extends StatelessWidget {
//   final String label; final bool enabled; final VoidCallback onTap;
//   const _PageNavButton({required this.label, required this.enabled, required this.onTap});
//
//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       borderRadius: BorderRadius.circular(20),
//       onTap: enabled ? onTap : null,
//       child: Container(
//         width: 36, height: 36,
//         decoration: BoxDecoration(color: enabled ? _surface : _surface.withOpacity(0.5), shape: BoxShape.circle, border: Border.all(color: _border)),
//         child: Center(child: Text(label, style: TextStyle(color: enabled ? _textHi : _textLo, fontWeight: FontWeight.w600))),
//       ),
//     );
//   }
// }
//
// class _PageTab extends StatelessWidget {
//   final String label; final bool active; final VoidCallback onTap;
//   const _PageTab({required this.label, required this.active, required this.onTap});
//
//   @override
//   Widget build(BuildContext context) {
//     return InkWell(
//       borderRadius: BorderRadius.circular(20),
//       onTap: onTap,
//       child: Container(
//         width: 36, height: 36,
//         decoration: BoxDecoration(color: active ? _blue : _surface, shape: BoxShape.circle, border: Border.all(color: active ? _blue : _border)),
//         child: Center(child: Text(label, style: TextStyle(color: active ? Colors.white : _textHi, fontWeight: FontWeight.w600, fontSize: 13))),
//       ),
//     );
//   }
// }
//
// class _TH extends StatelessWidget {
//   final String text;
//   const _TH(this.text);
//
//   @override
//   Widget build(BuildContext context) {
//     return Text(text, style: TextStyle(color: _textLo, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5));
//   }
// }
//
// class _ErrorView extends StatelessWidget {
//   final String message; final VoidCallback onRetry;
//   const _ErrorView({required this.message, required this.onRetry});
//
//   @override
//   Widget build(BuildContext context) {
//     return Center(
//       child: Padding(
//         padding: const EdgeInsets.all(32),
//         child: Column(mainAxisSize: MainAxisSize.min, children: [
//           Icon(Icons.cloud_off_rounded, color: _textLo, size: 48),
//           const SizedBox(height: 16),
//           Text(message, style: TextStyle(color: _textLo, fontSize: 13), textAlign: TextAlign.center),
//           const SizedBox(height: 20),
//           ElevatedButton.icon(
//             style: ElevatedButton.styleFrom(backgroundColor: _blue),
//             onPressed: onRetry,
//             icon: const Icon(Icons.refresh_rounded, size: 16),
//             label: const Text('Retry'),
//           ),
//         ]),
//       ),
//     );
//   }
// }