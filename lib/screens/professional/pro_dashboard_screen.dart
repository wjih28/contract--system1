import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../models/company.dart';
import '../../models/professional.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../providers/professional_state.dart';
import '../../theme/app_theme.dart';
import '../establishment/witness_tasks_screen.dart';
import '../operations/tx_widgets.dart';
import 'accounting_review_screen.dart';
import 'legal_review_screen.dart';
import 'pro_comments_screen.dart';
import 'pro_common.dart';

final _d = DateFormat('yyyy/MM/dd');

/// R02: لوحة الطرف المهني. المهام المسندة فقط: مسودات تنتظر المراجعة، وتعليقات تنتظر رداً،
/// ومهام الشهادة، والمهل. للشاهد تعرض مهام الشهادة وحدها.
class ProDashboardScreen extends StatelessWidget {
  const ProDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final pro = context.watch<ProfessionalState>();
    final c = cs.current;
    final e = myEngagement(context);
    if (c == null || e == null) return const WitnessTasksScreen();
    void go(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
    final sessions = reviewableSessions(st, c.id);
    final pending = [for (final s in sessions) if (pro.review(e, s.id)?.status != ReviewStatus.completed) s];
    final mine = pro.commentsFor(c.id, engagementId: e.id);
    final awaiting = mine.where((x) => x.status == CommentStatus.awaitingResponse).toList();
    final open = mine.where((x) => x.status.isOpen).toList();
    final daysLeft = e.end.difference(pro.now()).inDays;
    final reviewScreen = e.role == ProRole.lawyer ? const LegalReviewScreen() : const AccountingReviewScreen();
    final hasScope = e.scope.contains(e.role == ProRole.lawyer ? EngagementScope.contract : EngagementScope.financialRules);

    return Scaffold(
      appBar: AppBar(title: Text('مهامي · ${e.role.label}')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            KpiGrid(items: [
              (w) => KpiCard(
                  label: 'مستندات تنتظر مراجعتك',
                  value: hasScope ? '${pending.length}' : '—',
                  icon: Icons.rate_review_rounded,
                  color: AppColors.gold,
                  width: w,
                  onTap: hasScope ? () => go(reviewScreen) : null),
              (w) => KpiCard(
                  label: 'ردود من الشركة تنتظرك',
                  value: '${awaiting.length}',
                  icon: Icons.mark_chat_unread_rounded,
                  color: AppColors.info,
                  width: w,
                  onTap: () => go(const ProCommentsScreen())),
              (w) => KpiCard(
                  label: 'تعليقاتك المفتوحة',
                  value: '${open.length}',
                  icon: Icons.forum_rounded,
                  color: AppColors.warning,
                  width: w,
                  onTap: () => go(const ProCommentsScreen())),
              (w) => KpiCard(
                  label: 'ينتهي التكليف ${_d.format(e.end)}',
                  value: daysLeft < 0 ? 'منتهٍ' : '$daysLeft يوماً',
                  icon: Icons.event_rounded,
                  color: daysLeft < 14 ? AppColors.danger : AppColors.success,
                  width: w),
            ]),
            const SizedBox(height: 14),
            GovCard(
              title: 'المسودات والإصدارات',
              icon: Icons.description_rounded,
              child: !hasScope
                  ? const Text('مراجعة العقد خارج نطاق تكليفك.', style: TextStyle(color: AppColors.textMuted))
                  : Column(children: [
                      for (final s in sessions)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(sessionLabel(s)),
                          subtitle: Text(pro.review(e, s.id)?.status.label ?? 'لم تبدأ المراجعة',
                              style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
                          trailing: const Icon(Icons.chevron_left_rounded),
                          onTap: () => go(reviewScreen),
                        ),
                      if (sessions.isEmpty) const Text('لا توجد مستندات بعد.', style: TextStyle(color: AppColors.textMuted)),
                    ]),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'آخر النشاط',
              icon: Icons.history_rounded,
              child: Column(children: [
                for (final x in mine.take(5))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${x.kind.label}: ${x.targetLabel}'),
                    subtitle: Text('${x.status.label} · ${txTime.format(x.createdAt.toLocal())}',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
                    onTap: () => go(const ProCommentsScreen()),
                  ),
                if (mine.isEmpty) const Text('لا يوجد نشاط بعد.', style: TextStyle(color: AppColors.textMuted)),
              ]),
            ),
            if (st.witnessTasks.isNotEmpty) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => go(const WitnessTasksScreen()),
                icon: const Icon(Icons.person_pin_rounded),
                label: Text('مهام الشهادة (${st.witnessTasks.length})'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// R03: ملف التكليف. النطاق والمدة والجهة والتواصل والحالة وسجل الإشعارات.
class EngagementScreen extends StatelessWidget {
  const EngagementScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final pro = context.watch<ProfessionalState>();
    final c = cs.current;
    final e = myEngagement(context);
    if (c == null || e == null) return const WitnessTasksScreen();
    final history = cs.audit.where((x) => x.objectType == 'engagement' && x.objectId == e.id).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('ملف التكليف')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            EngagementCard(c: c, e: e),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () async {
                final t = TextEditingController(text: e.contact);
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: AppColors.navySurface,
                    title: const Text('بيانات التواصل'),
                    content: TextField(controller: t, decoration: const InputDecoration(labelText: 'بريد أو هاتف المكتب')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                      ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
                    ],
                  ),
                );
                if (ok == true) pro.updateContact(c, e, t.text);
                t.dispose();
              },
              icon: const Icon(Icons.contact_mail_rounded),
              label: const Text('تحديث بيانات التواصل'),
            ),
            const SizedBox(height: 12),
            GovCard(title: 'سجل التكليف', icon: Icons.history_rounded, child: AuditTimeline(events: history)),
          ],
        ),
      ),
    );
  }
}

/// بطاقة التكليف (تُستخدم في ملف التكليف ولدى الشركاء)
class EngagementCard extends StatelessWidget {
  final Company c;
  final Engagement e;
  final Widget? trailing;
  const EngagementCard({super.key, required this.c, required this.e, this.trailing});

  @override
  Widget build(BuildContext context) {
    final st = e.statusAt(context.read<ProfessionalState>().now());
    return GovCard(
      title: '${e.name} · ${e.role.label}',
      icon: e.role == ProRole.lawyer ? Icons.balance_rounded : Icons.calculate_rounded,
      trailing: Text(st.label, style: TextStyle(color: st.color, fontWeight: FontWeight.w800, fontSize: 12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('الشركة: ${c.legalName}${e.organization.isEmpty ? '' : ' · الجهة: ${e.organization}'}', style: const TextStyle(height: 1.7)),
        Text('النطاق: ${e.scope.map((s) => s.label).join('، ')}', style: const TextStyle(height: 1.7)),
        Text('المدة: ${_d.format(e.start)} – ${_d.format(e.end)}', style: const TextStyle(height: 1.7)),
        if (e.contact.isNotEmpty) Text('التواصل: ${e.contact}', style: const TextStyle(height: 1.7)),
        if (e.declineReason != null && e.declineReason!.isNotEmpty) Text('سبب الاعتذار: ${e.declineReason}'),
        if (e.terminationReason != null && st != EngagementStatus.terminated)
          Text('طلب إنهاء: ${e.terminationReason}', style: const TextStyle(color: AppColors.warning)),
        ?trailing,
      ]),
    );
  }
}
