import 'package:flutter/material.dart';
import '../db/DBResult.dart';
import '../Utils/app_theme.dart';


// ── Role colour by name ─────────────────────────────
Color _roleColor(String roleName) {
  final n = roleName.toLowerCase();
  if (n.contains('super')) return AppColors.red;
  if (n.contains('admin')) return AppColors.red;
  if (n.contains('manager')) return AppColors.amber;
  if (n.contains('cashier')) return AppColors.green;
  return AppColors.blue;
}

IconData _roleIcon(String roleName) {
  final n = roleName.toLowerCase();
  if (n.contains('super')) return Icons.verified_user_rounded;
  if (n.contains('admin')) return Icons.shield_rounded;
  if (n.contains('manager')) return Icons.work_rounded;
  if (n.contains('cashier')) return Icons.point_of_sale_rounded;
  return Icons.person_rounded;
}

String _initials(String name) {
  final parts = name.trim().split(' ');
  if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  return name.isNotEmpty ? name[0].toUpperCase() : 'U';
}

// ────────────────────────────────────────────────────
// USER MANAGEMENT SCREEN
// ────────────────────────────────────────────────────
class UserManagementScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;

  const UserManagementScreen({super.key, this.currentUser});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _modules = [];
  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _warehouses = [];

  String _searchQuery = '';
  String _roleFilter = 'all';

  int get _currentUserId => (widget.currentUser?['user_id'] as int?) ?? 0;

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

  bool get canViewUsers => hasPermission('USER_VIEW');
  bool get canCreateUsers => hasPermission('USER_CREATE');
  bool get canEditUsers => hasPermission('USER_EDIT');
  bool get canDeleteUsers => hasPermission('USER_DELETE');

  // ── Single ROLES permission — full access to roles management ──
  bool get canManageRoles => hasPermission('ROLES');

  bool _isWide(BuildContext context) {
    return MediaQuery.of(context).size.width >= 900;
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _toList(dynamic v) {
    return (v as List?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ??
        [];
  }

  Future<void> _loadUsers() async {
    if (!canViewUsers && !canManageRoles) {
      setState(() {
        _loading = false;
        _error = 'You do not have permission to view users or roles.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await DBService.instance.fetchUsers();

    if (!mounted) return;

    setState(() {
      _loading = false;

      if (result.success) {
        _users = _toList(result.data?['users']);
        _roles = _toList(result.data?['roles']);
        _modules = _toList(result.data?['modules']);
        _stores = _toList(result.data?['stores']);
        _warehouses = _toList(result.data?['warehouses']);
      } else {
        _error = result.message;
      }
    });
  }

  List<Map<String, dynamic>> get _filtered {
    return _users.where((u) {
      final roleName = (u['role_name'] as String? ?? '').toLowerCase();
      final q = _searchQuery.toLowerCase();

      final matchRole =
          _roleFilter == 'all' || roleName == _roleFilter.toLowerCase();

      final matchSearch = q.isEmpty ||
          (u['full_name'] as String? ?? '').toLowerCase().contains(q) ||
          (u['username'] as String? ?? '').toLowerCase().contains(q) ||
          (u['email'] as String? ?? '').toLowerCase().contains(q);

      return matchRole && matchSearch;
    }).toList();
  }

  Future<void> _toggleActive(Map<String, dynamic> user) async {
    if (!canEditUsers) {
      _snack('You do not have permission to edit users.', error: true);
      return;
    }

    final id = user['user_id'] as int;
    final newState = !(user['is_active'] as bool? ?? true);

    setState(() => user['is_active'] = newState);

    final result = await DBService.instance.toggleUserActive(
      userId: id,
      isActive: newState,
      performedBy: _currentUserId,
    );

    if (!mounted) return;

    if (!result.success) {
      setState(() => user['is_active'] = !newState);
      _snack(result.message, error: true);
    } else {
      _snack(newState ? 'User activated' : 'User deactivated');
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> user, AppTheme t) async {
    if (!canDeleteUsers) {
      _snack('You do not have permission to delete users.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Delete User',
        message:
        'Remove "${user['full_name']}" permanently? This cannot be undone.',
        confirmLabel: 'Delete',
        confirmColor: t.red,
      ),
    );

    if (ok != true || !mounted) return;

    final result = await DBService.instance.deleteUser(
      userId: user['user_id'] as int,
      performedBy: _currentUserId,
    );

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _users.removeWhere((u) => u['user_id'] == user['user_id']);
      });
      _snack('User deleted');
    } else {
      _snack(result.message, error: true);
    }
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    if (existing == null && !canCreateUsers) {
      _snack('You do not have permission to create users.', error: true);
      return;
    }

    if (existing != null && !canEditUsers) {
      _snack('You do not have permission to edit users.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => UserFormDialog(
        existing: existing,
        roles: _roles,
        modules: _modules,
        stores: _stores,
        warehouses: _warehouses,
        currentUserId: _currentUserId,
      ),
    );

    if (ok == true) _loadUsers();
  }

  // ───────────────────────────────────────────────
  // ROLE OPERATIONS
  // ───────────────────────────────────────────────
  Future<void> _openRoleForm({Map<String, dynamic>? existing}) async {
    if (!canManageRoles) {
      _snack('You do not have permission to manage roles.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RoleFormDialog(existing: existing),
    );

    if (ok == true) {
      _snack(existing == null ? 'Role created' : 'Role updated');
      _loadUsers();
    }
  }

  Future<void> _deleteRole(Map<String, dynamic> role, AppTheme t) async {
    if (!canManageRoles) {
      _snack('You do not have permission to manage roles.', error: true);
      return;
    }

    final id = role['role_id'] as int;
    final name = (role['role_name'] as String?) ?? '';
    final userCount = _users.where((u) => u['role_id'] == id).length;

    if (userCount > 0) {
      _snack(
        'Cannot delete "$name": $userCount user(s) still assigned.',
        error: true,
      );
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _ConfirmDialog(
        title: 'Delete Role',
        message:
        'Delete role "$name"? This will also remove its module permissions.',
        confirmLabel: 'Delete',
        confirmColor: t.red,
      ),
    );

    if (ok != true || !mounted) return;

    final result = await DBService.instance.deleteRole(id: id);
    if (!mounted) return;

    if (result.success) {
      _snack(result.message.isEmpty ? 'Role deleted' : result.message);
      _loadUsers();
    } else {
      _snack(result.message, error: true);
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;

    final t = themeNotifier.theme;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? t.red : t.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: themeNotifier,
      builder: (_, __, ___) {
        final t = themeNotifier.theme;

        if (_loading) {
          return Scaffold(
            backgroundColor: t.bg,
            body: Center(
              child: CircularProgressIndicator(color: t.blue),
            ),
          );
        }

        if (_error != null) {
          return Scaffold(
            backgroundColor: t.bg,
            body: _ErrorView(
              message: _error!,
              onRetry: _loadUsers,
            ),
          );
        }

        final wide = _isWide(context);

        return Scaffold(
          backgroundColor: t.bg,
          body: SafeArea(
            child: Column(
              children: [
                // ── Top-level tab bar (Users / Roles) ──
                Padding(
                  padding: EdgeInsets.fromLTRB(
                      wide ? 24 : 16, 16, wide ? 24 : 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.border),
                    ),
                    child: TabBar(
                      controller: _tabs,
                      indicator: BoxDecoration(
                        color: t.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.blue.withOpacity(0.4)),
                      ),
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      labelColor: t.blue,
                      unselectedLabelColor: t.textLo,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      tabs: const [
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.people_rounded, size: 16),
                              SizedBox(width: 6),
                              Text('Users'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.admin_panel_settings_rounded,
                                  size: 16),
                              SizedBox(width: 6),
                              Text('Roles'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _buildUsersTabBody(t),
                      _buildRolesTabBody(t),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ────────────────────────────────────────────────────
  // USERS TAB BODY
  // ────────────────────────────────────────────────────
  Widget _buildUsersTabBody(AppTheme t) {
    return RefreshIndicator(
      color: t.blue,
      backgroundColor: t.surface,
      onRefresh: _loadUsers,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(t)),
          SliverToBoxAdapter(child: _buildFilters(t)),
          SliverToBoxAdapter(child: _buildStats(t)),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          _isWide(context) ? _buildTable(t) : _buildCards(t),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────
  // ROLES TAB BODY
  // ────────────────────────────────────────────────────
  Widget _buildRolesTabBody(AppTheme t) {
    final wide = _isWide(context);

    return RefreshIndicator(
      color: t.blue,
      backgroundColor: t.surface,
      onRefresh: _loadUsers,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  wide ? 24 : 16, 20, wide ? 24 : 16, 0),
              child: wide
                  ? Row(
                children: [
                  _RolesHeaderTitle(t: t),
                  const Spacer(),
                  _RolesHeaderActions(
                    t: t,
                    onRefresh: _loadUsers,
                    onAdd: canManageRoles ? () => _openRoleForm() : null,
                  ),
                ],
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RolesHeaderTitle(t: t),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      if (canManageRoles) ...[
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: t.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding:
                              const EdgeInsets.symmetric(vertical: 14),
                            ),
                            onPressed: () => _openRoleForm(),
                            icon: const Icon(Icons.add_rounded, size: 18),
                            label: const Text('New Role'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      _SquareButton(
                        t: t,
                        icon: Icons.refresh_rounded,
                        onTap: _loadUsers,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: _buildRolesStats(t)),
          const SliverToBoxAdapter(child: SizedBox(height: 8)),
          _buildRolesList(t),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildRolesStats(AppTheme t) {
    final wide = _isWide(context);

    final totalRoles = _roles.length;
    final usedRoles = _roles.where((r) {
      final id = r['role_id'] as int;
      return _users.any((u) => u['role_id'] == id);
    }).length;

    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, wide ? 24 : 16, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MiniStat(t: t, label: 'Total', value: '$totalRoles', color: t.blue),
          _MiniStat(t: t, label: 'In use', value: '$usedRoles', color: t.green),
          _MiniStat(
            t: t,
            label: 'Unused',
            value: '${totalRoles - usedRoles}',
            color: t.textLo,
          ),
        ],
      ),
    );
  }

  Widget _buildRolesList(AppTheme t) {
    if (_roles.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'No roles found',
              style: TextStyle(color: t.textLo),
            ),
          ),
        ),
      );
    }

    final wide = _isWide(context);

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, wide ? 24 : 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
              (_, i) {
            final role = _roles[i];
            final id = role['role_id'] as int;
            final userCount =
                _users.where((u) => u['role_id'] == id).length;
            return _RoleCard(
              t: t,
              role: role,
              userCount: userCount,
              canManage: canManageRoles,
              onEdit: () => _openRoleForm(existing: role),
              onDelete: () => _deleteRole(role, t),
            );
          },
          childCount: _roles.length,
        ),
      ),
    );
  }

  Widget _buildHeader(AppTheme t) {
    final wide = _isWide(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 20, wide ? 24 : 16, 0),
      child: wide
          ? Row(
        children: [
          _HeaderTitle(t: t),
          const Spacer(),
          _HeaderActions(
            t: t,
            onRefresh: _loadUsers,
            onAdd: canCreateUsers ? () => _openForm() : null,
          ),
        ],
      )
          : Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderTitle(t: t),
          const SizedBox(height: 14),
          Row(
            children: [
              if (canCreateUsers) ...[
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: t.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.person_add_rounded, size: 18),
                    label: const Text('New User'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
              _SquareButton(
                t: t,
                icon: Icons.refresh_rounded,
                onTap: _loadUsers,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilters(AppTheme t) {
    final wide = _isWide(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, wide ? 24 : 16, 0),
      child: wide
          ? Row(
        children: [
          Expanded(
            child: _SearchBar(
              t: t,
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          const SizedBox(width: 12),
          _RoleFilterDropdown(
            t: t,
            roles: _roles,
            selected: _roleFilter,
            onChanged: (r) => setState(() => _roleFilter = r),
          ),
        ],
      )
          : Column(
        children: [
          _SearchBar(
            t: t,
            onChanged: (v) => setState(() => _searchQuery = v),
          ),
          const SizedBox(height: 10),
          _RoleFilterDropdown(
            t: t,
            roles: _roles,
            selected: _roleFilter,
            onChanged: (r) => setState(() => _roleFilter = r),
            fullWidth: true,
          ),
        ],
      ),
    );
  }

  Widget _buildStats(AppTheme t) {
    final total = _users.length;
    final active = _users.where((u) => u['is_active'] == true).length;

    final byRole = <String, int>{};
    for (final u in _users) {
      final rn = u['role_name'] as String? ?? 'Unknown';
      byRole[rn] = (byRole[rn] ?? 0) + 1;
    }

    final wide = _isWide(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, wide ? 24 : 16, 0),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _MiniStat(t: t, label: 'Total', value: '$total', color: t.blue),
          _MiniStat(t: t, label: 'Active', value: '$active', color: t.green),
          ...byRole.entries.map(
                (e) => _MiniStat(
              t: t,
              label: e.key,
              value: '${e.value}',
              color: _roleColor(e.key),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTable(AppTheme t) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
        child: Container(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.border),
          ),
          child: Column(
            children: [
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: t.border)),
                ),
                child: Row(
                  children: [
                    Expanded(flex: 3, child: _TH(t: t, text: 'User')),
                    Expanded(flex: 2, child: _TH(t: t, text: 'Email')),
                    Expanded(flex: 2, child: _TH(t: t, text: 'Role')),
                    Expanded(flex: 2, child: _TH(t: t, text: 'Permissions')),
                    Expanded(flex: 1, child: _TH(t: t, text: 'Status')),
                    SizedBox(width: 96, child: _TH(t: t, text: 'Actions')),
                  ],
                ),
              ),
              if (_filtered.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'No users match your filter',
                    style: TextStyle(color: t.textLo),
                  ),
                )
              else
                ..._filtered.asMap().entries.map(
                      (e) => _TableRow(
                    t: t,
                    user: e.value,
                    isLast: e.key == _filtered.length - 1,
                    canEdit: canEditUsers,
                    canDelete: canDeleteUsers,
                    onEdit: () => _openForm(existing: e.value),
                    onToggle: () => _toggleActive(e.value),
                    onDelete: () => _confirmDelete(e.value, t),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCards(AppTheme t) {
    if (_filtered.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'No users match your filter',
              style: TextStyle(color: t.textLo),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
              (_, i) => _UserCard(
            t: t,
            user: _filtered[i],
            canEdit: canEditUsers,
            canDelete: canDeleteUsers,
            onEdit: () => _openForm(existing: _filtered[i]),
            onToggle: () => _toggleActive(_filtered[i]),
            onDelete: () => _confirmDelete(_filtered[i], t),
          ),
          childCount: _filtered.length,
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────
// ROLES — HEADER PIECES
// ────────────────────────────────────────────────────
class _RolesHeaderTitle extends StatelessWidget {
  final AppTheme t;
  const _RolesHeaderTitle({required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Role Management',
          style: TextStyle(
            color: t.textHi,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Create, rename and delete roles for your users',
          style: TextStyle(color: t.textLo, fontSize: 12),
        ),
      ],
    );
  }
}

class _RolesHeaderActions extends StatelessWidget {
  final AppTheme t;
  final VoidCallback onRefresh;
  final VoidCallback? onAdd;

  const _RolesHeaderActions({
    required this.t,
    required this.onRefresh,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SquareButton(t: t, icon: Icons.refresh_rounded, onTap: onRefresh),
        if (onAdd != null) ...[
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: t.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New Role'),
          ),
        ],
      ],
    );
  }
}

// ────────────────────────────────────────────────────
// ROLE CARD
// ────────────────────────────────────────────────────
class _RoleCard extends StatelessWidget {
  final AppTheme t;
  final Map<String, dynamic> role;
  final int userCount;
  final bool canManage;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RoleCard({
    required this.t,
    required this.role,
    required this.userCount,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = role['role_name'] as String? ?? '';
    final desc = role['description'] as String? ?? '';
    final color = _roleColor(name);
    final icon = _roleIcon(name);
    final canDel = canManage && userCount == 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        style: TextStyle(
                          color: t.textHi,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: t.blue.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: t.blue.withOpacity(0.25)),
                      ),
                      child: Text(
                        '$userCount user${userCount == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: t.blue,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  desc.trim().isEmpty ? 'No description' : desc,
                  style: TextStyle(color: t.textLo, fontSize: 12),
                ),
              ],
            ),
          ),
          if (canManage) ...[
            _IconBtn(
              icon: Icons.edit_rounded,
              color: t.blue,
              tooltip: 'Edit',
              onTap: onEdit,
            ),
            _IconBtn(
              icon: Icons.delete_outline_rounded,
              color: canDel ? t.red : t.textLo.withOpacity(0.4),
              tooltip: canDel ? 'Delete' : 'Cannot delete (in use)',
              onTap: canDel ? onDelete : () {},
            ),
          ],
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────
// ROLE FORM DIALOG
// ────────────────────────────────────────────────────
class _RoleFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;

  const _RoleFormDialog({this.existing});

  @override
  State<_RoleFormDialog> createState() => _RoleFormDialogState();
}

class _RoleFormDialogState extends State<_RoleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;

  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(
      text: (widget.existing?['role_name'] as String?) ?? '',
    );
    _descCtrl = TextEditingController(
      text: (widget.existing?['description'] as String?) ?? '',
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final id = _isEdit ? widget.existing!['role_id'] as int : null;

    final result = await DBService.instance.saveRole(
      id: id,
      name: _nameCtrl.text.trim(),
      description: _descCtrl.text.trim(),
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
    return ValueListenableBuilder<bool>(
      valueListenable: themeNotifier,
      builder: (_, __, ___) {
        final t = themeNotifier.theme;
        final sw = MediaQuery.of(context).size.width;
        final dialogWidth = sw >= 720 ? 520.0 : sw * 0.95;

        return Dialog(
          backgroundColor: t.surface,
          insetPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18)),
          child: SizedBox(
            width: dialogWidth,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: t.blue.withOpacity(0.10),
                            borderRadius: BorderRadius.circular(10),
                            border:
                            Border.all(color: t.blue.withOpacity(0.20)),
                          ),
                          child: Icon(
                            _isEdit
                                ? Icons.edit_rounded
                                : Icons.admin_panel_settings_rounded,
                            color: t.blue,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isEdit ? 'Edit Role' : 'Create Role',
                                style: TextStyle(
                                  color: t.textHi,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'Set a name and an optional description',
                                style: TextStyle(
                                    color: t.textLo, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close_rounded,
                              color: t.textLo, size: 20),
                          onPressed:
                          _saving ? null : () => Navigator.pop(context, false),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _SectionLabel(t: t, text: 'Role Name'),
                    const SizedBox(height: 5),
                    TextFormField(
                      controller: _nameCtrl,
                      style: TextStyle(color: t.textHi, fontSize: 13),
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'Role name is required'
                          : null,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.badge_rounded,
                            color: t.textLo, size: 17),
                        filled: true,
                        fillColor: t.bg,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: _ob(t.border),
                        enabledBorder: _ob(t.border),
                        focusedBorder: _ob(t.blue, w: 1.5),
                        errorBorder: _ob(t.red),
                        errorStyle: TextStyle(color: t.red, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _SectionLabel(t: t, text: 'Description (optional)'),
                    const SizedBox(height: 5),
                    TextFormField(
                      controller: _descCtrl,
                      maxLines: 2,
                      style: TextStyle(color: t.textHi, fontSize: 13),
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.description_outlined,
                            color: t.textLo, size: 17),
                        filled: true,
                        fillColor: t.bg,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        border: _ob(t.border),
                        enabledBorder: _ob(t.border),
                        focusedBorder: _ob(t.blue, w: 1.5),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 14),
                      _ErrorBanner(t: t, message: _error!),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: t.border),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding:
                              const EdgeInsets.symmetric(vertical: 13),
                            ),
                            onPressed: _saving
                                ? null
                                : () => Navigator.pop(context, false),
                            child: Text('Cancel',
                                style: TextStyle(color: t.textLo)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: t.blue,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding:
                              const EdgeInsets.symmetric(vertical: 13),
                            ),
                            onPressed: _saving ? null : _submit,
                            child: _saving
                                ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                                : Text(
                                _isEdit ? 'Save Changes' : 'Create Role'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  OutlineInputBorder _ob(Color c, {double w = 1.0}) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: c, width: w),
  );
}

// ────────────────────────────────────────────────────
// TABLE ROW
// ────────────────────────────────────────────────────
class _TableRow extends StatelessWidget {
  final AppTheme t;
  final Map<String, dynamic> user;
  final bool isLast;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TableRow({
    required this.t,
    required this.user,
    required this.isLast,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = user['is_active'] as bool? ?? true;
    final roleName = user['role_name'] as String? ?? '';
    final name = user['full_name'] as String? ?? '';
    final username = user['username'] as String? ?? '';
    final email = user['email'] as String? ?? '';

    final permissions = user['permissions'] as List? ?? [];
    final granted =
        permissions.cast<Map>().where((p) => p['can_access'] == true).length;
    final total = permissions.length;

    return Container(
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: t.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                _Avatar(initials: _initials(name), color: _roleColor(roleName)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: t.textHi,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '@$username',
                        style: TextStyle(color: t.textLo, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              email,
              style: TextStyle(color: t.textLo, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(flex: 2, child: _RoleBadge(roleName: roleName)),
          Expanded(
            flex: 2,
            child: _PermBadge(t: t, granted: granted, total: total),
          ),
          Expanded(
            flex: 1,
            child: Switch(
              value: isActive,
              activeColor: t.green,
              onChanged: canEdit ? (_) => onToggle() : null,
            ),
          ),
          SizedBox(
            width: 96,
            child: Row(
              children: [
                if (canEdit) ...[
                  _IconBtn(
                    icon: Icons.edit_rounded,
                    color: t.blue,
                    tooltip: 'Edit',
                    onTap: onEdit,
                  ),
                  const SizedBox(width: 4),
                ],
                if (canDelete)
                  _IconBtn(
                    icon: Icons.delete_outline_rounded,
                    color: t.red,
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

// ────────────────────────────────────────────────────
// USER CARD
// ────────────────────────────────────────────────────
class _UserCard extends StatelessWidget {
  final AppTheme t;
  final Map<String, dynamic> user;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _UserCard({
    required this.t,
    required this.user,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = user['is_active'] as bool? ?? true;
    final roleName = user['role_name'] as String? ?? '';
    final name = user['full_name'] as String? ?? '';
    final username = user['username'] as String? ?? '';
    final email = user['email'] as String? ?? '';

    final permissions = user['permissions'] as List? ?? [];
    final granted =
        permissions.cast<Map>().where((p) => p['can_access'] == true).length;
    final total = permissions.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _Avatar(initials: _initials(name), color: _roleColor(roleName)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: TextStyle(
                        color: t.textHi,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '@$username',
                      style: TextStyle(color: t.textLo, fontSize: 12),
                    ),
                    if (email.isNotEmpty)
                      Text(
                        email,
                        style: TextStyle(color: t.textLo, fontSize: 11),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _RoleBadge(roleName: roleName),
                  const SizedBox(height: 6),
                  _PermBadge(t: t, granted: granted, total: total),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.circle,
                size: 8,
                color: isActive ? t.green : t.red,
              ),
              const SizedBox(width: 6),
              Text(
                isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  color: isActive ? t.green : t.red,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Switch(
                value: isActive,
                activeColor: t.green,
                onChanged: canEdit ? (_) => onToggle() : null,
              ),
              if (canEdit)
                _IconBtn(
                  icon: Icons.edit_rounded,
                  color: t.blue,
                  tooltip: 'Edit',
                  onTap: onEdit,
                ),
              if (canDelete)
                _IconBtn(
                  icon: Icons.delete_outline_rounded,
                  color: t.red,
                  tooltip: 'Delete',
                  onTap: onDelete,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────
// REUSABLE WIDGETS
// ────────────────────────────────────────────────────
class _HeaderTitle extends StatelessWidget {
  final AppTheme t;

  const _HeaderTitle({required this.t});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'User Management',
          style: TextStyle(
            color: t.textHi,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Create, assign roles & manage accounts',
          style: TextStyle(color: t.textLo, fontSize: 12),
        ),
      ],
    );
  }
}


class _HeaderActions extends StatelessWidget {
  final AppTheme t;
  final VoidCallback onRefresh;
  final VoidCallback? onAdd;

  const _HeaderActions({
    required this.t,
    required this.onRefresh,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SquareButton(t: t, icon: Icons.refresh_rounded, onTap: onRefresh),
        if (onAdd != null) ...[
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: t.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: onAdd,
            icon: const Icon(Icons.person_add_rounded, size: 18),
            label: const Text('New User'),
          ),
        ],
      ],
    );
  }
}

class _SquareButton extends StatelessWidget {
  final AppTheme t;
  final IconData icon;
  final VoidCallback onTap;

  const _SquareButton({
    required this.t,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: t.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.border),
          ),
          child: Icon(icon, color: t.textLo),
        ),
      ),
    );
  }
}

class _ThemedDropdown<T> extends StatelessWidget {
  final AppTheme t;
  final String label;
  final IconData icon;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? Function(T?)? validator;

  const _ThemedDropdown({
    required this.t,
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      value: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      dropdownColor: t.surface,
      iconEnabledColor: t.textLo,
      style: TextStyle(color: t.textHi, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: t.textLo),
        prefixIcon: Icon(icon, color: t.textLo, size: 18),
        filled: true,
        fillColor: t.bg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.blue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.red),
        ),
      ),
    );
  }
}

class _RoleFilterDropdown extends StatelessWidget {
  final AppTheme t;
  final List<Map<String, dynamic>> roles;
  final String selected;
  final ValueChanged<String> onChanged;
  final bool fullWidth;

  const _RoleFilterDropdown({
    required this.t,
    required this.roles,
    required this.selected,
    required this.onChanged,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth ? double.infinity : 230,
      child: DropdownButtonFormField<String>(
        value: selected,
        dropdownColor: t.surface,
        iconEnabledColor: t.textLo,
        style: TextStyle(color: t.textHi, fontSize: 13),
        decoration: InputDecoration(
          labelText: 'Role',
          labelStyle: TextStyle(color: t.textLo),
          prefixIcon: Icon(
            Icons.admin_panel_settings_rounded,
            color: t.textLo,
            size: 18,
          ),
          filled: true,
          fillColor: t.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: t.blue, width: 1.5),
          ),
        ),
        items: [
          const DropdownMenuItem(
            value: 'all',
            child: Text('All Roles'),
          ),
          ...roles.map((r) {
            final name = r['role_name'] as String? ?? '';
            return DropdownMenuItem(
              value: name.toLowerCase(),
              child: Text(name),
            );
          }),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  final Color color;

  const _Avatar({
    required this.initials,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: color.withOpacity(0.13),
      child: Text(
        initials,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String roleName;

  const _RoleBadge({required this.roleName});

  @override
  Widget build(BuildContext context) {
    final color = _roleColor(roleName);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Text(
        roleName,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PermBadge extends StatelessWidget {
  final AppTheme t;
  final int granted;
  final int total;

  const _PermBadge({
    required this.t,
    required this.granted,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: t.purple.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.purple.withOpacity(0.25)),
      ),
      child: Text(
        '$granted / $total modules',
        style: TextStyle(
          color: t.purple,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final AppTheme t;
  final String label;
  final String value;
  final Color color;

  const _MiniStat({
    required this.t,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(color: t.textLo, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final AppTheme t;
  final ValueChanged<String> onChanged;

  const _SearchBar({
    required this.t,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      style: TextStyle(color: t.textHi, fontSize: 14),
      decoration: InputDecoration(
        hintText: 'Search name, username or email…',
        hintStyle: TextStyle(color: t.textLo, fontSize: 13),
        prefixIcon: Icon(Icons.search_rounded, color: t.textLo, size: 20),
        filled: true,
        fillColor: t.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.blue, width: 1.5),
        ),
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      onChanged: onChanged,
    );
  }
}

class _TH extends StatelessWidget {
  final AppTheme t;
  final String text;

  const _TH({
    required this.t,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: t.textLo,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final AppTheme t;
  final String text;

  const _Label({
    required this.t,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: t.textLo,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
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

class _ConfirmDialog extends StatelessWidget {
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;

  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;

    return AlertDialog(
      backgroundColor: t.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(
        title,
        style: TextStyle(
          color: t.textHi,
          fontWeight: FontWeight.w700,
        ),
      ),
      content: Text(
        message,
        style: TextStyle(color: t.textLo, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(
            'Cancel',
            style: TextStyle(color: t.textLo),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: confirmColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: t.blue,
                foregroundColor: Colors.white,
              ),
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



// ─────────────────────────────────────────────────────────────────
// MODULE GROUPS  (all 49 from DB, grouped for the permissions tab)
// ─────────────────────────────────────────────────────────────────
const _moduleGroups = <String, List<String>>{
  'Mobile': [
    'Warehouse Inventory - Mobile',
    'Store Inventory - Mobile',
    'Scan Items - Mobile',
    'Stock Transfers - Mobile',
    'Delivery In - Mobile',
    'Refund Items - Mobile',
    'Transfer Confirmations - Mobile',
    'Refund Item Decision - Mobile',
    'Bad Order - Mobile',
  ],
  'Products': [
    'PRODUCT_VIEW',
    'PRODUCT_CREATE',
    'PRODUCT_IMPORT',
    'PRODUCT_EDIT',
    'PRODUCT_DELETE',
    'PRODUCT_MANAGE_UOM',
  ],
  'Inventory': [
    'INVENTORY_VIEW',
    'WAREHOUSE_STOCK_ADD',
    'WAREHOUSE_STOCK_EDIT',
    'WAREHOUSE_STOCK_DELETE',
    'WAREHOUSE_STOCK_IMPORT',
    'STORE_STOCK_ADD',
    'STORE_STOCK_EDIT',
    'STORE_STOCK_DELETE',
    'STORE_STOCK_IMPORT',
  ],
  'Deliveries': [
    'DELIVERY_VIEW',
    'DELIVERY_EXPORT',
  ],
  'Suppliers': [
    'SUPPLIER_VIEW',
    'SUPPLIER_CREATE',
    'SUPPLIER_EDIT',
    'SUPPLIER_DELETE',
    'SUPPLIER_IMPORT',
  ],
  'Users': [
    'USER_VIEW',
    'USER_CREATE',
    'USER_EDIT',
    'USER_DELETE',
  ],
  'Reports': [
    'REPORT_VIEW',
    'REPORT_DAILY_SALES',
    'REPORT_SALES_PER_CLERK',
    'REPORT_WAREHOUSE_TRANSFER',
    'REPORT_REFUND',
    'REPORT_DISPOSAL',
    'REPORT_LOW_STOCK',
    'REPORT_BAD_ORDER',
    'REPORT_PROMO_SALES',
  ],
  'Locations': [
    'LOCATION_VIEW',
    'LOCATION_CREATE',
    'LOCATION_EDIT',
    'LOCATION_DELETE',
  ],
  'Roles': [
    'ROLES',
  ],
  'Promotions': [
    'PROMOS',
  ],
  'Activity Log': [          // ← add this
    'ACTIVITY_LOG_VIEW',
  ],
};

// ─────────────────────────────────────────────────────────────────
// TAB ENUM
// ─────────────────────────────────────────────────────────────────
enum _FormTab { identity, access, permissions }

// ─────────────────────────────────────────────────────────────────
// DIALOG WIDGET
// ─────────────────────────────────────────────────────────────────
class UserFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> roles;
  final List<Map<String, dynamic>> modules;
  final List<Map<String, dynamic>> stores;
  final List<Map<String, dynamic>> warehouses;
  final int currentUserId;

  const UserFormDialog({
    super.key,
    this.existing,
    required this.roles,
    required this.modules,
    required this.stores,
    required this.warehouses,
    required this.currentUserId,
  });

  @override
  State<UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<UserFormDialog>
    with SingleTickerProviderStateMixin {
  // ── controllers ──────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _fullName;
  late final TextEditingController _email;

  // ── state ─────────────────────────────────────────────────────
  _FormTab _tab = _FormTab.identity;
  int? _selectedRoleId;
  final Set<int> _storeIds = {};
  final Set<int> _warehouseIds = {};
  Map<int, bool> _perms = {};

  bool _saving = false;
  bool _obscurePass = true;
  String? _errorMsg;

  // ── permissions tab state ─────────────────────────────────────
  final TextEditingController _modSearch = TextEditingController();
  bool _showSelectedOnly = false;
  String _modQuery = '';

  bool get _isEdit => widget.existing != null;

  // ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _username = TextEditingController(text: e?['username'] ?? '');
    _password = TextEditingController();
    _fullName = TextEditingController(text: e?['full_name'] ?? '');
    _email = TextEditingController(text: e?['email'] ?? '');
    _selectedRoleId = e?['role_id'] as int?;

    if (e != null) {
      for (final s in (e['assigned_stores'] as List? ?? [])) {
        _storeIds.add((s as Map)['store_id'] as int);
      }
      for (final w in (e['assigned_warehouses'] as List? ?? [])) {
        _warehouseIds.add((w as Map)['warehouse_id'] as int);
      }
      for (final p in (e['permissions'] as List? ?? [])) {
        final map = Map<String, dynamic>.from(p as Map);
        _perms[map['module_id'] as int] = map['can_access'] as bool? ?? false;
      }
    }
    for (final m in widget.modules) {
      _perms.putIfAbsent(m['module_id'] as int, () => false);
    }

    _modSearch.addListener(() => setState(() => _modQuery = _modSearch.text));
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _fullName.dispose();
    _email.dispose();
    _modSearch.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // helpers
  // ─────────────────────────────────────────────────────────────
  int get _grantedCount => _perms.values.where((v) => v).length;

  Map<String, dynamic>? _moduleByName(String name) {
    try {
      return widget.modules.firstWhere(
            (m) => (m['module_name'] as String?) == name,
      );
    } catch (_) {
      return null;
    }
  }

  bool _permOf(String name) {
    final m = _moduleByName(name);
    if (m == null) return false;
    return _perms[m['module_id'] as int] ?? false;
  }

  void _togglePerm(String name, bool val) {
    final m = _moduleByName(name);
    if (m == null) return;
    setState(() => _perms[m['module_id'] as int] = val);
  }

  void _setGroupAll(List<String> names, bool val) {
    for (final n in names) {
      final m = _moduleByName(n);
      if (m != null) _perms[m['module_id'] as int] = val;
    }
    setState(() {});
  }

  // ─────────────────────────────────────────────────────────────
  // submit
  // ─────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      setState(() => _tab = _FormTab.identity);
      return;
    }
    if (_selectedRoleId == null) {
      setState(() {
        _tab = _FormTab.identity;
        _errorMsg = 'Please select a role.';
      });
      return;
    }
    setState(() {
      _saving = true;
      _errorMsg = null;
    });

    final permsList = _perms.entries
        .map((e) => {'module_id': e.key, 'can_access': e.value})
        .toList();

    DBResult result;
    if (_isEdit) {
      result = await DBService.instance.updateUser(
        userId: widget.existing!['user_id'] as int,
        fullName: _fullName.text.trim(),
        email: _email.text.trim(),
        roleId: _selectedRoleId,
        storeId: _storeIds.isEmpty ? null : _storeIds.first,
        warehouseId: _warehouseIds.isEmpty ? null : _warehouseIds.first,
        assignedStoreIds: _storeIds.toList(),
        assignedWarehouseIds: _warehouseIds.toList(),
        permissions: permsList,
        performedBy: widget.currentUserId,
      );
    } else {
      result = await DBService.instance.createUser(
        username: _username.text.trim(),
        password: _password.text,
        fullName: _fullName.text.trim(),
        email: _email.text.trim(),
        storeId: _storeIds.isEmpty ? null : _storeIds.first,
        warehouseId: _warehouseIds.isEmpty ? null : _warehouseIds.first,
        assignedStoreIds: _storeIds.toList(),
        assignedWarehouseIds: _warehouseIds.toList(),
        roleId: _selectedRoleId!,
        permissions: permsList,
        performedBy: widget.currentUserId,
      );
    }

    if (!mounted) return;
    setState(() => _saving = false);
    if (result.success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _errorMsg = result.message);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: themeNotifier,
      builder: (_, __, ___) {
        final t = themeNotifier.theme;
        final sw = MediaQuery.of(context).size.width;
        final wide = sw >= 720;
        final dialogWidth =
        sw >= 960 ? 720.0 : sw >= 720 ? 640.0 : sw * 0.95;

        return Dialog(
          backgroundColor: t.surface,
          insetPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: SizedBox(
            width: dialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeader(t),
                _buildTabBar(t),
                const Divider(height: 1, thickness: 0.5),
                Flexible(
                  child: Form(
                    key: _formKey,
                    child: _buildBody(t, wide),
                  ),
                ),
                _buildFooter(t),
              ],
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // HEADER
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader(AppTheme t) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 0),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: t.blue.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.blue.withOpacity(0.20)),
            ),
            child: Icon(
              _isEdit ? Icons.edit_rounded : Icons.person_add_rounded,
              color: t.blue,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isEdit ? 'Edit User' : 'Create User',
                  style: TextStyle(
                    color: t.textHi,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Complete all three sections',
                  style: TextStyle(color: t.textLo, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, color: t.textLo, size: 20),
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // TAB BAR
  // ─────────────────────────────────────────────────────────────
  Widget _buildTabBar(AppTheme t) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          _TabItem(
            t: t,
            icon: Icons.badge_rounded,
            label: 'Identity',
            active: _tab == _FormTab.identity,
            dotColor: (_selectedRoleId != null &&
                _fullName.text.trim().isNotEmpty)
                ? t.green
                : null,
            onTap: () => setState(() => _tab = _FormTab.identity),
          ),
          _TabItem(
            t: t,
            icon: Icons.store_rounded,
            label: 'Access',
            active: _tab == _FormTab.access,
            dotColor: (_storeIds.isNotEmpty || _warehouseIds.isNotEmpty)
                ? t.green
                : null,
            onTap: () => setState(() => _tab = _FormTab.access),
          ),
          _TabItem(
            t: t,
            icon: Icons.shield_outlined,
            label: 'Permissions',
            active: _tab == _FormTab.permissions,
            dotColor: _grantedCount > 0 ? t.green : null,
            badge: _grantedCount > 0 ? '$_grantedCount' : null,
            onTap: () => setState(() => _tab = _FormTab.permissions),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // BODY
  // ─────────────────────────────────────────────────────────────
  Widget _buildBody(AppTheme t, bool wide) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_tab == _FormTab.identity) _buildIdentityTab(t, wide),
          if (_tab == _FormTab.access) _buildAccessTab(t),
          if (_tab == _FormTab.permissions) _buildPermissionsTab(t),
          if (_errorMsg != null) ...[
            const SizedBox(height: 14),
            _ErrorBanner(t: t, message: _errorMsg!),
          ],
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  // ── IDENTITY TAB ──────────────────────────────────────────────
  Widget _buildIdentityTab(AppTheme t, bool wide) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Full name + email
        wide
            ? Row(children: [
          Expanded(child: _Field(t: t, ctrl: _fullName, label: 'Full Name', icon: Icons.badge_rounded, validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null)),
          const SizedBox(width: 12),
          Expanded(child: _Field(t: t, ctrl: _email, label: 'Email', icon: Icons.email_outlined, keyboard: TextInputType.emailAddress)),
        ])
            : Column(children: [
          _Field(t: t, ctrl: _fullName, label: 'Full Name', icon: Icons.badge_rounded, validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null),
          const SizedBox(height: 12),
          _Field(t: t, ctrl: _email, label: 'Email', icon: Icons.email_outlined, keyboard: TextInputType.emailAddress),
        ]),

        const SizedBox(height: 12),

        // Username + password (create only)
        if (!_isEdit)
          wide
              ? Row(children: [
            Expanded(child: _Field(t: t, ctrl: _username, label: 'Username', icon: Icons.person_outline_rounded, validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null)),
            const SizedBox(width: 12),
            Expanded(
              child: _PasswordField(
                t: t,
                ctrl: _password,
                obscure: _obscurePass,
                onToggle: () => setState(() => _obscurePass = !_obscurePass),
                validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
              ),
            ),
          ])
              : Column(children: [
            _Field(t: t, ctrl: _username, label: 'Username', icon: Icons.person_outline_rounded, validator: (v) => (v?.trim().isEmpty ?? true) ? 'Required' : null),
            const SizedBox(height: 12),
            _PasswordField(
              t: t,
              ctrl: _password,
              obscure: _obscurePass,
              onToggle: () => setState(() => _obscurePass = !_obscurePass),
              validator: (v) => (v?.isEmpty ?? true) ? 'Required' : null,
            ),
          ]),

        const SizedBox(height: 18),

        // Role picker
        _SectionLabel(t: t, text: 'Role'),
        const SizedBox(height: 8),
        _RolePicker(
          t: t,
          roles: widget.roles,
          selectedId: _selectedRoleId,
          onChanged: (id) => setState(() => _selectedRoleId = id),
        ),
      ],
    );
  }

  // ── ACCESS TAB ────────────────────────────────────────────────
  Widget _buildAccessTab(AppTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionLabel(t: t, text: 'Assigned Stores'),
        const SizedBox(height: 2),
        Text(
          'Stores this user can operate in',
          style: TextStyle(color: t.textLo, fontSize: 12),
        ),
        const SizedBox(height: 10),
        ...widget.stores.map((s) {
          final id = s['store_id'] as int;
          return _AccessRow(
            t: t,
            icon: Icons.store_rounded,
            name: s['store_name'] as String? ?? '',
            checked: _storeIds.contains(id),
            onChanged: (v) => setState(() {
              v! ? _storeIds.add(id) : _storeIds.remove(id);
            }),
          );
        }),

        const SizedBox(height: 20),
        Divider(height: 1, thickness: 0.5, color: t.border),
        const SizedBox(height: 20),

        _SectionLabel(t: t, text: 'Assigned Warehouses'),
        const SizedBox(height: 2),
        Text(
          'Warehouses this user can manage inventory in',
          style: TextStyle(color: t.textLo, fontSize: 12),
        ),
        const SizedBox(height: 10),
        ...widget.warehouses.map((w) {
          final id = w['warehouse_id'] as int;
          return _AccessRow(
            t: t,
            icon: Icons.warehouse_rounded,
            name: w['warehouse_name'] as String? ?? '',
            checked: _warehouseIds.contains(id),
            onChanged: (v) => setState(() {
              v! ? _warehouseIds.add(id) : _warehouseIds.remove(id);
            }),
          );
        }),
      ],
    );
  }

  // ── PERMISSIONS TAB ───────────────────────────────────────────
  Widget _buildPermissionsTab(AppTheme t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Search + filter row
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _modSearch,
                style: TextStyle(color: t.textHi, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Search modules…',
                  hintStyle: TextStyle(color: t.textLo, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, color: t.textLo, size: 18),
                  filled: true,
                  fillColor: t.bg,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  border: _border(t.border),
                  enabledBorder: _border(t.border),
                  focusedBorder: _border(t.blue, width: 1.5),
                ),
              ),
            ),
            const SizedBox(width: 8),
            _FilterToggle(
              t: t,
              active: _showSelectedOnly,
              onTap: () => setState(() => _showSelectedOnly = !_showSelectedOnly),
            ),
          ],
        ),

        const SizedBox(height: 10),

        // Stats row
        Row(
          children: [
            Text(
              '$_grantedCount / ${widget.modules.length} enabled',
              style: TextStyle(color: t.textLo, fontSize: 12),
            ),
            const Spacer(),
            _QuickAction(
              t: t,
              label: 'Enable all',
              color: t.green,
              onTap: () {
                for (final key in _perms.keys) {
                  _perms[key] = true;
                }
                setState(() {});
              },
            ),
            const SizedBox(width: 4),
            _QuickAction(
              t: t,
              label: 'Clear all',
              color: t.red,
              onTap: () {
                for (final key in _perms.keys) {
                  _perms[key] = false;
                }
                setState(() {});
              },
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Module groups
        ..._moduleGroups.entries.map((entry) {
          // Convert the hardcoded module name list into actual module
          // maps from the database (widget.modules).
          final groupModules = entry.value
              .map((name) => _moduleByName(name))
              .whereType<Map<String, dynamic>>()
              .toList();

          return _ModuleGroup(
            t: t,
            groupName: entry.key,
            groupModules: groupModules,
            query: _modQuery.toLowerCase(),
            showSelectedOnly: _showSelectedOnly,
            permOf: _permOf,
            onToggle: _togglePerm,
            onGroupAll: (val) => _setGroupAll(entry.value, val),
          );
        }),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────
  // FOOTER
  // ─────────────────────────────────────────────────────────────
  Widget _buildFooter(AppTheme t) {
    final isLast = _tab == _FormTab.permissions;
    final isFirst = _tab == _FormTab.identity;

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 16),
      decoration: BoxDecoration(
        color: t.bg,
        border: Border(top: BorderSide(color: t.border, width: 0.5)),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(18)),
      ),
      child: Row(
        children: [
          // Step dots
          Row(
            children: _FormTab.values.map((tab) {
              final active = _tab == tab;
              return Container(
                width: active ? 18 : 7,
                height: 7,
                margin: const EdgeInsets.only(right: 5),
                decoration: BoxDecoration(
                  color: active ? t.blue : t.border,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }).toList(),
          ),
          const Spacer(),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: t.textLo, fontSize: 13)),
          ),
          const SizedBox(width: 6),
          if (!isFirst) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: t.textLo,
                side: BorderSide(color: t.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: _saving ? null : () => setState(() => _tab = _FormTab.values[_tab.index - 1]),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 6),
          ],
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: isLast ? t.green : t.blue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            onPressed: _saving
                ? null
                : isLast
                ? _submit
                : () => setState(() => _tab = _FormTab.values[_tab.index + 1]),
            child: _saving
                ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
                : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isLast ? (_isEdit ? 'Save Changes' : 'Create User') : 'Next',
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(width: 4),
                Icon(
                  isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                  size: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  OutlineInputBorder _border(Color color, {double width = 1.0}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// TAB ITEM
// ─────────────────────────────────────────────────────────────────
class _TabItem extends StatelessWidget {
  final AppTheme t;
  final IconData icon;
  final String label;
  final bool active;
  final Color? dotColor;
  final String? badge;
  final VoidCallback onTap;

  const _TabItem({
    required this.t,
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    this.dotColor,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? t.blue : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: active ? t.blue : t.textLo),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? t.blue : t.textLo,
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: t.blue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: t.blue,
                    ),
                  ),
                ),
              ] else if (dotColor != null) ...[
                const SizedBox(width: 5),
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: dotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// ROLE PICKER
// ─────────────────────────────────────────────────────────────────
class _RolePicker extends StatelessWidget {
  final AppTheme t;
  final List<Map<String, dynamic>> roles;
  final int? selectedId;
  final ValueChanged<int?> onChanged;

  const _RolePicker({
    required this.t,
    required this.roles,
    required this.selectedId,
    required this.onChanged,
  });

  IconData _icon(String name) {
    final n = name.toLowerCase();
    if (n.contains('super')) return Icons.verified_user_rounded;
    if (n.contains('admin')) return Icons.shield_rounded;
    if (n.contains('manager')) return Icons.work_rounded;
    if (n.contains('cashier')) return Icons.point_of_sale_rounded;
    return Icons.person_rounded;
  }

  Color _color(String name, AppTheme t) {
    final n = name.toLowerCase();
    if (n.contains('super')) return t.red;
    if (n.contains('admin')) return t.blue;
    if (n.contains('manager')) return t.amber;
    if (n.contains('cashier')) return t.green;
    return t.blue;
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: roles.map((r) {
        final id = r['role_id'] as int;
        final name = r['role_name'] as String? ?? '';
        final selected = selectedId == id;
        final color = _color(name, t);

        return GestureDetector(
          onTap: () => onChanged(id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? color.withOpacity(0.10) : t.bg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected ? color : t.border,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_icon(name), size: 16, color: selected ? color : t.textLo),
                const SizedBox(width: 7),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? color : t.textHi,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.check_circle_rounded, size: 14, color: color),
                ],
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// ACCESS ROW
// ─────────────────────────────────────────────────────────────────
class _AccessRow extends StatelessWidget {
  final AppTheme t;
  final IconData icon;
  final String name;
  final bool checked;
  final ValueChanged<bool?> onChanged;

  const _AccessRow({
    required this.t,
    required this.icon,
    required this.name,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!checked),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: checked ? t.blue.withOpacity(0.06) : t.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: checked ? t.blue.withOpacity(0.35) : t.border,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: checked ? t.blue : t.textLo),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
                  color: checked ? t.blue : t.textHi,
                ),
              ),
            ),
            Checkbox(
              value: checked,
              activeColor: t.blue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// MODULE GROUP
// ─────────────────────────────────────────────────────────────────
class _ModuleGroup extends StatefulWidget {
  final AppTheme t;
  final String groupName;
  final List<Map<String, dynamic>> groupModules;
  final String query;
  final bool showSelectedOnly;
  final bool Function(String) permOf;
  final void Function(String, bool) onToggle;
  final void Function(bool) onGroupAll;

  const _ModuleGroup({
    required this.t,
    required this.groupName,
    required this.groupModules,
    required this.query,
    required this.showSelectedOnly,
    required this.permOf,
    required this.onToggle,
    required this.onGroupAll,
  });

  @override
  State<_ModuleGroup> createState() => _ModuleGroupState();
}

class _ModuleGroupState extends State<_ModuleGroup> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;

    final visible = widget.groupModules.where((m) {
      final name = (m['module_name'] as String? ?? '').toLowerCase();
      if (widget.query.isNotEmpty && !name.contains(widget.query)) return false;
      if (widget.showSelectedOnly &&
          !widget.permOf(m['module_name'] as String? ?? '')) return false;
      return true;
    }).toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    final allOn = visible.every(
            (m) => widget.permOf(m['module_name'] as String? ?? ''));
    final anyOn = visible.any(
            (m) => widget.permOf(m['module_name'] as String? ?? ''));
    final onCount = visible
        .where((m) => widget.permOf(m['module_name'] as String? ?? ''))
        .length;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_right_rounded,
                    size: 18,
                    color: t.textLo,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.groupName,
                    style: TextStyle(
                      color: t.textHi,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: anyOn
                          ? t.blue.withOpacity(0.10)
                          : t.border.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$onCount/${visible.length}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: anyOn ? t.blue : t.textLo,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: allOn,
                      activeColor: t.blue,
                      onChanged: widget.onGroupAll,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            Divider(height: 1, thickness: 0.5, color: t.border),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: visible.map((m) {
                  final name = m['module_name'] as String? ?? '';
                  final on = widget.permOf(name);
                  return GestureDetector(
                    onTap: () => widget.onToggle(name, !on),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: on ? t.blue.withOpacity(0.10) : t.bg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: on ? t.blue.withOpacity(0.40) : t.border,
                          width: on ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (on)
                            Padding(
                              padding: const EdgeInsets.only(right: 5),
                              child: Icon(Icons.check_rounded,
                                  size: 12, color: t.blue),
                            ),
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                              on ? FontWeight.w600 : FontWeight.w400,
                              color: on ? t.blue : t.textHi,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────
// FIELD
// ─────────────────────────────────────────────────────────────────
class _Field extends StatelessWidget {
  final AppTheme t;
  final TextEditingController ctrl;
  final String label;
  final IconData icon;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;

  const _Field({
    required this.t,
    required this.ctrl,
    required this.label,
    required this.icon,
    this.keyboard,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(t: t, text: label),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl,
          validator: validator,
          keyboardType: keyboard,
          style: TextStyle(color: t.textHi, fontSize: 13),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: t.textLo, size: 17),
            filled: true,
            fillColor: t.bg,
            isDense: true,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: _ob(t.border),
            enabledBorder: _ob(t.border),
            focusedBorder: _ob(t.blue, w: 1.5),
            errorBorder: _ob(t.red),
            errorStyle: TextStyle(color: t.red, fontSize: 11),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _ob(Color c, {double w = 1.0}) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: c, width: w),
  );
}

// ─────────────────────────────────────────────────────────────────
// PASSWORD FIELD
// ─────────────────────────────────────────────────────────────────
class _PasswordField extends StatelessWidget {
  final AppTheme t;
  final TextEditingController ctrl;
  final bool obscure;
  final VoidCallback onToggle;
  final String? Function(String?)? validator;

  const _PasswordField({
    required this.t,
    required this.ctrl,
    required this.obscure,
    required this.onToggle,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionLabel(t: t, text: 'Password'),
        const SizedBox(height: 5),
        TextFormField(
          controller: ctrl,
          obscureText: obscure,
          validator: validator,
          style: TextStyle(color: t.textHi, fontSize: 13),
          decoration: InputDecoration(
            prefixIcon:
            Icon(Icons.lock_outline_rounded, color: t.textLo, size: 17),
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: t.textLo,
                size: 17,
              ),
              onPressed: onToggle,
            ),
            filled: true,
            fillColor: t.bg,
            isDense: true,
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: _ob(t.border),
            enabledBorder: _ob(t.border),
            focusedBorder: _ob(t.blue, w: 1.5),
            errorBorder: _ob(t.red),
            errorStyle: TextStyle(color: t.red, fontSize: 11),
          ),
        ),
      ],
    );
  }

  OutlineInputBorder _ob(Color c, {double w = 1.0}) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(10),
    borderSide: BorderSide(color: c, width: w),
  );
}

// ─────────────────────────────────────────────────────────────────
// SMALL HELPERS
// ─────────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final AppTheme t;
  final String text;

  const _SectionLabel({required this.t, required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: t.textLo,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  final AppTheme t;
  final bool active;
  final VoidCallback onTap;

  const _FilterToggle({required this.t, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? t.blue.withOpacity(0.10) : t.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? t.blue : t.border,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.filter_list_rounded,
                size: 16, color: active ? t.blue : t.textLo),
            const SizedBox(width: 5),
            Text(
              'Selected',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: active ? t.blue : t.textLo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final AppTheme t;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.t,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: Size.zero,
      ),
      onPressed: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final AppTheme t;
  final String message;

  const _ErrorBanner({required this.t, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: t.red.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.red.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: t.red, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: t.red, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
