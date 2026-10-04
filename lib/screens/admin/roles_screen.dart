import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/admin.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../theme/app_theme.dart';

final _dt = DateFormat('yyyy/MM/dd HH:mm');

/// A04: الأدوار والصلاحيات. مصفوفة الوحدات والإجراءات لكل دور، مع معاينة الأثر قبل الحفظ،
/// وسجل التغييرات للقراءة فقط. حقوق الشريك الأساسية مقفلة ولا يمكن نزعها.
class RolesScreen extends StatefulWidget {
  final CompanyRole? initialRole;
  const RolesScreen({super.key, this.initialRole});

  @override
  State<RolesScreen> createState() => _RolesScreenState();
}

class _RolesScreenState extends State<RolesScreen> {
  late CompanyRole _role = widget.initialRole ?? CompanyRole.partner;
  Map<AppModule, Set<PermAction>>? _draft;

  Map<AppModule, Set<PermAction>> _current(Company c) =>
      {for (final m in AppModule.values) m: Permissions.actionsFor(_role, m, c)};

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    // صلاحيات دوري الشريك والشريك المدير يحددها العقد: عرض فقط
    final canEdit = cs.canDo(AppModule.roles, PermAction.configure) && !_role.isPartner;
    final saved = _current(c);
    final draft = _draft ?? saved;
    final dirty = _draft != null && AppModule.values.any((m) => !_same(_draft![m]!, saved[m]!));
    final history = cs.audit.where((e) => e.objectType == 'permissions' && e.objectId == _role.name).toList();
    // الوحدات التي يملك عليها الدور إجراء افتراضياً أو مخصصاً، ثم البقية
    final modules = AppModule.values.toList()
      ..sort((a, b) => (draft[b]!.isNotEmpty ? 1 : 0).compareTo(draft[a]!.isNotEmpty ? 1 : 0));

    return Scaffold(
      appBar: AppBar(title: const Text('الأدوار والصلاحيات')),
      bottomNavigationBar: dirty
          ? SafeArea(
              child: Container(
                color: AppColors.navyMedium,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                child: Row(children: [
                  const Expanded(child: Text('تغييرات غير محفوظة', style: TextStyle(color: AppColors.warning))),
                  TextButton(onPressed: () => setState(() => _draft = null), child: const Text('تراجع')),
                  const SizedBox(width: 8),
                  ElevatedButton(onPressed: () => _preview(context, c, saved, _draft!), child: const Text('معاينة الأثر والحفظ')),
                ]),
              ),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            const StateBanner(
              color: AppColors.info,
              icon: Icons.lock_outline_rounded,
              text: 'الخانات المقفلة حقوق أساسية للشريك (التصويت، الاطلاع على العقد، النزاعات، السجل) ولا يمكن نزعها من الإدارة. '
                  'الصلاحية التقنية لا تمنح سلطة تجارية.',
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final r in CompanyRole.values)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(r.label),
                      selected: _role == r,
                      onSelected: (_) => _switchRole(r, dirty),
                    ),
                  ),
              ]),
            ),
            if (_role.isPartner)
              const StateBanner(
                color: AppColors.warning,
                icon: Icons.gavel_rounded,
                text: CompanyState.partnerRoleLocked,
              ),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(
                child: Text('${_role.portal.label}${c.permissions.containsKey(_role.name) ? ' · مخصص لهذه الشركة' : ' · الافتراضي'}',
                    style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
              ),
              if (canEdit && c.permissions.containsKey(_role.name))
                TextButton.icon(
                  onPressed: () {
                    cs.resetPermissions(c.id, _role);
                    setState(() => _draft = null);
                  },
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: const Text('استعادة الافتراضي'),
                ),
            ]),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                color: AppColors.navySurface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 40,
                  dataRowMinHeight: 40,
                  dataRowMaxHeight: 48,
                  columnSpacing: 14,
                  horizontalMargin: 12,
                  columns: [
                    const DataColumn(label: Text('الوحدة', style: TextStyle(fontWeight: FontWeight.w800))),
                    for (final a in PermAction.values) DataColumn(label: Text(a.label, style: const TextStyle(fontSize: 12))),
                  ],
                  rows: [
                    for (final m in modules)
                      DataRow(cells: [
                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(m.icon, size: 16, color: draft[m]!.isEmpty ? AppColors.textMuted : AppColors.gold),
                          const SizedBox(width: 6),
                          Text(m.label, style: const TextStyle(fontSize: 12.5)),
                        ])),
                        for (final a in PermAction.values) DataCell(_cell(c, m, a, draft, canEdit)),
                      ]),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            GovCard(
              title: 'سجل تغييرات هذا الدور',
              icon: Icons.history_rounded,
              child: history.isEmpty
                  ? const Text('لم تُعدَّل صلاحيات هذا الدور بعد.', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5))
                  : Column(children: [
                      for (final e in history)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(e.action, style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${e.actorName} · ${_dt.format(e.at.toLocal())}\n${e.result}',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5, height: 1.5)),
                        ),
                    ]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(Company c, AppModule m, PermAction a, Map<AppModule, Set<PermAction>> draft, bool canEdit) {
    final locked = Permissions.lockedActions(_role, m).contains(a);
    final on = draft[m]!.contains(a);
    if (locked) {
      return const Tooltip(message: 'حق أساسي مقفل', child: Icon(Icons.lock_rounded, size: 18, color: AppColors.gold));
    }
    return Checkbox(
      value: on,
      activeColor: AppColors.gold,
      onChanged: canEdit
          ? (v) => setState(() {
                final d = {for (final e in (_draft ?? _current(c)).entries) e.key: {...e.value}};
                v == true ? d[m]!.add(a) : d[m]!.remove(a);
                // العرض شرط لأي إجراء آخر
                if (a == PermAction.view && v != true) d[m]!.clear();
                if (a != PermAction.view && v == true) d[m]!.add(PermAction.view);
                _draft = d;
              })
          : null,
    );
  }

  void _switchRole(CompanyRole r, bool dirty) {
    if (dirty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('احفظ التغييرات أو تراجع عنها أولاً.')));
      return;
    }
    setState(() {
      _role = r;
      _draft = null;
    });
  }

  static bool _same(Set<PermAction> a, Set<PermAction> b) => a.length == b.length && a.containsAll(b);

  Future<void> _preview(BuildContext context, Company c, Map<AppModule, Set<PermAction>> saved,
      Map<AppModule, Set<PermAction>> draft) async {
    final lines = <(String, bool)>[];
    for (final m in AppModule.values) {
      final add = draft[m]!.difference(saved[m]!), rem = saved[m]!.difference(draft[m]!);
      if (add.isNotEmpty) lines.add(('${m.label}: إضافة ${add.map((a) => a.label).join('، ')}', true));
      if (rem.isNotEmpty) lines.add(('${m.label}: إزالة ${rem.map((a) => a.label).join('، ')}', false));
    }
    final affected = c.members.where((x) => x.roles.contains(_role) && x.active).map((x) => x.name).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.navySurface,
        title: Text('أثر تعديل صلاحيات ${_role.label}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(affected.isEmpty ? 'لا يوجد عضو بهذا الدور حالياً.' : 'يتأثر: ${affected.join('، ')}',
                style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            for (final (t, add) in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(add ? Icons.add_circle_outline_rounded : Icons.remove_circle_outline_rounded,
                      size: 16, color: add ? AppColors.success : AppColors.danger),
                  const SizedBox(width: 6),
                  Expanded(child: Text(t, style: const TextStyle(fontSize: 13))),
                ]),
              ),
            const SizedBox(height: 8),
            const Text('يُسجَّل التغيير في سجل التدقيق ويسري فوراً.', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('رجوع')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok == true && context.mounted) {
      context.read<CompanyState>().savePermissions(c.id, _role, draft);
      setState(() => _draft = null);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('حُفظت صلاحيات ${_role.label} (${lines.length} تغييرات).')));
    }
  }
}
