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

class _UserManagementScreenState extends State<UserManagementScreen> {
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
      final canAccess =
          p['can_access'] == true ||
              p['can_access'] == 1 ||
              p['can_access'].toString() == '1';

      return name == moduleName.trim().toUpperCase() && canAccess;
    });
  }

  bool get canViewUsers => hasPermission('USER_VIEW');
  bool get canCreateUsers => hasPermission('USER_CREATE');
  bool get canEditUsers => hasPermission('USER_EDIT');
  bool get canDeleteUsers => hasPermission('USER_DELETE');

  bool _isWide(BuildContext context) {
    return MediaQuery.of(context).size.width >= 900;
  }

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  List<Map<String, dynamic>> _toList(dynamic v) {
    return (v as List?)
        ?.map((e) => Map<String, dynamic>.from(e as Map))
        .toList() ??
        [];
  }

  Future<void> _loadUsers() async {
    if (!canViewUsers) {
      setState(() {
        _loading = false;
        _error = 'You do not have permission to view users.';
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
      builder: (_) => _UserFormDialog(
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

        return Scaffold(
          backgroundColor: t.bg,
          body: SafeArea(
            child: RefreshIndicator(
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
            ),
          ),
        );
      },
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
// CREATE / EDIT DIALOG
// ────────────────────────────────────────────────────
class _UserFormDialog extends StatefulWidget {
  final Map<String, dynamic>? existing;
  final List<Map<String, dynamic>> roles;
  final List<Map<String, dynamic>> modules;
  final List<Map<String, dynamic>> stores;
  final List<Map<String, dynamic>> warehouses;
  final int currentUserId;

  const _UserFormDialog({
    this.existing,
    required this.roles,
    required this.modules,
    required this.stores,
    required this.warehouses,
    required this.currentUserId,
  });

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _username;
  late TextEditingController _password;
  late TextEditingController _fullName;
  late TextEditingController _email;

  int? _selectedRoleId;
  int? _selectedStoreId;
  int? _selectedWarehouseId;

  Map<int, bool> _perms = {};

  bool _saving = false;
  bool _obscurePass = true;
  String? _errorMsg;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final e = widget.existing;

    _username = TextEditingController(text: e?['username'] ?? '');
    _password = TextEditingController();
    _fullName = TextEditingController(text: e?['full_name'] ?? '');
    _email = TextEditingController(text: e?['email'] ?? '');

    _selectedRoleId = e?['role_id'] as int?;
    _selectedStoreId = e?['store_id'] as int?;
    _selectedWarehouseId = e?['warehouse_id'] as int?;

    if (e != null) {
      final rawPerms = e['permissions'] as List? ?? [];

      for (final p in rawPerms) {
        final map = Map<String, dynamic>.from(p as Map);
        _perms[map['module_id'] as int] = map['can_access'] as bool? ?? false;
      }

      for (final m in widget.modules) {
        final id = m['module_id'] as int;
        _perms.putIfAbsent(id, () => false);
      }
    } else {
      for (final m in widget.modules) {
        _perms[m['module_id'] as int] = false;
      }
    }
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _fullName.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedRoleId == null) {
      setState(() => _errorMsg = 'Please select a role');
      return;
    }

    setState(() {
      _saving = true;
      _errorMsg = null;
    });

    final permsList = _perms.entries
        .map((e) => {
      'module_id': e.key,
      'can_access': e.value,
    })
        .toList();

    DBResult result;

    if (_isEdit) {
      result = await DBService.instance.updateUser(
        userId: widget.existing!['user_id'] as int,
        fullName: _fullName.text.trim(),
        email: _email.text.trim(),
        roleId: _selectedRoleId,
        storeId: _selectedStoreId,
        warehouseId: _selectedWarehouseId,
        permissions: permsList,
        performedBy: widget.currentUserId,
      );
    } else {
      result = await DBService.instance.createUser(
        username: _username.text.trim(),
        password: _password.text,
        fullName: _fullName.text.trim(),
        email: _email.text.trim(),
        storeId: _selectedStoreId,
        warehouseId: _selectedWarehouseId,
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

  @override
  Widget build(BuildContext context) {
    final t = themeNotifier.theme;
    final sw = MediaQuery.of(context).size.width;
    final wide = sw >= 760;

    final dialogWidth = sw >= 1000
        ? 720.0
        : sw >= 760
        ? 640.0
        : sw * 0.94;

    return Dialog(
      backgroundColor: t.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(wide ? 28 : 18),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: t.blue.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: t.blue.withOpacity(0.25)),
                      ),
                      child: Icon(
                        _isEdit
                            ? Icons.edit_rounded
                            : Icons.person_add_rounded,
                        color: t.blue,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _isEdit ? 'Edit User' : 'Create User',
                      style: TextStyle(
                        color: t.textHi,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: t.textLo,
                        size: 20,
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                wide
                    ? Row(
                  children: [
                    Expanded(
                      child: _field(
                        t,
                        _fullName,
                        'Full Name',
                        Icons.badge_rounded,
                        validator: (v) =>
                        (v?.trim().isEmpty ?? true)
                            ? 'Required'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _field(
                        t,
                        _email,
                        'Email',
                        Icons.email_outlined,
                      ),
                    ),
                  ],
                )
                    : Column(
                  children: [
                    _field(
                      t,
                      _fullName,
                      'Full Name',
                      Icons.badge_rounded,
                      validator: (v) =>
                      (v?.trim().isEmpty ?? true)
                          ? 'Required'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    _field(
                      t,
                      _email,
                      'Email',
                      Icons.email_outlined,
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                if (!_isEdit) ...[
                  wide
                      ? Row(
                    children: [
                      Expanded(
                        child: _field(
                          t,
                          _username,
                          'Username',
                          Icons.person_outline_rounded,
                          validator: (v) =>
                          (v?.trim().isEmpty ?? true)
                              ? 'Required'
                              : null,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _field(
                          t,
                          _password,
                          'Password',
                          Icons.lock_outline_rounded,
                          obscure: true,
                          validator: (v) =>
                          (v?.isEmpty ?? true) ? 'Required' : null,
                        ),
                      ),
                    ],
                  )
                      : Column(
                    children: [
                      _field(
                        t,
                        _username,
                        'Username',
                        Icons.person_outline_rounded,
                        validator: (v) =>
                        (v?.trim().isEmpty ?? true)
                            ? 'Required'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _field(
                        t,
                        _password,
                        'Password',
                        Icons.lock_outline_rounded,
                        obscure: true,
                        validator: (v) =>
                        (v?.isEmpty ?? true) ? 'Required' : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],

                wide
                    ? Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _roleDropdown(t)),
                        const SizedBox(width: 12),
                        Expanded(child: _storeDropdown(t)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _warehouseDropdown(t)),
                        const SizedBox(width: 12),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                )
                    : Column(
                  children: [
                    _roleDropdown(t),
                    const SizedBox(height: 12),
                    _storeDropdown(t),
                    const SizedBox(height: 12),
                    _warehouseDropdown(t),
                  ],
                ),

                const SizedBox(height: 16),

                _PermissionDropdownPanel(
                  t: t,
                  modules: widget.modules,
                  perms: _perms,
                  onChanged: () => setState(() {}),
                ),

                if (_errorMsg != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: t.red.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.red.withOpacity(0.25)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: t.red, size: 15),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMsg!,
                            style: TextStyle(color: t.red, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 24),

                wide
                    ? Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: _actionButtons(t),
                )
                    : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: t.blue,
                        foregroundColor: Colors.white,
                        padding:
                        const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                          : Text(
                        _isEdit ? 'Save Changes' : 'Create User',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text(
                        'Cancel',
                        style: TextStyle(color: t.textLo),
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
  }

  List<Widget> _actionButtons(AppTheme t) {
    return [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: Text(
          'Cancel',
          style: TextStyle(color: t.textLo),
        ),
      ),
      const SizedBox(width: 10),
      FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: t.blue,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        onPressed: _saving ? null : _submit,
        child: _saving
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Colors.white,
          ),
        )
            : Text(_isEdit ? 'Save Changes' : 'Create User'),
      ),
    ];
  }

  Widget _roleDropdown(AppTheme t) {
    return _ThemedDropdown<int>(
      t: t,
      label: 'Role',
      icon: Icons.admin_panel_settings_rounded,
      value: _selectedRoleId,
      validator: (v) => v == null ? 'Please select a role' : null,
      items: widget.roles.map((r) {
        return DropdownMenuItem<int>(
          value: r['role_id'] as int,
          child: Text(r['role_name'] as String? ?? ''),
        );
      }).toList(),
      onChanged: (v) => setState(() => _selectedRoleId = v),
    );
  }

  Widget _storeDropdown(AppTheme t) {
    return _ThemedDropdown<int?>(
      t: t,
      label: 'Assigned Store',
      icon: Icons.store_rounded,
      value: _selectedStoreId,
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('None'),
        ),
        ...widget.stores.map((s) {
          return DropdownMenuItem<int?>(
            value: s['store_id'] as int,
            child: Text(s['store_name'] as String? ?? ''),
          );
        }),
      ],
      onChanged: (v) => setState(() => _selectedStoreId = v),
    );
  }

  Widget _warehouseDropdown(AppTheme t) {
    return _ThemedDropdown<int?>(
      t: t,
      label: 'Assigned Warehouse',
      icon: Icons.warehouse_rounded,
      value: _selectedWarehouseId,
      items: [
        const DropdownMenuItem<int?>(
          value: null,
          child: Text('None'),
        ),
        ...widget.warehouses.map((w) {
          return DropdownMenuItem<int?>(
            value: w['warehouse_id'] as int,
            child: Text(w['warehouse_name'] as String? ?? ''),
          );
        }),
      ],
      onChanged: (v) => setState(() => _selectedWarehouseId = v),
    );
  }

  Widget _field(
      AppTheme t,
      TextEditingController ctrl,
      String label,
      IconData icon, {
        bool obscure = false,
        String? Function(String?)? validator,
      }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label(t: t, text: label),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          obscureText: obscure && _obscurePass,
          validator: validator,
          style: TextStyle(color: t.textHi, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: t.textLo, size: 18),
            suffixIcon: obscure
                ? IconButton(
              icon: Icon(
                _obscurePass
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: t.textLo,
                size: 18,
              ),
              onPressed: () {
                setState(() => _obscurePass = !_obscurePass);
              },
            )
                : null,
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
            errorStyle: TextStyle(color: t.red, fontSize: 11),
            contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          ),
        ),
      ],
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

class _PermissionDropdownPanel extends StatelessWidget {
  final AppTheme t;
  final List<Map<String, dynamic>> modules;
  final Map<int, bool> perms;
  final VoidCallback onChanged;

  const _PermissionDropdownPanel({
    required this.t,
    required this.modules,
    required this.perms,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final grantedIds = perms.entries.where((e) => e.value).map((e) => e.key).toSet();
    final grantedModules = modules.where((m) => grantedIds.contains(m['module_id'])).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.apps_rounded, color: t.textLo, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Module Permissions',
                  style: TextStyle(
                    color: t.textHi,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${grantedModules.length} / ${modules.length}',
                style: TextStyle(color: t.textLo, fontSize: 12),
              ),
            ],
          ),

          const SizedBox(height: 10),

          if (grantedModules.isEmpty)
            Text(
              'No modules selected',
              style: TextStyle(color: t.textLo, fontSize: 12),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: grantedModules.take(8).map((m) {
                return Chip(
                  label: Text(
                    m['module_name']?.toString() ?? '',
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: t.blue.withOpacity(0.10),
                  side: BorderSide(color: t.blue.withOpacity(0.25)),
                  labelStyle: TextStyle(color: t.blue),
                );
              }).toList()
                ..addAll(
                  grantedModules.length > 8
                      ? [
                    Chip(
                      label: Text(
                        '+${grantedModules.length - 8} more',
                        style: TextStyle(fontSize: 11, color: t.textLo),
                      ),
                      visualDensity: VisualDensity.compact,
                      backgroundColor: t.surface,
                      side: BorderSide(color: t.border),
                    )
                  ]
                      : [],
                ),
            ),

          const SizedBox(height: 12),

          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.blue,
                    side: BorderSide(color: t.blue.withOpacity(0.35)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('Search / Manage Modules'),
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (_) => _ModulePermissionPickerDialog(
                        t: t,
                        modules: modules,
                        perms: perms,
                        onChanged: onChanged,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ModulePermissionPickerDialog extends StatefulWidget {
  final AppTheme t;
  final List<Map<String, dynamic>> modules;
  final Map<int, bool> perms;
  final VoidCallback onChanged;

  const _ModulePermissionPickerDialog({
    required this.t,
    required this.modules,
    required this.perms,
    required this.onChanged,
  });

  @override
  State<_ModulePermissionPickerDialog> createState() =>
      _ModulePermissionPickerDialogState();
}

class _ModulePermissionPickerDialogState
    extends State<_ModulePermissionPickerDialog> {
  String _query = '';
  bool _showSelectedOnly = false;

  List<Map<String, dynamic>> get _filtered {
    final q = _query.trim().toLowerCase();

    return widget.modules.where((m) {
      final id = m['module_id'] as int;
      final name = m['module_name']?.toString().toLowerCase() ?? '';
      final selected = widget.perms[id] ?? false;

      if (_showSelectedOnly && !selected) return false;
      return q.isEmpty || name.contains(q);
    }).toList();
  }

  void _setAll(bool value) {
    for (final m in _filtered) {
      final id = m['module_id'] as int;
      widget.perms[id] = value;
    }
    widget.onChanged();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final selectedCount = widget.perms.values.where((v) => v).length;

    return Dialog(
      backgroundColor: t.surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Row(
                children: [
                  Icon(Icons.apps_rounded, color: t.blue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Select Modules',
                      style: TextStyle(
                        color: t.textHi,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close_rounded, color: t.textLo),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              TextField(
                autofocus: true,
                style: TextStyle(color: t.textHi, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search module name...',
                  hintStyle: TextStyle(color: t.textLo, fontSize: 13),
                  prefixIcon: Icon(Icons.search_rounded, color: t.textLo),
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
                ),
                onChanged: (v) => setState(() => _query = v),
              ),

              const SizedBox(height: 10),

              Row(
                children: [
                  Text(
                    '$selectedCount selected',
                    style: TextStyle(color: t.textLo, fontSize: 12),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() {
                      _showSelectedOnly = !_showSelectedOnly;
                    }),
                    child: Text(
                      _showSelectedOnly ? 'Show All' : 'Selected Only',
                      style: TextStyle(color: t.blue),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _setAll(true),
                    child: Text('Allow Filtered', style: TextStyle(color: t.green)),
                  ),
                  TextButton(
                    onPressed: () => _setAll(false),
                    child: Text('Clear Filtered', style: TextStyle(color: t.red)),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              Expanded(
                child: _filtered.isEmpty
                    ? Center(
                  child: Text(
                    'No modules found',
                    style: TextStyle(color: t.textLo),
                  ),
                )
                    : GridView.builder(
                  itemCount: _filtered.length,
                  gridDelegate:
                  const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 260,
                    mainAxisExtent: 52,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (_, i) {
                    final m = _filtered[i];
                    final id = m['module_id'] as int;
                    final name = m['module_name']?.toString() ?? '';
                    final checked = widget.perms[id] ?? false;

                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        widget.perms[id] = !checked;
                        widget.onChanged();
                        setState(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: checked
                              ? t.blue.withOpacity(0.10)
                              : t.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: checked
                                ? t.blue.withOpacity(0.45)
                                : t.border,
                          ),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: checked,
                              activeColor: t.blue,
                              checkColor: Colors.white,
                              onChanged: (v) {
                                widget.perms[id] = v ?? false;
                                widget.onChanged();
                                setState(() {});
                              },
                            ),
                            Expanded(
                              child: Text(
                                name,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.textHi,
                                  fontSize: 12,
                                  fontWeight: checked
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: t.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
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