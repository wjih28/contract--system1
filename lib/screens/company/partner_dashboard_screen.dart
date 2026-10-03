import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/company.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../theme/app_theme.dart';
import '../contract/clause_voting_screen.dart';
import '../establishment/contract_summary_screen.dart';
import '../contract/session_overview_screen.dart';
import '../establishment/deferred_screen.dart';
import '../establishment/voting_center_screen.dart';

/// P03: لوحة الشريك. نظرة موجهة للقرار: ما الذي يحتاج انتباهي الآن؟
/// اللوحة ملخص فقط ولا تغني عن سجل التدقيق والأدلة.
class PartnerDashboardScreen extends StatelessWidget {
  const PartnerDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final s = st.establishmentFor(c.id);
    final me = cs.me;
    final myPending = (s == null || me == null) ? <ClauseRecord>[] : st.pendingFor(s, me.id);
    final open = s == null ? <ClauseRecord>[] : st.openDecisions(s);
    final deferred = s?.count(ClauseStatus.deferred) ?? 0;
    final blocked = s == null
        ? <ClauseRecord>[]
        : s.records
            .where((r) =>
                r.status == ClauseStatus.deadlock ||
                r.status == ClauseStatus.quorumFailed ||
                r.status == ClauseStatus.rejected)
            .toList();
    final needsMySignature = s != null &&
        me != null &&
        st.signingBlockers(s).isEmpty &&
        s.status != SessionStatus.completed &&
        (s.signOffs[me.id] == null || !st.signOffValid(s, s.signOffs[me.id]!));

    final fmt = DateFormat('d/M HH:mm');

    return Scaffold(
      body: ContentWidth(
        max: 1100,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
          children: [
            // الترويسة: الشركة والعقد والحالة
            Text(c.legalName,
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
              '${c.status.label} · ${c.contractVersion > 0 ? 'العقد الإصدار ${c.contractVersion}' : s == null ? 'لم تبدأ جلسة التأسيس' : 'التأسيس ${(s.progress * 100).round()}%'}'
              '${me == null ? '' : ' · ${me.roles.map((r) => r.label).join('، ')}'}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
            ),
            const SizedBox(height: 16),
            if (blocked.any((r) => r.status == ClauseStatus.deadlock))
              StateBanner(
                color: ClauseStatus.deadlock.color,
                icon: ClauseStatus.deadlock.icon,
                text: '${blocked.where((r) => r.status == ClauseStatus.deadlock).length} بنود في حالة جمود بعد فشل متكرر. '
                    'ناقشوها وعدّلوا صيغتها أو أجّلوها أو حيّدوها بالاتفاق.',
              ),
            // مؤشرات رئيسية
            LayoutBuilder(builder: (context, box) {
              final cols = box.maxWidth > 760 ? 5 : (box.maxWidth > 480 ? 3 : 2);
              final w = (box.maxWidth - (cols - 1) * 10) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _Kpi(w, 'بانتظار صوتي', '${myPending.length}', Icons.how_to_vote_rounded, AppColors.info),
                  _Kpi(w, 'قرارات مفتوحة', '${open.length}', Icons.hourglass_top_rounded, AppColors.gold),
                  _Kpi(w, 'مؤجلة', '$deferred', Icons.schedule_rounded, AppColors.warning),
                  _Kpi(w, 'تحتاج حلاً', '${blocked.length}', Icons.error_outline_rounded, AppColors.danger),
                  _Kpi(w, 'توقيعي مطلوب', needsMySignature ? 'نعم' : 'لا', Icons.draw_rounded,
                      needsMySignature ? AppColors.success : AppColors.textMuted),
                ],
              );
            }),
            const SizedBox(height: 22),
            // قائمة المهام
            const Text('ما يحتاج انتباهك',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            if (s == null)
              _Task(
                icon: Icons.play_circle_rounded,
                color: AppColors.gold,
                title: 'ابدأ جلسة التأسيس',
                subtitle: 'لم تُفتح جلسة التأسيس لهذه الشركة بعد.',
                onTap: null,
              )
            else ...[
              if (needsMySignature)
                _Task(
                  icon: Icons.draw_rounded,
                  color: AppColors.success,
                  title: 'وقّع على العقد',
                  subtitle: 'حُسمت كل البنود، والعقد بانتظار توقيعك.',
                  // يبدأ التوقيع من ملخص العقد (P10) ثم صفحة التوقيع (P12)
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => ContractSummaryScreen(sessionId: s.id))),
                ),
              ...myPending.take(6).map((r) {
                final q = st.quorum(s, r);
                return _Task(
                  icon: Icons.how_to_vote_rounded,
                  color: AppColors.info,
                  title: 'صوّت على: ${st.question(r.questionId).title}',
                  subtitle: q.deadline == null
                      ? 'لم يبدأ التصويت عليه بعد'
                      : 'المهلة حتى ${fmt.format(q.deadline!)} · موافقة ${q.agreeShare.toStringAsFixed(0)}% من ${q.required.toStringAsFixed(0)}%',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClauseVotingScreen(sessionId: s.id, initialIndex: s.records.indexOf(r)),
                    ),
                  ),
                );
              }),
              if (myPending.length > 6)
                TextButton(
                  onPressed: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => VotingCenterScreen(sessionId: s.id))),
                  child: Text('عرض كل البنود بانتظار صوتك (${myPending.length})'),
                ),
              if (blocked.isNotEmpty)
                _Task(
                  icon: Icons.error_outline_rounded,
                  color: AppColors.danger,
                  title: '${blocked.length} بنود لم تُحسم (رفض أو تعذّر نصاب أو جمود)',
                  subtitle: 'تحتاج إعادة تصويت أو تأجيلاً أو تحييداً بالاتفاق.',
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => VotingCenterScreen(sessionId: s.id))),
                ),
              if (deferred > 0)
                _Task(
                  icon: Icons.schedule_rounded,
                  color: AppColors.warning,
                  title: '$deferred بنود مؤجلة',
                  subtitle: 'لا يصدر العقد قبل حسمها.',
                  onTap: () => Navigator.push(
                      context, MaterialPageRoute(builder: (_) => DeferredScreen(sessionId: s.id))),
                ),
              if (myPending.isEmpty && blocked.isEmpty && deferred == 0 && !needsMySignature)
                const StateBanner(
                  color: AppColors.success,
                  icon: Icons.task_alt_rounded,
                  text: 'لا توجد مهام بانتظارك الآن.',
                ),
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => SessionOverviewScreen(sessionId: s.id))),
                icon: const Icon(Icons.history_edu_rounded),
                label: const Text('فتح جلسة التأسيس'),
              ),
            ],
            const SizedBox(height: 24),
            // النشاط الأخير
            GovCard(
              title: 'النشاط الأخير',
              icon: Icons.timeline_rounded,
              child: AuditTimeline(events: cs.audit.take(6).toList()),
            ),
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final double width;
  final String label, value;
  final IconData icon;
  final Color color;
  const _Kpi(this.width, this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
            Text(label, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          ],
        ),
      );
}

class _Task extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, subtitle;
  final VoidCallback? onTap;
  const _Task({required this.icon, required this.color, required this.title, required this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: ListTile(
          onTap: onTap,
          leading: Icon(icon, color: color),
          title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5)),
          trailing: onTap == null ? null : const Icon(Icons.chevron_left_rounded, color: AppColors.textMuted),
        ),
      );
}
