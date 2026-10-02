import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/admin.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../theme/app_theme.dart';

final _dt = DateFormat('yyyy/MM/dd HH:mm');

/// A21: إعدادات المنصة غير التعاقدية. لكل إعداد قيمته الحالية والقيم المسموحة وأثره وسجل تغييراته.
/// الإعدادات لا تتجاوز حقوق الشركاء ولا تغيّر السجلات التاريخية، وتسري على ما يُنشأ بعد الحفظ.
class PlatformSettingsScreen extends StatelessWidget {
  const PlatformSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final canEdit = cs.canDo(AppModule.platformSettings, PermAction.configure);
    final categories = PlatformSetting.catalog.map((s) => s.category).toSet();

    return Scaffold(
      appBar: AppBar(title: const Text('إعدادات المنصة')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            StateBanner.readOnly('إعدادات تشغيلية لهذه الشركة. لا تغيّر بنود العقد المعتمد ولا السجلات السابقة، وتسري على ما يُنشأ بعد الحفظ.'),
            for (final cat in categories)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ExpansionTile(
                  initiallyExpanded: true,
                  title: Text(cat, style: const TextStyle(fontWeight: FontWeight.w800)),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  children: [
                    for (final s in PlatformSetting.catalog.where((x) => x.category == cat)) _SettingRow(c: c, s: s, canEdit: canEdit),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  final Company c;
  final PlatformSetting s;
  final bool canEdit;
  const _SettingRow({required this.c, required this.s, required this.canEdit});

  @override
  Widget build(BuildContext context) {
    final cs = context.read<CompanyState>();
    final v = c.setting<Object?>(s.key);
    final history = cs.audit.where((e) => e.objectType == 'settings' && e.objectId == s.key).toList();
    Widget control;
    switch (s.kind) {
      case SettingKind.toggle:
        control = Switch(
          value: v == true,
          activeThumbColor: AppColors.gold,
          onChanged: canEdit && !s.requiresService ? (x) => _save(context, x) : null,
        );
      case SettingKind.choice:
        control = DropdownButton<String>(
          value: '$v',
          dropdownColor: AppColors.navySurface,
          underline: const SizedBox.shrink(),
          items: [for (final e in s.choices!.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
          onChanged: canEdit ? (x) => _save(context, x) : null,
        );
      case SettingKind.integer:
        control = TextButton(onPressed: canEdit ? () => _editInt(context, v) : null, child: Text('$v'));
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(s.label, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700))),
          control,
        ]),
        Text(
          '${s.impact}${s.min != null ? ' القيم المسموحة: ${s.min}–${s.max}.' : ''}${s.requiresService ? ' (يتطلب خدمة غير مربوطة بعد)' : ''}',
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12, height: 1.5),
        ),
        if (history.isNotEmpty)
          Text('آخر تغيير: ${history.first.result} · ${history.first.actorName} · ${_dt.format(history.first.at.toLocal())}',
              style: const TextStyle(color: AppColors.gold, fontSize: 11.5)),
      ]),
    );
  }

  void _save(BuildContext context, Object? value) {
    final err = context.read<CompanyState>().setSetting(c.id, s.key, value);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(err ?? 'حُفظ "${s.label}" وسُجّل في سجل التدقيق.')));
  }

  Future<void> _editInt(BuildContext context, Object? v) async {
    final ctrl = TextEditingController(text: '$v');
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: AppColors.navySurface,
          title: Text(s.label),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: 'القيمة (${s.min}–${s.max})', errorText: err),
              onChanged: (_) => set(() => err = s.validate(ctrl.text)),
            ),
            const SizedBox(height: 8),
            Text('الأثر: ${s.impact}', style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            ElevatedButton(
              onPressed: () => s.validate(ctrl.text) == null ? Navigator.pop(ctx, true) : set(() => err = s.validate(ctrl.text)),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && context.mounted) _save(context, ctrl.text);
    ctrl.dispose();
  }
}
