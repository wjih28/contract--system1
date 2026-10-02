import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/admin.dart';
import '../../models/company.dart';
import '../../providers/company_state.dart';
import '../../theme/app_theme.dart';

/// A05: مصفوفة نقاط الإفصاح والتحكم. لكل نوع بيانات: من يرى ويضيف ويطبع ويرد.
/// إتاحة بيانات الشريك الشخصية لغير الشركاء لا تسري إلا بموافقة كل شريك مباشرة.
class ControlPointsScreen extends StatelessWidget {
  const ControlPointsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    return Scaffold(
      appBar: AppBar(title: const Text('نقاط الإفصاح والتحكم')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            const StateBanner(
              color: AppColors.info,
              icon: Icons.policy_rounded,
              text: 'اختر نقطة لضبط صلاحياتها. "موروث" يعني القيمة الافتراضية، و"مخصص" يعني تجاوزاً صريحاً لهذه الشركة.',
            ),
            for (final p in ControlPoint.catalog) _PointCard(c: c, p: p),
          ],
        ),
      ),
    );
  }
}

class _PointCard extends StatelessWidget {
  final Company c;
  final ControlPoint p;
  const _PointCard({required this.c, required this.p});

  @override
  Widget build(BuildContext context) {
    final overridden = c.controlPoints[p.id]?.isNotEmpty ?? false;
    final pending = [
      for (final r in CompanyRole.values)
        if (p.requiresConsent && !r.isPartner && (c.controlPoints[p.id]?[r.name]?.isNotEmpty ?? false) && !c.consentComplete(p.id, r))
          r,
    ];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ControlPointEditor(pointId: p.id))),
        title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(
          '${p.dataType} · ${overridden ? 'مخصص' : 'موروث'}'
          '${p.requiresConsent ? '\nيتطلب موافقة الشريك المباشرة لإتاحته لغير الشركاء' : ''}'
          '${pending.isEmpty ? '' : '\nبانتظار موافقة الشركاء: ${pending.map((r) => r.label).join('، ')}'}',
          style: TextStyle(color: pending.isEmpty ? AppColors.textMuted : AppColors.warning, fontSize: 12, height: 1.6),
        ),
        isThreeLine: p.requiresConsent || pending.isNotEmpty,
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: p.sensitivity.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: p.sensitivity.color.withValues(alpha: 0.5)),
          ),
          child: Text(p.sensitivity.label, style: TextStyle(color: p.sensitivity.color, fontSize: 11)),
        ),
      ),
    );
  }
}

/// محرر نقطة واحدة: صف لكل دور، وخانة لكل إجراء منطبق
class ControlPointEditor extends StatelessWidget {
  final String pointId;
  const ControlPointEditor({super.key, required this.pointId});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current!;
    final p = ControlPoint.byId(pointId);
    final canEdit = cs.canDo(AppModule.controlPoints, PermAction.configure);

    Set<PermAction> configured(CompanyRole r) {
      final o = c.controlPoints[p.id]?[r.name];
      return o == null ? (p.defaults[r] ?? const {}) : o.map(PermAction.values.byName).toSet();
    }

    return Scaffold(
      appBar: AppBar(title: Text(p.label)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            if (p.requiresConsent)
              const StateBanner(
                color: AppColors.warning,
                icon: Icons.how_to_reg_rounded,
                text: 'بيانات شخصية للشريك: إتاحتها لدور من غير الشركاء تُرسل طلب موافقة لكل شريك، ولا تسري حتى يوافقوا جميعاً.',
              ),
            for (final r in CompanyRole.values)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(r.label, style: const TextStyle(fontWeight: FontWeight.w800))),
                      Text(
                        c.controlPoints[p.id]?.containsKey(r.name) ?? false ? 'تجاوز صريح' : 'موروث',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5),
                      ),
                    ]),
                    Wrap(spacing: 6, children: [
                      for (final a in p.actions)
                        FilterChip(
                          label: Text(a.label),
                          selected: configured(r).contains(a),
                          onSelected: canEdit
                              ? (v) {
                                  final next = {...configured(r)};
                                  v ? next.add(a) : next.remove(a);
                                  if (a == PermAction.view && !v) next.clear();
                                  if (a != PermAction.view && v) next.add(PermAction.view);
                                  cs.saveControlPoint(c.id, p.id, r, next);
                                }
                              : null,
                        ),
                    ]),
                    if (p.requiresConsent && !r.isPartner && configured(r).isNotEmpty)
                      Text(
                        c.consentComplete(p.id, r)
                            ? 'وافق كل الشركاء: الإتاحة سارية'
                            : 'بانتظار موافقة ${c.partners.where((x) => !(c.consents['${p.id}|${r.name}']?.containsKey(x.id) ?? false)).map((x) => x.name).join('، ')}. لا تسري قبلها.',
                        style: TextStyle(
                            color: c.consentComplete(p.id, r) ? AppColors.success : AppColors.warning, fontSize: 12),
                      ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
