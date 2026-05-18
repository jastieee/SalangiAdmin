import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:salangi_ko_pu/Screens/deliveries_screen.dart';
import '../db/DBResult.dart';
import 'user_management_screen.dart';
import 'product_management_screen.dart';
import 'inventory_screen.dart';
import 'reports_screen.dart';
import '../Utils/app_theme.dart';
import '../login_screen.dart';
import 'supplier_management_screen.dart';
import 'location_management_screen.dart';
import 'promo_management_screen.dart';

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

bool _sidebarOpen = false;

const _allDestinations = [
  (icon: Icons.dashboard_rounded, label: 'Dashboard', permission: ''),
  (icon: Icons.inventory_2_rounded, label: 'Products', permission: 'PRODUCT_VIEW'),
  (icon: Icons.business_rounded, label: 'Suppliers', permission: 'SUPPLIER_VIEW'),
  (icon: Icons.inventory_2_sharp, label: 'Inventory', permission: 'INVENTORY_VIEW'),
  (icon: Icons.receipt_long_rounded, label: 'Deliveries', permission: 'DELIVERY_VIEW'),
  (icon: Icons.report_outlined, label: 'Reports', permission: 'REPORT_VIEW'),
  (icon: Icons.local_offer_rounded, label: 'Promos', permission: 'PROMOS'),
  (
  icon: Icons.store_mall_directory_rounded,
  label: 'Locations',
  permission: 'LOCATION_VIEW'
  ),
  (icon: Icons.people_rounded, label: 'Users', permission: 'USER_VIEW'),
];

class DashboardScreen extends StatefulWidget {
  final Map<String, dynamic>? user;
  const DashboardScreen({super.key, this.user});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;

  bool get _isWindows {
    try {
      return !kIsWeb && Platform.isWindows;
    } catch (_) {
      return false;
    }
  }

  String get _initials {
    final name = widget.user?['full_name'] as String? ?? 'User';
    final parts = name.trim().split(' ');
    return (parts.length >= 2)
        ? '${parts[0][0]}${parts[1][0]}'.toUpperCase()
        : name.isNotEmpty
        ? name[0].toUpperCase()
        : 'U';
  }

  bool _hasAdminPermission(String permissionName) {
    if (permissionName.isEmpty) return true;

    final modules = List<Map<String, dynamic>>.from(
      widget.user?['admin_modules'] ?? [],
    );

    return modules.any((m) {
      final name = m['module_name']?.toString() ?? '';
      final canAccess =
          m['can_access'] == true ||
              m['can_access'] == 1 ||
              m['can_access'].toString() == '1';

      return name == permissionName && canAccess;
    });
  }

  List<dynamic> get _visibleDestinations {
    return _allDestinations.where((d) => _hasAdminPermission(d.permission))
        .toList();
  }

  Widget _screen() {
    final destinations = _visibleDestinations;

    if (destinations.isEmpty) return _DashboardTab(user: widget.user);
    if (_selectedIndex >= destinations.length) _selectedIndex = 0;

    final label = destinations[_selectedIndex].label;

    switch (label) {
      case 'Products':
        return ProductManagementScreen(currentUser: widget.user);
      case 'Suppliers':
        return SupplierManagementScreen(currentUser: widget.user);
      case 'Inventory':
        return InventoryScreen(currentUser: widget.user);
      case 'Deliveries':
        return DeliveriesScreen(currentUser: widget.user);
      case 'Locations':
        return LocationManagementScreen(currentUser: widget.user);
      case 'Reports':
        return ReportsScreen(currentUser: widget.user);
      case 'Promos':
        return PromoManagementScreen(currentUser: widget.user);
      case 'Users':
        return UserManagementScreen(currentUser: widget.user);
      default:
        return _DashboardTab(user: widget.user);
    }


  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) =>
          AlertDialog(
            backgroundColor: _surface,
            title: Text('Logout', style: TextStyle(color: _textHi)),
            content: Text('Are you sure you want to logout?',
                style: TextStyle(color: _textLo)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text('Cancel', style: TextStyle(color: _textLo)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Logout'),
              ),
            ],
          ),
    );

    if (ok != true || !mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
    );
  }

  void _showChangePassword() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Change password screen/API will be added next.'),
        backgroundColor: _blue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showUserMenu() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) =>
          SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(Icons.lock_reset_rounded, color: _blue),
                  title: Text(
                      'Change Password', style: TextStyle(color: _textHi)),
                  onTap: () {
                    Navigator.pop(context);
                    _showChangePassword();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.logout_rounded, color: _red),
                  title: Text('Logout', style: TextStyle(color: _red)),
                  onTap: () {
                    Navigator.pop(context);
                    _logout();
                  },
                ),
              ],
            ),
          ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      _isWindows ? _windowsLayout() : _androidLayout();

  Widget _windowsLayout() {
    final destinations = _visibleDestinations;

    return Scaffold(
      backgroundColor: _bg,
      body: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: _sidebarOpen ? 220 : 60,
            color: _surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 32, 10, 24),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _sidebarOpen ? Icons.menu_open_rounded : Icons
                              .menu_rounded,
                          color: _textHi,
                        ),
                        onPressed: () =>
                            setState(() => _sidebarOpen = !_sidebarOpen),
                      ),
                      if (_sidebarOpen) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Salangi Ko Pu",
                            style: TextStyle(
                              color: _textHi,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ...List.generate(destinations.length, (i) {
                  final d = destinations[i];
                  return _SidebarItem(
                    icon: d.icon,
                    label: d.label,
                    selected: _selectedIndex == i,
                    showLabel: _sidebarOpen,
                    onTap: () => setState(() => _selectedIndex = i),
                  );
                }),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: themeNotifier,
                    builder: (_, isDark, __) =>
                        GestureDetector(
                          onTap: () => setState(() => themeNotifier.toggle()),
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                                horizontal: 0, vertical: 2),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 11),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  isDark ? Icons.light_mode_rounded : Icons
                                      .dark_mode_rounded,
                                  color: _textLo,
                                  size: 20,
                                ),
                                if (_sidebarOpen) ...[
                                  const SizedBox(width: 12),
                                  Text(
                                    isDark ? 'Light Mode' : 'Dark Mode',
                                    style: TextStyle(
                                        color: _textLo, fontSize: 14),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                  ),
                ),
                if (_sidebarOpen)
                  _userTile()
                else
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16, left: 10),
                    child: CircleAvatar(
                      backgroundColor: _blue.withOpacity(0.15),
                      radius: 18,
                      child: Text(
                        _initials,
                        style: TextStyle(
                          color: _blue,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Expanded(child: _screen()),
        ],
      ),
    );
  }

  Widget _androidLayout() {
    final destinations = _visibleDestinations;
    // Show max 4 primary items + "More" tab on mobile
    const maxPrimary = 4;
    final primaryDests = destinations.length <= maxPrimary
        ? destinations
        : destinations.sublist(0, maxPrimary);
    final overflowDests = destinations.length > maxPrimary
        ? destinations.sublist(maxPrimary)
        : <dynamic>[];

    // Check if selected index is in overflow
    final effectiveNavIndex = _selectedIndex < maxPrimary
        ? _selectedIndex
        : maxPrimary; // "More" tab index

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Row(
          children: [
            Icon(Icons.storefront_rounded, color: _blue, size: 22),
            const SizedBox(width: 10),
            Text(
              "Salangi ko Pu",
              style: TextStyle(
                  color: _textHi, fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: _showUserMenu,
              child: CircleAvatar(
                backgroundColor: _blue.withOpacity(0.15),
                radius: 18,
                child: Text(
                  _initials,
                  style: TextStyle(
                      color: _blue, fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ),
        ],
      ),
      body: _screen(),
      bottomNavigationBar: destinations.length <= 1
          ? null
          : NavigationBar(
        backgroundColor: _surface,
        indicatorColor: _blue.withOpacity(0.2),
        selectedIndex: effectiveNavIndex,
        onDestinationSelected: (i) {
          if (overflowDests.isNotEmpty && i == maxPrimary) {
            // Show "More" bottom sheet
            showModalBottomSheet(
              context: context,
              backgroundColor: _surface,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
              ),
              builder: (_) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Text(
                        'More',
                        style: TextStyle(
                          color: _textHi,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    ...overflowDests.asMap().entries.map((entry) {
                      final realIndex = maxPrimary + entry.key;
                      final d = entry.value;
                      final isSelected = _selectedIndex == realIndex;
                      return ListTile(
                        leading: Icon(
                          d.icon,
                          color: isSelected ? _blue : _textLo,
                        ),
                        title: Text(
                          d.label,
                          style: TextStyle(
                            color: isSelected ? _blue : _textHi,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check_rounded, color: _blue, size: 18)
                            : null,
                        onTap: () {
                          setState(() => _selectedIndex = realIndex);
                          Navigator.pop(context);
                        },
                      );
                    }),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          } else {
            setState(() => _selectedIndex = i);
          }
        },
        destinations: [
          ...primaryDests.map(
                (d) => NavigationDestination(
              icon: Icon(d.icon, color: _textLo),
              selectedIcon: Icon(d.icon, color: _blue),
              label: d.label,
            ),
          ),
          if (overflowDests.isNotEmpty)
            NavigationDestination(
              icon: Icon(
                Icons.more_horiz_rounded,
                color: _selectedIndex >= maxPrimary ? _blue : _textLo,
              ),
              selectedIcon:
              Icon(Icons.more_horiz_rounded, color: _blue),
              label: 'More',
            ),
        ],
      ),
    );
  }
  Widget _userTile() {
    final name = widget.user?['full_name'] as String? ?? 'User';
    final email = widget.user?['email'] as String? ?? '';

    return InkWell(
      onTap: _showUserMenu,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _showUserMenu,
              child: CircleAvatar(
                backgroundColor: _blue.withOpacity(0.15),
                radius: 18,
                child: Text(
                  _initials,
                  style: TextStyle(
                    color: _blue,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: TextStyle(
                      color: _textHi,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (email.isNotEmpty)
                    Text(
                      email,
                      style: TextStyle(color: _textLo, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            Icon(Icons.more_vert_rounded, color: _textLo, size: 18),
          ],
        ),
      ),
    );
  }
}

class _DashboardTab extends StatefulWidget {
  final Map<String, dynamic>? user;
  const _DashboardTab({this.user});

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await DBService.instance.fetchDashboard();

    if (mounted) {
      setState(() {
        _loading = false;
        if (result.success) {
          _data = result.data ?? {};
        } else {
          _error = result.message;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator(color: _blue));
    if (_error != null) return _ErrorView(message: _error!, onRetry: _load);

    List<Map<String, dynamic>> asList(String key) =>
        (_data[key] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];

    final summary = Map<String, dynamic>.from(_data['summary'] as Map? ?? {});
    final weeklySales = asList('weekly_sales').take(7).toList();
    final salesByProduct = asList('sales_by_product').take(5).toList();
    final recentTrx = asList('recent_transactions').take(5).toList();
    final storeLowStock = asList('store_low_stock').take(5).toList();
    final warehouseLowStock = asList('warehouse_low_stock').take(5).toList();

    return RefreshIndicator(
      color: _blue,
      backgroundColor: _surface,
      onRefresh: _load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dashboard',
                      style: TextStyle(color: _textHi, fontSize: 24, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text('Pull to refresh', style: TextStyle(color: _textLo, fontSize: 12)),
                  ],
                ),
                IconButton(icon: Icon(Icons.refresh_rounded, color: _textLo), onPressed: _load),
              ],
            ),
            const SizedBox(height: 20),
            _SummaryCards(summary: summary),
            const SizedBox(height: 20),
            _buildChartsRow(context, weeklySales, salesByProduct),
            const SizedBox(height: 20),
            _buildBottomRow(context, recentTrx, storeLowStock, warehouseLowStock),
          ],
        ),
      ),
    );
  }

  Widget _buildChartsRow(
      BuildContext ctx,
      List<Map<String, dynamic>> weekly,
      List<Map<String, dynamic>> byProduct,
      ) {
    final isWide = MediaQuery.of(ctx).size.width > 700;

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _SalesChart(weeklyData: weekly)),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: _ProductPieChart(data: byProduct)),
        ],
      );
    }

    return Column(
      children: [
        _SalesChart(weeklyData: weekly),
        const SizedBox(height: 16),
        _ProductPieChart(data: byProduct),
      ],
    );
  }

  Widget _buildBottomRow(
      BuildContext ctx,
      List<Map<String, dynamic>> trx,
      List<Map<String, dynamic>> storeLow,
      List<Map<String, dynamic>> warehouseLow,
      ) {
    final isWide = MediaQuery.of(ctx).size.width > 700;

    if (isWide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 3, child: _RecentOrders(data: trx)),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Column(
              children: [
                _LowStockAlerts(title: 'Store Low Stock', data: storeLow),
                const SizedBox(height: 16),
                _LowStockAlerts(title: 'Warehouse Low Stock', data: warehouseLow),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        _RecentOrders(data: trx),
        const SizedBox(height: 16),
        _LowStockAlerts(title: 'Store Low Stock', data: storeLow),
        const SizedBox(height: 16),
        _LowStockAlerts(title: 'Warehouse Low Stock', data: warehouseLow),
      ],
    );
  }
}

class _SummaryCards extends StatelessWidget {
  final Map<String, dynamic> summary;
  const _SummaryCards({required this.summary});

  @override
  Widget build(BuildContext context) {
    final todaySales = _toDouble(summary['today_sales']);
    final todayOrders = _toInt(summary['today_orders']);
    final storeStock = _toInt(summary['store_stock']);
    final warehouseStock = _toInt(summary['warehouse_stock']);
    final storeLow = _toInt(summary['store_low_stock_count']);
    final warehouseLow = _toInt(summary['warehouse_low_stock_count']);
    final totalLow = storeLow + warehouseLow;
    final storeProducts = _toInt(summary['store_products']);

    final stats = [
      (
      label: "Today's Sales",
      value: '₱${todaySales.toStringAsFixed(2)}',
      sub: '$todayOrders transactions',
      color: _green,
      icon: Icons.trending_up_rounded,
      ),
      (
      label: 'Transactions',
      value: '$todayOrders',
      sub: 'Total today',
      color: _blue,
      icon: Icons.receipt_long_rounded,
      ),
      (
      label: 'Store Stock',
      value: '$storeStock units',
      sub: '$storeProducts products',
      color: _amber,
      icon: Icons.storefront_rounded,
      ),
      (
      label: 'Warehouse Stock',
      value: '$warehouseStock units',
      sub: '${_toInt(summary["warehouse_products"])} products',
      color: _amber,
      icon: Icons.inventory_2_rounded,
      ),
      (
      label: 'Low Stock Alerts',
      value: '$totalLow',
      sub: '$storeLow store · $warehouseLow wh.',
      color: _red,
      icon: Icons.warning_amber_rounded,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 900
            ? 5
            : constraints.maxWidth > 600
            ? 3
            : 2;

        return GridView.count(
          crossAxisCount: crossCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 1.6,
          children: stats
              .map(
                (s) => _StatCard(
              label: s.label,
              value: s.value,
              sub: s.sub,
              color: s.color,
              icon: s.icon,
            ),
          )
              .toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value, sub;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: _textLo, fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 16),
            ),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(color: _textHi, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(color: color, fontSize: 11)),
          ],
        ),
      ],
    ),
  );
}

class _SalesChart extends StatelessWidget {
  final List<Map<String, dynamic>> weeklyData;
  const _SalesChart({required this.weeklyData});

  @override
  Widget build(BuildContext context) {
    if (weeklyData.isEmpty) {
      return _Card(
        title: 'Weekly Sales',
        child: SizedBox(
          height: 180,
          child: Center(child: Text('No sales data yet', style: TextStyle(color: _textLo))),
        ),
      );
    }

    final spots = List.generate(
      weeklyData.length,
          (i) => FlSpot(i.toDouble(), _toDouble(weeklyData[i]['total'])),
    );

    final labels = weeklyData.map((d) => (d['day'] as String?) ?? '').toList();
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final sumY = spots.map((s) => s.y).reduce((a, b) => a + b);

    return _Card(
      title: 'Weekly Sales',
      subtitle: 'Last ${weeklyData.length} days  •  ₱${sumY.toStringAsFixed(2)} total',
      child: SizedBox(
        height: 180,
        child: LineChart(
          LineChartData(
            minY: 0,
            maxY: maxY <= 0 ? 1 : maxY * 1.2,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(color: Colors.white10, strokeWidth: 1),
            ),
            titlesData: FlTitlesData(
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= labels.length) return const SizedBox();
                    return Text(labels[i], style: TextStyle(color: _textLo, fontSize: 10));
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineBarsData: [
              LineChartBarData(
                spots: spots,
                isCurved: true,
                color: _blue,
                barWidth: 2.5,
                dotData: FlDotData(
                  show: true,
                  getDotPainter: (_, __, ___, i) => FlDotCirclePainter(
                    radius: i == spots.length - 1 ? 5 : 3,
                    color: i == spots.length - 1 ? _blue : _surface,
                    strokeWidth: 2,
                    strokeColor: _blue,
                  ),
                ),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    colors: [_blue.withOpacity(0.25), _blue.withOpacity(0)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductPieChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _ProductPieChart({required this.data});

  static List<Color> _colors = [_blue, _green, _amber, _red, Color(0xFF9C27B0)];

  String _shortName(String desc) {
    final clean = desc.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length > 18 ? '${clean.substring(0, 16)}…' : clean;
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return _Card(
        title: 'Top Products',
        child: SizedBox(
          height: 180,
          child: Center(child: Text('No data yet', style: TextStyle(color: _textLo))),
        ),
      );
    }

    final total = data.fold<double>(0, (s, d) => s + _toDouble(d['total']));

    return _Card(
      title: 'Top Products',
      subtitle: 'By revenue',
      child: SizedBox(
        height: 180,
        child: Row(
          children: [
            Expanded(
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 34,
                  sections: List.generate(data.length, (i) {
                    final pct = total > 0 ? _toDouble(data[i]['total']) / total * 100 : 0.0;
                    return PieChartSectionData(
                      color: _colors[i % _colors.length],
                      value: pct,
                      radius: 46,
                      title: '${pct.toStringAsFixed(0)}%',
                      titleStyle: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    );
                  }),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(
                data.length,
                    (i) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: _colors[i % _colors.length],
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _shortName((data[i]['item_description'] as String?) ?? ''),
                        style: TextStyle(color: _textLo, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentOrders extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  const _RecentOrders({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return _Card(
        title: 'Recent Transactions',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No transactions yet', style: TextStyle(color: _textLo)),
          ),
        ),
      );
    }

    return _Card(
      title: 'Recent Transactions',
      subtitle: 'Latest ${data.length}',
      child: Column(
        children: data.map((t) {
          final trxNo = (t['transaction_no'] as String?) ?? '-';
          final amount = _toDouble(t['total_amount']).toStringAsFixed(2);
          final customer = (t['customer_code'] as String?) ?? 'WALK-IN';
          final items = _toInt(t['items_count']);
          final dateStr = (t['created_at'] as String?) ?? '';
          final time = dateStr.length >= 19 ? dateStr.substring(11, 16) : '';

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    trxNo,
                    style: TextStyle(color: _blue, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(customer, style: TextStyle(color: _textHi, fontSize: 11)),
                ),
                Expanded(
                  flex: 1,
                  child: Text('$items items', style: TextStyle(color: _textLo, fontSize: 10)),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '₱$amount',
                    style: TextStyle(color: _textHi, fontSize: 12, fontWeight: FontWeight.w700),
                    textAlign: TextAlign.right,
                  ),
                ),
                const SizedBox(width: 8),
                Text(time, style: TextStyle(color: _textLo, fontSize: 10)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _LowStockAlerts extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> data;
  const _LowStockAlerts({required this.title, required this.data});

  String _shortName(String s) {
    final clean = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length > 22 ? '${clean.substring(0, 20)}…' : clean;
  }

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return _Card(
        title: title,
        titleAccentColor: _green,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded, color: _green, size: 18),
              const SizedBox(width: 8),
              Text('All items well stocked!', style: TextStyle(color: _green, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    const threshold = 10;

    return _Card(
      title: title,
      subtitle: '${data.length} item(s) need restocking',
      titleAccentColor: _amber,
      child: Column(
        children: data.map((item) {
          final name = _shortName((item['item_description'] as String?) ?? '');
          final qty = _toInt(item['quantity']);
          final pct = (qty / threshold).clamp(0.0, 1.0);

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(color: _textHi, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      '$qty / $threshold',
                      style: TextStyle(
                        color: qty == 0 ? _red : _amber,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 5,
                    backgroundColor: Colors.white10,
                    color: qty == 0 ? _red : _amber,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? titleAccentColor;
  final Widget child;

  const _Card({
    required this.title,
    this.subtitle,
    this.titleAccentColor,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
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
            if (titleAccentColor != null) ...[
              Icon(Icons.warning_amber_rounded, color: titleAccentColor, size: 16),
              const SizedBox(width: 6),
            ],
            Text(
              title,
              style: TextStyle(
                color: titleAccentColor ?? _textHi,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(subtitle!, style: TextStyle(color: _textLo, fontSize: 12)),
        ],
        const SizedBox(height: 16),
        child,
      ],
    ),
  );
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool showLabel;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      decoration: BoxDecoration(
        color: selected ? _blue.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? _blue.withOpacity(0.3) : Colors.transparent,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: selected ? _blue : _textLo, size: 20),
          if (showLabel) ...[
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selected ? _blue : _textLo,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
          ],
        ],
      ),
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

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
