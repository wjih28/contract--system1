import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../theme/app_theme.dart';
import 'decision_details_screen.dart';

/// P08: مركز التصويت. كل القرارات مع العتبة والنتيجة المرجّحة والنصاب والمهلة وحالة صوتي.
/// لا يظهر أي قرار "معتمداً" لمجرد أن أحداً لم يصوّت.
class VotingCenterScreen extends StatefulWidget {
  final String? sessionId; // إن لم يُحدَّد: جلسة الشركة الحالية
  const VotingCenterScreen({super.key, this.sessionId});

  @override
  State<VotingCenterScreen> createState() => _VotingCenterScreenState();
}

class _VotingCenterScreenState extends State<VotingCenterScreen> {
  ClauseCategory? _category;

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final s = widget.sessionId != null
        ? st.sessions.where((x) => x.id == widget.sessionId).firstOrNull
        : st.establishmentFor(cs.current?.id);
    if (s == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('مركز التصويت')),
        body: const StateView.empty(
          icon: Icons.how_to_vote_rounded,
          title: 'لا توجد قرارات بعد',
          message: 'تظهر القرارات هنا بعد بدء جلسة التأسيس من وحدة "التأسيس والعقد".',
        ),
      );
    }
    final me = cs.me;
    final myId = me?.id;
    bool inCat(ClauseRecord r) => _category == null || st.question(r.questionId).category == _category;

    final mine = myId == null ? <ClauseRecord>[] : st.pendingFor(s, myId).where(inCat).toList();
    final open = s.records.where((r) => r.status.needsDecision && inCat(r)).toList();
    final done = s.records
        .where((r) => (r.status == ClauseStatus.agreed || r.status == ClauseStatus.neutralized) && inCat(r))
        .toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('مركز التصويت'),
          bottom: TabBar(tabs: [
            Tab(text: 'بانتظار صوتي (${mine.length})'),
            Tab(text: 'مفتوحة (${open.length})'),
            Tab(text: 'محسومة (${done.length})'),
          ]),
        ),
        body: ContentWidth(
          child: Column(
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(children: [
                  ChoiceChip(
                      label: const Text('كل الفئات'),
                      selected: _category == null,
                      onSelected: (_) => setState(() => _category = null)),
                  for (final c in ClauseCategory.values)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: ChoiceChip(
                        avatar: Icon(c.icon, size: 15),
                        label: Text(c.label),
                        selected: _category == c,
                        onSelected: (_) => setState(() => _category = c),
                      ),
                    ),
                ]),
              ),
              Expanded(
                child: TabBarView(children: [
                  _DecisionList(session: s, items: mine, myId: myId,
                      empty: const StateView.empty(
                          icon: Icons.task_alt_rounded,
                          title: 'لا شيء بانتظار صوتك',
                          message: 'صوّتّ على كل البنود المفتوحة لك.')),
                  _DecisionList(session: s, items: open, myId: myId,
                      empty: const StateView.empty(title: 'لا قرارات مفتوحة', message: 'كل البنود حُسمت أو أُجّلت.')),
                  _DecisionList(session: s, items: done, myId: myId,
                      empty: const StateView.empty(title: 'لا قرارات محسومة بعد', message: 'تظهر هنا البنود المعتمدة والمحيّدة.')),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DecisionList extends StatelessWidget {
  final ContractSession session;
  final List<ClauseRecord> items;
  final String? myId;
  final Widget empty;
  const _DecisionList({required this.session, required this.items, required this.myId, required this.empty});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return empty;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      itemCount: items.length,
      itemBuilder: (_, i) => _DecisionCard(session: session, record: items[i], myId: myId),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  final ContractSession session;
  final ClauseRecord record;
  final String? myId;
  const _DecisionCard({required this.session, required this.record, required this.myId});

  @override
  Widget build(BuildContext context) {
    final st = context.read<ContractState>();
    final r = record;
    final q = st.question(r.questionId);
    final res = st.quorum(session, r);
    final partner = session.partners.where((p) => p.id == r.concernedPartnerId).firstOrNull;
    final myVote = myId == null ? null : r.votes[myId];
    final fmt = DateFormat('d/M HH:mm');
    String p(double v) => '${v.toStringAsFixed(v % 1 == 0 ? 0 : 1)}%';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DecisionDetailsScreen(sessionId: session.id, recordKey: r.key)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.navySurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(q.category.icon, size: 16, color: q.category.color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(partner == null ? q.title : '${q.title} – ${partner.name}',
                      style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                ),
                _StatusPill(r.status),
              ],
            ),
            const SizedBox(height: 10),
            // النتيجة المرجّحة مقابل العتبة
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (res.agreeShare / 100).clamp(0, 1),
                minHeight: 6,
                backgroundColor: AppColors.navyLight,
                color: res.passed ? AppColors.success : AppColors.gold,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                _t('موافقة ${p(res.agreeShare)} من ${p(res.required)}'),
                _t('مشاركة ${p(res.participation)}${res.quorum > 0 ? ' (النصاب ${p(res.quorum)})' : ''}',
                    color: res.quorumMet ? AppColors.textSecondary : AppColors.warning),
                if (res.deadline != null)
                  _t(res.deadlinePassed ? 'انتهت المهلة' : 'المهلة ${fmt.format(res.deadline!)}',
                      color: res.deadlinePassed ? AppColors.warning : AppColors.textSecondary),
                if (myId != null && st.voters(session, r).any((v) => v.id == myId))
                  _t(myVote == null ? 'لم أصوّت بعد' : 'صوتي: ${myVote.ballot.label}',
                      color: myVote == null ? AppColors.info : myVote.ballot.color),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _t(String s, {Color color = AppColors.textSecondary}) =>
      Text(s, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w600));
}

class _StatusPill extends StatelessWidget {
  final ClauseStatus status;
  const _StatusPill(this.status);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: status.color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: status.color.withValues(alpha: 0.45)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(status.icon, size: 12, color: status.color),
          const SizedBox(width: 4),
          Text(status.label, style: TextStyle(color: status.color, fontSize: 10.5, fontWeight: FontWeight.w700)),
        ]),
      );
}
