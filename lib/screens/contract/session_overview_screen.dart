import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/questionnaire.dart';
import '../../providers/contract_state.dart';
import '../../services/contract_pdf.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'clause_voting_screen.dart';
import 'finalize_screen.dart';

/// ملخص الجلسة: التقدم، البنود حسب الحالة، التعليق والاستئناف، التقرير المرحلي
class SessionOverviewScreen extends StatelessWidget {
  final String sessionId;
  const SessionOverviewScreen({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ContractState>();
    final s = state.sessions.where((x) => x.id == sessionId).firstOrNull;
    if (s == null) {
      return const Scaffold(body: Center(child: Text('الجلسة غير موجودة')));
    }
    final suspended = s.status == SessionStatus.suspended;
    final completed = s.status == SessionStatus.completed;
    final next = state.nextPendingIndex(s);

    void openVoting(int index) {
      if (suspended) {
        state.resume(s);
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClauseVotingScreen(sessionId: s.id, initialIndex: index),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.companyName),
        actions: [
          PopupMenuButton<String>(
            color: AppColors.navySurface,
            onSelected: (v) async {
              if (v == 'delete') {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('حذف الجلسة؟'),
                    content: const Text('سيتم حذف الجلسة وكل الأصوات المسجلة فيها من هذا الجهاز.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('حذف', style: TextStyle(color: AppColors.danger)),
                      ),
                    ],
                  ),
                );
                if (ok == true && context.mounted) {
                  Navigator.pop(context);
                  state.deleteSession(s);
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('حذف الجلسة')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        children: [
          _ProgressHeader(session: s),
          const SizedBox(height: 14),
          if (suspended)
            _Banner(
              color: AppColors.warning,
              icon: Icons.pause_circle_rounded,
              text: 'الجلسة معلّقة. ما تم التراضي عليه محفوظ، ويمكن استئنافها في أي وقت.',
            ),
          if (s.count(ClauseStatus.deferred) > 0 && next == -1 && !s.allResolved)
            _Banner(
              color: AppColors.warning,
              icon: Icons.schedule_rounded,
              text: 'تبقت بنود مؤجلة فقط. أعيدوا فتحها للتصويت أو حيّدوها بالاتفاق لإتمام العقد.',
            ),
          if (s.allResolved && !completed)
            _Banner(
              color: AppColors.success,
              icon: Icons.verified_rounded,
              text: 'تم التراضي على كافة البنود. انتقلوا لإقرار الأهلية والتوقيع وتوليد العقد النهائي.',
            ),
          const SizedBox(height: 4),
          if (!completed) ...[
            if (next != -1)
              ElevatedButton.icon(
                onPressed: () => openVoting(next),
                icon: Icon(suspended ? Icons.play_arrow_rounded : Icons.how_to_vote_rounded),
                label: Text(suspended ? 'استئناف الجلسة' : 'متابعة التصويت'),
              ),
            if (s.allResolved)
              ElevatedButton.icon(
                onPressed: () {
                  state.markAwaitingSignature(s);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => FinalizeScreen(sessionId: s.id)),
                  );
                },
                icon: const Icon(Icons.draw_rounded),
                label: const Text('التوقيع وتوليد العقد'),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                if (!suspended && next != -1)
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        state.suspend(s);
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('تم تعليق الجلسة وحفظ ما تم التراضي عليه')));
                      },
                      icon: const Icon(Icons.pause_rounded, size: 18),
                      label: const Text('تعليق'),
                    ),
                  ),
                if (!suspended && next != -1) const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => ContractPdf.share(state, s, interim: true),
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: const Text('تقرير مرحلي'),
                  ),
                ),
              ],
            ),
          ] else
            ElevatedButton.icon(
              onPressed: () => ContractPdf.share(state, s, interim: false),
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('عرض العقد النهائي PDF'),
            ),
          const SizedBox(height: 24),
          ...ClauseCategory.values.map((c) {
            final items = s.records
                .asMap()
                .entries
                .where((e) => state.question(e.value.questionId).category == c)
                .toList();
            if (items.isEmpty) return const SizedBox.shrink();
            final done = items
                .where((e) =>
                    e.value.status == ClauseStatus.agreed ||
                    e.value.status == ClauseStatus.neutralized)
                .length;
            return Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(c.icon, color: c.color, size: 18),
                      const SizedBox(width: 8),
                      Text('البنود ال${c.label}ة',
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w800,
                              fontSize: 15)),
                      const Spacer(),
                      Text('$done / ${items.length}',
                          style: TextStyle(color: c.color, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.navySurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < items.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _ClauseTile(
                            session: s,
                            record: items[i].value,
                            onTap: completed ? null : () => openVoting(items[i].key),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          if (s.allResolved) ...[
            const SectionHeader(title: 'القواعد الرقابية المولدة من العقد'),
            const SizedBox(height: 8),
            GoldBorderCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: state.generatedRules(s).isEmpty
                    ? [const Text('لا توجد قواعد مالية معتمدة',
                        style: TextStyle(color: AppColors.textMuted))]
                    : state
                        .generatedRules(s)
                        .map((r) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.rule_rounded,
                                      color: AppColors.gold, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(r,
                                        style: const TextStyle(
                                            color: AppColors.textSecondary,
                                            fontSize: 12.5,
                                            height: 1.6)),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final ContractSession session;
  const _ProgressHeader({required this.session});

  @override
  Widget build(BuildContext context) {
    final s = session;
    return GoldBorderCard(
      child: Row(
        children: [
          SizedBox(
            width: 92,
            height: 92,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: s.progress,
                  strokeWidth: 8,
                  backgroundColor: AppColors.navyLight,
                  color: s.progress >= 1 ? AppColors.success : AppColors.gold,
                  strokeCap: StrokeCap.round,
                ),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${(s.progress * 100).round()}%',
                          style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w900)),
                      const Text('محسوم',
                          style: TextStyle(color: AppColors.textMuted, fontSize: 10.5)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusChip(
                        label: s.status.label, color: s.status.color, icon: Icons.circle),
                    const SizedBox(width: 6),
                    StatusChip(
                        label: 'الجلسة رقم ${s.sittings}',
                        color: AppColors.info,
                        icon: Icons.event_repeat_rounded),
                  ],
                ),
                const SizedBox(height: 10),
                _Count(ClauseStatus.agreed, s.count(ClauseStatus.agreed)),
                _Count(ClauseStatus.pending, s.count(ClauseStatus.pending)),
                _Count(ClauseStatus.deferred, s.count(ClauseStatus.deferred)),
                _Count(ClauseStatus.rejected, s.count(ClauseStatus.rejected)),
                _Count(ClauseStatus.neutralized, s.count(ClauseStatus.neutralized)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  final ClauseStatus st;
  final int n;
  const _Count(this.st, this.n);

  @override
  Widget build(BuildContext context) {
    if (n == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          Icon(st.icon, size: 13, color: st.color),
          const SizedBox(width: 6),
          Text(st.label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const Spacer(),
          Text('$n', style: TextStyle(color: st.color, fontWeight: FontWeight.w800, fontSize: 12.5)),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String text;
  const _Banner({required this.color, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: color, fontSize: 12.5, height: 1.6, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _ClauseTile extends StatelessWidget {
  final ContractSession session;
  final ClauseRecord record;
  final VoidCallback? onTap;
  const _ClauseTile({required this.session, required this.record, this.onTap});

  @override
  Widget build(BuildContext context) {
    final state = context.read<ContractState>();
    final q = state.question(record.questionId);
    final partner = record.concernedPartnerId == null
        ? null
        : session.partners.where((p) => p.id == record.concernedPartnerId).firstOrNull;
    return ListTile(
      onTap: onTap,
      dense: true,
      leading: Icon(record.status.icon, color: record.status.color, size: 22),
      title: Text(
        partner == null ? q.title : '${q.title} – ${partner.name}',
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        record.status.label,
        style: TextStyle(color: record.status.color, fontSize: 11.5),
      ),
      trailing: onTap == null
          ? null
          : const Icon(Icons.chevron_left_rounded, color: AppColors.textMuted),
    );
  }
}
