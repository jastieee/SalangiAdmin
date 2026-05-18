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
Color get _teal => _t.teal;
Color get _textHi => _t.textHi;
Color get _textLo => _t.textLo;

int toInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

String toStr(dynamic v) => v?.toString() ?? '';

class LocationManagementScreen extends StatefulWidget {
  final Map<String, dynamic>? currentUser;

  const LocationManagementScreen({
    super.key,
    this.currentUser,
  });

  @override
  State<LocationManagementScreen> createState() =>
      _LocationManagementScreenState();
}

class _LocationManagementScreenState extends State<LocationManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  bool _loading = true;
  String? _error;

  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _warehouses = [];

  List<Map<String, dynamic>> get _permissions {
    final rawAdmin = widget.currentUser?['admin_modules'];
    final rawAll = widget.currentUser?['permissions'];
    final raw = rawAdmin is List ? rawAdmin : rawAll;

    return (raw as List?)
        ?.whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList() ??
        [];
  }

  bool hasPermission(String moduleName) {
    return _permissions.any((p) {
      final name = toStr(p['module_name']).trim().toUpperCase();
      final canAccess = p['can_access'] == true ||
          p['can_access'] == 1 ||
          toStr(p['can_access']) == '1';

      return name == moduleName.trim().toUpperCase() && canAccess;
    });
  }

  bool get canView => hasPermission('LOCATION_VIEW');
  bool get canCreate => hasPermission('LOCATION_CREATE');
  bool get canEdit => hasPermission('LOCATION_EDIT');
  bool get canDelete => hasPermission('LOCATION_DELETE');

  @override
  void initState() {
    super.initState();
    _load();
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

  Future<void> _load() async {
    if (!canView) {
      setState(() {
        _loading = false;
        _error = 'You do not have permission to view locations.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final result = await DBService.instance.fetchStoresWarehouses();

    if (!mounted) return;

    if (result.success) {
      setState(() {
        _stores = _toList(result.data?['stores']);
        _warehouses = _toList(result.data?['warehouses']);
        _loading = false;
      });
    } else {
      setState(() {
        _error = result.message;
        _loading = false;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? _red : _green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openForm({
    required String type,
    Map<String, dynamic>? existing,
  }) async {
    if (existing == null && !canCreate) {
      _snack('You do not have permission to create locations.', error: true);
      return;
    }

    if (existing != null && !canEdit) {
      _snack('You do not have permission to edit locations.', error: true);
      return;
    }

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _LocationFormDialog(
        type: type,
        existing: existing,
      ),
    );

    if (ok == true) {
      _snack('${type == 'store' ? 'Store' : 'Warehouse'} saved.');
      _load();
    }
  }

  Future<void> _delete({
    required String type,
    required Map<String, dynamic> item,
  }) async {
    if (!canDelete) {
      _snack('You do not have permission to delete locations.', error: true);
      return;
    }

    final id =
    type == 'store' ? toInt(item['store_id']) : toInt(item['warehouse_id']);

    final name = type == 'store'
        ? toStr(item['store_name'])
        : toStr(item['warehouse_name']);

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          'Delete ${type == 'store' ? 'Store' : 'Warehouse'}',
          style: TextStyle(color: _textHi, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'Delete "$name"? This may fail if it is already used in inventory, users, or transfers.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final result = await DBService.instance.deleteLocation(type: type, id: id);

    if (!mounted) return;

    if (result.success) {
      _snack(result.message.isEmpty ? 'Deleted.' : result.message);
      _load();
    } else {
      _snack(result.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Center(child: CircularProgressIndicator(color: _blue));

    if (_error != null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error!,
              style: TextStyle(color: _red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
           child:  Row(
              children: [
                Expanded(                              // ← ADD THIS
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Store & Warehouse Management',
                        style: TextStyle(
                          color: _textHi,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,   // ← ADD THIS
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Add and manage store/warehouse names and addresses',
                        style: TextStyle(color: _textLo, fontSize: 12),
                        overflow: TextOverflow.ellipsis,   // ← ADD THIS
                      ),
                    ],
                  ),
                ),                                     // ← CLOSE Expanded
                // const Spacer(),  ← REMOVE THIS (Expanded replaces it)
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _load,
                  icon: Icon(Icons.refresh_rounded, color: _textLo),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: TabBar(
                controller: _tabs,
                indicator: BoxDecoration(
                  color: _blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _blue.withOpacity(0.4)),
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                dividerColor: Colors.transparent,
                labelColor: _blue,
                unselectedLabelColor: _textLo,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.storefront_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Stores'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warehouse_rounded, size: 16),
                        SizedBox(width: 6),
                        Text('Warehouses'),
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
                _LocationTab(
                  type: 'store',
                  items: _stores,
                  canCreate: canCreate,
                  canEdit: canEdit,
                  canDelete: canDelete,
                  onAdd: () => _openForm(type: 'store'),
                  onEdit: (item) => _openForm(type: 'store', existing: item),
                  onDelete: (item) => _delete(type: 'store', item: item),
                ),
                _LocationTab(
                  type: 'warehouse',
                  items: _warehouses,
                  canCreate: canCreate,
                  canEdit: canEdit,
                  canDelete: canDelete,
                  onAdd: () => _openForm(type: 'warehouse'),
                  onEdit: (item) =>
                      _openForm(type: 'warehouse', existing: item),
                  onDelete: (item) => _delete(type: 'warehouse', item: item),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationTab extends StatelessWidget {
  final String type;
  final List<Map<String, dynamic>> items;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onAdd;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;

  const _LocationTab({
    required this.type,
    required this.items,
    required this.canCreate,
    required this.canEdit,
    required this.canDelete,
    required this.onAdd,
    required this.onEdit,
    required this.onDelete,
  });

  bool get _isStore => type == 'store';

  @override
  Widget build(BuildContext context) {
    final color = _isStore ? _green : _teal;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                _isStore ? 'Stores' : 'Warehouses',
                style: TextStyle(
                  color: _textHi,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              if (canCreate)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: color,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text(_isStore ? 'Add Store' : 'Add Warehouse'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border),
              ),
              child: items.isEmpty
                  ? Center(
                child: Text(
                  _isStore ? 'No stores found.' : 'No warehouses found.',
                  style: TextStyle(color: _textLo),
                ),
              )
                  : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: _border),
                itemBuilder: (_, i) {
                  final item = items[i];

                  final name = _isStore
                      ? toStr(item['store_name'])
                      : toStr(item['warehouse_name']);

                  final address = _isStore
                      ? (toStr(item['address']).isNotEmpty
                      ? toStr(item['address'])
                      : toStr(item['store_address']))
                      : (toStr(item['address']).isNotEmpty
                      ? toStr(item['address'])
                      : toStr(item['warehouse_address']));

                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    leading: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: color.withOpacity(0.35)),
                      ),
                      child: Icon(
                        _isStore
                            ? Icons.storefront_rounded
                            : Icons.warehouse_rounded,
                        color: color,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      name,
                      style: TextStyle(
                        color: _textHi,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      address.trim().isEmpty ? 'No address' : address,
                      style: TextStyle(color: _textLo, fontSize: 12),
                    ),
                    trailing: SizedBox(
                      width: 96,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (canEdit)
                            IconButton(
                              tooltip: 'Edit',
                              onPressed: () => onEdit(item),
                              icon: Icon(
                                Icons.edit_rounded,
                                color: _blue,
                                size: 18,
                              ),
                            ),
                          if (canDelete)
                            IconButton(
                              tooltip: 'Delete',
                              onPressed: () => onDelete(item),
                              icon: Icon(
                                Icons.delete_rounded,
                                color: _red,
                                size: 18,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationFormDialog extends StatefulWidget {
  final String type;
  final Map<String, dynamic>? existing;

  const _LocationFormDialog({
    required this.type,
    this.existing,
  });

  @override
  State<_LocationFormDialog> createState() => _LocationFormDialogState();
}

class _LocationFormDialogState extends State<_LocationFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _nameCtrl;
  late final TextEditingController _addressCtrl;

  bool _saving = false;
  String? _error;

  bool get _isStore => widget.type == 'store';
  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();

    final item = widget.existing;

    _nameCtrl = TextEditingController(
      text: _isStore
          ? toStr(item?['store_name'])
          : toStr(item?['warehouse_name']),
    );

    _addressCtrl = TextEditingController(
      text: toStr(item?['address']).isNotEmpty
          ? toStr(item?['address'])
          : (_isStore
          ? toStr(item?['store_address'])
          : toStr(item?['warehouse_address'])),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final id = _isEdit
        ? (_isStore
        ? toInt(widget.existing?['store_id'])
        : toInt(widget.existing?['warehouse_id']))
        : null;

    final result = await DBService.instance.saveLocation(
      type: widget.type,
      id: id,
      name: _nameCtrl.text.trim(),
      address: _addressCtrl.text.trim(),
    );

    if (!mounted) return;

    if (result.success) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _saving = false;
        _error = result.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _isStore ? _green : _teal;
    final label = _isStore ? 'Store' : 'Warehouse';

    return Dialog(
      backgroundColor: _surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(26),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      _isStore
                          ? Icons.storefront_rounded
                          : Icons.warehouse_rounded,
                      color: color,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${_isEdit ? 'Edit' : 'Add'} $label',
                      style: TextStyle(
                        color: _textHi,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed:
                      _saving ? null : () => Navigator.pop(context, false),
                      icon: Icon(Icons.close_rounded, color: _textLo),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameCtrl,
                  style: TextStyle(color: _textHi),
                  validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Name is required' : null,
                  decoration: _inputDecoration(
                    label: '$label Name',
                    icon: _isStore
                        ? Icons.storefront_rounded
                        : Icons.warehouse_rounded,
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _addressCtrl,
                  style: TextStyle(color: _textHi),
                  maxLines: 2,
                  decoration: _inputDecoration(
                    label: '$label Address',
                    icon: Icons.location_on_outlined,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 14),
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
                          child: Text(
                            _error!,
                            style: TextStyle(color: _red, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: _border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        onPressed:
                        _saving ? null : () => Navigator.pop(context, false),
                        child: Text('Cancel', style: TextStyle(color: _textLo)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: color,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 14),
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
                            : Text(_isEdit ? 'Save Changes' : 'Add $label'),
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

  InputDecoration _inputDecoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: _textLo),
      prefixIcon: Icon(icon, color: _textLo, size: 18),
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
    );
  }
}