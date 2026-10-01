import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/gov_status.dart';
import '../../design/responsive.dart';
import '../../design/state_view.dart';
import '../../models/questionnaire.dart';
import '../../providers/company_state.dart';
import '../../providers/contract_state.dart';
import '../../services/identity_service.dart';
import '../../theme/app_theme.dart';
import '../contract/clause_voting_screen.dart';

/// P06 + P09: تفاصيل القرار. السياق الكامل قبل التصويت، والحساب المرجّح الشفاف،
/// ومصفوفة الأصوات، والملاحظات، وسجل البند، ثم التصويت بتأكيد صريح.
class DecisionDetailsScreen extends StatefulWidget {
  final String sessionId;
  final String recordKey;
  const DecisionDetailsScreen({super.key, required this.sessionId, required this.recordKey});

  @override
  State<DecisionDetailsScreen> createState() => _DecisionDetailsScreenState();
}

class _DecisionDetailsScreenState extends State<DecisionDetailsScreen> {
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  GovStatus _gov(ClauseStatus s) => switch (s) {
        ClauseStatus.pending => GovStatus.pending,
        ClauseStatus.agreed => GovStatus.approved,
        ClauseStatus.rejected => GovStatus.rejected,
        ClauseStatus.deferred => GovStatus.deferred,
        ClauseStatus.neutralized => GovStatus.neutralized,
        ClauseStatus.quorumFailed => GovStatus.pending,
        ClauseStatus.deadlock => GovStatus.dispute,
        ClauseStatus.notApplicable => GovStatus.archived,
      };

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    final cs = context.watch<CompanyState>();
    final s = st.sessions.where((x) => x.id == widget.sessionId).firstOrNull;
    final r = s?.records.where((x) => x.key == widget.recordKey).firstOrNull;
    if (s == null || r == null) {
      return const Scaffold(body: StateView.empty(title: 'القرار غير موجود', message: ''));
    }
    final q = st.question(r.questionId);
    final res = st.quorum(s, r);
    final voters = st.voters(s, r);
    final partner = s.partners.where((p) => p.id == r.concernedPartnerId).firstOrNull;
    final readOnly = s.status == SessionStatus.completed;
    final history = cs.audit.where((e) => e.objectId == r.key).toList();
    final fmt = DateFormat('yyyy/MM/dd HH:mm');
    final rule = q.rule;

    // الحساب المرجّح بالأرقام الدقيقة بلا تقريب يغيّر النتيجة
    final totalEquity = voters.fold<double>(0, (a, p) => a + p.equity);
    final agreeEquity =
        voters.where((p) => r.votes[p.id]?.ballot == Ballot.agree).fold<double>(0, (a, p) => a + p.equity);

    return Scaffold(
      appBar: AppBar(title: Text(q.id)),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            if (readOnly) StateBanner.readOnly('العقد معتمد: هذا القرار للقراءة فقط.'),
            Wrap(spacing: 6, runSpacing: 6, children: [
              StatusBadge(_gov(r.status), overrideLabel: r.status.label),
              _Chip(q.category.label, q.category.icon, q.category.color),
              _Chip(q.effect == EffectType.financial ? 'أثر مالي ومحاسبي' : 'أثر قانوني وإداري',
                  q.effect == EffectType.financial ? Icons.account_balance_wallet_rounded : Icons.gavel_rounded,
                  AppColors.gold),
              _Chip(q.scope.label, Icons.groups_rounded, AppColors.textSecondary),
              if (r.round > 1) _Chip('الجولة ${r.round}', Icons.replay_rounded, AppColors.warning),
            ]),
            const SizedBox(height: 12),
            Text(partner == null ? q.title : '${q.title} – ${partner.name}',
                style: const TextStyle(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 14),
            GovCard(
              title: 'نص البند كما سيظهر في العقد',
              icon: Icons.article_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(st.renderClause(s, r),
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.9)),
                  const SizedBox(height: 10),
                  const Text(
                    'هذه هي الصيغة المعتمدة في النظام وأثرها، وليست استشارة قانونية.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'لماذا هذا البند مهم؟',
              icon: Icons.lightbulb_rounded,
              child: Text(q.awareness,
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.8)),
            ),
            if (rule != null) ...[
              const SizedBox(height: 12),
              GovCard(
                title: 'الأثر التشغيلي: القاعدة التي سيولّدها البند',
                icon: Icons.rule_rounded,
                child: Text(
                  'إذا كان ${rule.fieldLabel}'
                  '${r.value == null ? '' : ' ${rule.op.symbol} ${st.formatValue(s, q, r.value)}${q.paramKind == ParamKind.percent ? '%' : ''}'}'
                  ' ⟵ ${rule.action}',
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 13.5, height: 1.7),
                ),
              ),
            ],
            const SizedBox(height: 12),
            ApprovalPanel(
              threshold: res.required,
              quorum: res.quorum,
              agree: res.agreeShare,
              disagree: res.disagreeShare,
              neutral: res.neutralShare,
              deadline: res.deadline,
              decision: r.status == ClauseStatus.pending ? null : _gov(r.status),
              voters: voters
                  .map((p) => VoterLine(
                        name: p.name,
                        weight: r.concernedPartnerId != null ? 100 : p.equity,
                        vote: r.votes[p.id]?.ballot.label,
                        voteColor: r.votes[p.id]?.ballot.color,
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'طريقة الحساب',
              icon: Icons.calculate_rounded,
              child: Text(
                r.concernedPartnerId != null
                    ? 'بند خاص: يُعتمد بموافقة ${partner?.name ?? 'الشريك المعني'} وحده (100%).'
                    : 'حصص الموافقين $agreeEquity ÷ إجمالي الحصص $totalEquity = '
                        '${totalEquity == 0 ? 0 : (agreeEquity / totalEquity * 100).toStringAsFixed(4)}%\n'
                        'العتبة المطلوبة ${res.required}%، والحد الأدنى للمشاركة ${res.quorum}%.\n'
                        'المحايد وعدم التصويت لا يُحتسبان موافقة. المهلة ${s.settings.deadlineDays} أيام من أول صوت، '
                        'والجمود بعد ${s.settings.deadlockAfter} جولات فاشلة متتالية.',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.8),
              ),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'ملاحظات النقاش (${r.notes.length})',
              icon: Icons.forum_rounded,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (r.notes.isEmpty)
                    const Text('لا توجد ملاحظات.', style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                  ...r.notes.map((n) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.text, style: const TextStyle(color: AppColors.textPrimary, fontSize: 13)),
                            Text('${n.author} · ${fmt.format(n.at.toLocal())}',
                                style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                          ],
                        ),
                      )),
                  if (!readOnly) ...[
                    const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _note,
                          minLines: 1,
                          maxLines: 3,
                          decoration: const InputDecoration(hintText: 'أضف ملاحظة للنقاش', isDense: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.navyDark),
                        onPressed: () {
                          st.addNote(s, r, _note.text, author: cs.me?.name ?? cs.myName);
                          _note.clear();
                        },
                        icon: const Icon(Icons.send_rounded),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            GovCard(
              title: 'سجل هذا البند',
              icon: Icons.history_rounded,
              child: AuditTimeline(events: history),
            ),
          ],
        ),
      ),
      bottomNavigationBar: readOnly ? null : _ActionBar(session: s, record: r),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  const _Chip(this.label, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
        ]),
      );
}

/// شريط الإجراء: التصويت بتأكيد صريح، أو فتح البند في الجلسة لمعالجة الرفض والجمود
class _ActionBar extends StatelessWidget {
  final ContractSession session;
  final ClauseRecord record;
  const _ActionBar({required this.session, required this.record});

  @override
  Widget build(BuildContext context) {
    final st = context.read<ContractState>();
    final cs = context.read<CompanyState>();
    final r = record;
    final myId = cs.me?.id;
    final mine = st.voters(session, r).where((p) => p.id == myId && st.canActAs(p)).firstOrNull;
    final canVote = mine != null && r.status == ClauseStatus.pending;

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          color: AppColors.navyMedium,
          border: Border(top: BorderSide(color: AppColors.divider)),
        ),
        child: canVote
            ? Row(
                children: [
                  for (final b in Ballot.values)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: b.color,
                            side: BorderSide(color: b.color.withValues(alpha: r.votes[mine.id]?.ballot == b ? 1 : 0.4)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => _confirmVote(context, mine, b),
                          icon: Icon(b.icon, size: 18),
                          label: Text(b.label),
                        ),
                      ),
                    ),
                ],
              )
            : ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClauseVotingScreen(sessionId: session.id, initialIndex: session.records.indexOf(r)),
                  ),
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(r.status.needsDecision && r.status != ClauseStatus.pending
                    ? 'معالجة البند في الجلسة (إعادة تصويت، تأجيل، تحييد)'
                    : 'فتح البند في جلسة التأسيس'),
              ),
      ),
    );
  }

  /// تأكيد صريح للاختيار قبل التسجيل، ثم تأكيد الهوية
  Future<void> _confirmVote(BuildContext context, SessionPartner me, Ballot b) async {
    final st = context.read<ContractState>();
    final q = st.question(record.questionId);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد التصويت'),
        content: Text(
          'ستصوّت بـ "${b.label}" على بند "${q.title}" بوزن ${me.equity.toStringAsFixed(me.equity % 1 == 0 ? 0 : 2)}% '
          'من الحصص. يُسجَّل الصوت مع وقته في سجل التدقيق.',
          style: const TextStyle(height: 1.7),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text('تأكيد "${b.label}"')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final m = await IdentityService.confirm(context, partnerName: me.name, action: 'التصويت بـ "${b.label}" على بند ${q.title}');
    if (m == null) return;
    st.castVote(session, record, me.id, b, m);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('سُجّل صوتك "${b.label}" على ${q.title}')));
    }
  }
}
