import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/family.dart';
import '../../providers/company_state.dart';
import '../../providers/family_state.dart';
import '../../theme/app_theme.dart';
import '../operations/tx_widgets.dart';
import 'constitution_screen.dart';
import 'distribution_succession_screens.dart';
import 'family_decisions_screen.dart';
import 'family_tree_screen.dart';

/// R09: لوحة الحوكمة العائلية. حالة الدستور، والورثة والخلافة، ودورة التوزيع، والقرارات المعلّقة.
class FamilyDashboardScreen extends StatelessWidget {
  const FamilyDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final f = context.watch<FamilyState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    if (!c.familyEnabled) {
      return const Scaffold(body: StateView.empty(icon: Icons.family_restroom_rounded, title: 'الحوكمة العائلية غير مفعّلة', message: ''));
    }
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final cur = f.current(c.id);
    final draft = f.pendingDraft(c.id);
    final open = f.decisionsFor(c.id).where((d) => d.status == FamilyDecisionStatus.open).toList();
    final heirs = f.peopleFor(c.id).where((p) => p.role == SuccessionRole.heir).length;
    final succ = f.successionsFor(c.id).where((x) => x.status != SuccessionStatus.effective && x.status != SuccessionStatus.rejected).length;
    final lastDist = f.distributionsFor(c.id).firstOrNull;
    final events = cs.audit.where((e) => e.objectType == 'family').take(6).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('الحوكمة العائلية')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            StateBanner.readOnly('بيانات عائلية مقيدة. الدستور العائلي منفصل عن عقد التأسيس، وأي أثر على الحصص يتم بإصدار جديد للعقد.'),
            KpiGrid(items: [
              (w) => KpiCard(
                  label: draft == null ? 'الدستور العائلي' : 'الدستور · يوجد ${draft.status.label}',
                  value: cur == null ? 'لم يُعتمد' : 'الإصدار ${cur.version}',
                  icon: Icons.menu_book_rounded,
                  color: cur == null ? AppColors.warning : AppColors.success,
                  width: w,
                  onTap: () => go(const ConstitutionScreen())),
              (w) => KpiCard(
                  label: 'قرارات بانتظار التصويت',
                  value: '${open.length}',
                  icon: Icons.how_to_vote_outlined,
                  color: open.isEmpty ? AppColors.textMuted : AppColors.info,
                  width: w,
                  onTap: () => go(const FamilyDecisionsScreen())),
              (w) => KpiCard(
                  label: 'الورثة المعتمدون · خلافة جارية $succ',
                  value: '$heirs',
                  icon: Icons.account_tree_rounded,
                  color: AppColors.gold,
                  width: w,
                  onTap: () => go(const FamilyTreeScreen())),
              (w) => KpiCard(
                  label: lastDist == null ? 'لا توجد دورة توزيع' : 'توزيع ${lastDist.period}',
                  value: lastDist?.status.label ?? '—',
                  icon: Icons.volunteer_activism_rounded,
                  color: AppColors.gold,
                  width: w,
                  onTap: () => go(const DistributionScreen())),
            ]),
            const SizedBox(height: 12),
            if (open.isNotEmpty)
              GovCard(
                title: 'قرارات معلّقة',
                icon: Icons.pending_actions_rounded,
                child: Column(children: [
                  for (final d in open)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(d.title),
                      subtitle: Text('المهلة ${txTime.format(d.deadline.toLocal())}', style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                      trailing: const Icon(Icons.chevron_left_rounded),
                      onTap: () => go(FamilyDecisionScreen(decisionId: d.id)),
                    ),
                ]),
              ),
            const SizedBox(height: 12),
            GovCard(title: 'آخر الأحداث', icon: Icons.history_rounded, child: AuditTimeline(events: events)),
          ],
        ),
      ),
    );
  }
}

/// بطاقة تفعيل الحوكمة العائلية في لوحة الشريك (للشريك المدير، والشركة غير مفعّلة)
class FamilyEnableCard extends StatelessWidget {
  const FamilyEnableCard({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final c = cs.current;
    if (c == null || c.familyEnabled || !cs.myRoles.contains(CompanyRole.managingPartner)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(14),
        child: ListTile(
          leading: const Icon(Icons.family_restroom_rounded, color: AppColors.gold),
          title: const Text('شركة عائلية؟'),
          subtitle: const Text('فعّل الحوكمة العائلية: الدستور العائلي، والورثة، وتوزيع الأرباح، والخلافة.',
              style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          trailing: TextButton(onPressed: () => cs.setFamilyEnabled(c.id, true), child: const Text('تفعيل')),
        ),
      ),
    );
  }
}
