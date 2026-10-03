import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../design/components.dart';
import '../../design/state_view.dart';
import '../../models/questionnaire.dart';
import '../../providers/contract_state.dart';
import '../../services/identity_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../establishment/decision_details_screen.dart';

/// شاشة التصويت على بند واحد: نص البند، السؤال التوعوي، القيمة، أصوات الشركاء، النصاب
class ClauseVotingScreen extends StatefulWidget {
  final String sessionId;
  final int initialIndex;
  const ClauseVotingScreen({super.key, required this.sessionId, required this.initialIndex});

  @override
  State<ClauseVotingScreen> createState() => _ClauseVotingScreenState();
}

class _ClauseVotingScreenState extends State<ClauseVotingScreen> {
  late int _index = widget.initialIndex;
  final _scroll = ScrollController();

  /// توقيع حالة البند عند فتحه: إن تغيّرت الجولة أو التأجيل/التحييد من جهاز آخر نعرض تنبيه تعارض
  String? _seen;
  String _sig(ClauseRecord r) => ContractState.editSig(r);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int i) {
    setState(() {
      _index = i;
      _seen = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<ContractState>();
    final s = state.sessions.where((x) => x.id == widget.sessionId).firstOrNull;
    if (s == null) return const Scaffold();
    final total = s.records.length;
    final r = s.records[_index];
    final q = state.question(r.questionId);
    final result = state.quorum(s, r);
    final voters = state.voters(s, r);
    final concerned = r.concernedPartnerId == null
        ? null
        : s.partners.where((p) => p.id == r.concernedPartnerId).firstOrNull;
    final open = r.status == ClauseStatus.pending;
    // أفعالي على البند (تعديل قيمة، إعادة تصويت، تأجيل...) تتغير بها الجولة، فلا تُعد تعارضاً
    if (_seen == null || state.lastLocalEdit == _sig(r)) _seen = _sig(r);

    return Scaffold(
      appBar: AppBar(
        title: Text('البند ${_index + 1} من $total'),
        actions: [
          if (s.status != SessionStatus.completed && s.status != SessionStatus.suspended)
            IconButton(
              tooltip: 'تعليق الجلسة',
              icon: const Icon(Icons.pause_circle_outline_rounded),
              onPressed: () {
                state.suspend(s);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('عُلّقت الجلسة، وكل ما تم محفوظ. يمكن استئنافها في أي وقت.')));
              },
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(
            value: s.progress,
            minHeight: 4,
            backgroundColor: AppColors.navyLight,
            color: AppColors.gold,
          ),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                children: [
                  if (_seen != null && _seen != _sig(r))
                    StateBanner.conflict(onRefresh: () => setState(() => _seen = _sig(r))),
                  _ProgressHeader(session: s, record: r, savedAt: s.updatedAt),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      StatusChip(label: q.category.label, color: q.category.color, icon: q.category.icon),
                      StatusChip(
                        label: q.scope.label,
                        color: q.scope == ClauseScope.private ? AppColors.gold : AppColors.textSecondary,
                        icon: q.scope == ClauseScope.private ? Icons.person_rounded : Icons.groups_rounded,
                      ),
                      if (q.effect == EffectType.financial)
                        const StatusChip(label: 'يولّد قاعدة رقابية', color: AppColors.success, icon: Icons.rule_rounded),
                      if (r.round > 1)
                        StatusChip(label: 'الجولة ${r.round}', color: AppColors.warning, icon: Icons.replay_rounded),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    concerned == null ? q.title : '${q.title} – ${concerned.name}',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 14),
                  _ClauseText(text: state.renderClause(s, r)),
                  const SizedBox(height: 12),
                  _Awareness(text: q.awareness),
                  if (q.paramKind != ParamKind.none) ...[
                    const SizedBox(height: 12),
                    _ValueEditor(
                      key: ValueKey('${r.key}-${r.round}'),
                      session: s,
                      record: r,
                      question: q,
                      enabled: open,
                    ),
                  ],
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => DecisionDetailsScreen(sessionId: s.id, recordKey: r.key)),
                      ),
                      icon: const Icon(Icons.info_outline_rounded, size: 18),
                      label: Text('التفاصيل الكاملة والسجل${r.notes.isEmpty ? '' : ' (${r.notes.length} ملاحظات)'}'),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ApprovalPanel(
                    threshold: result.required,
                    quorum: result.quorum,
                    agree: result.agreeShare,
                    disagree: result.disagreeShare,
                    neutral: result.neutralShare,
                    deadline: result.deadline,
                  ),
                  const SizedBox(height: 18),
                  SectionHeader(title: concerned == null ? 'أصوات الشركاء' : 'تراضي الشريك المعني'),
                  const SizedBox(height: 8),
                  ...voters.map((p) => _PartnerBallotRow(
                        partner: p,
                        vote: r.votes[p.id],
                        enabled: open && state.canActAs(p),
                        waitingRemote: open && !state.canActAs(p) && r.votes[p.id] == null,
                        onVote: (b) async {
                          final m = await IdentityService.confirm(
                            context,
                            partnerName: p.name,
                            action: 'التصويت بـ "${b.label}" على بند ${q.title}',
                          );
                          if (m != null) state.castVote(s, r, p.id, b, m);
                        },
                      )),
                  const SizedBox(height: 8),
                  _Outcome(
                    session: s,
                    record: r,
                    result: result,
                    onNext: () => _next(state, s),
                  ),
                ],
              ),
            ),
            _BottomBar(
              canPrev: _index > 0,
              canNext: _index < total - 1,
              canDefer: open,
              onPrev: () => _go(_index - 1),
              onNext: () => _go(_index + 1),
              onDefer: () async {
                final reason = await askDeferReason(context);
                if (reason == null || !context.mounted) return;
                state.defer(s, r, reason: reason);
                _seen = _sig(r);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم نقل البند إلى قائمة المؤجلات')),
                );
                _next(state, s);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _next(ContractState state, ContractSession s) {
    final n = state.nextPendingIndex(s, from: _index + 1);
    if (n == -1) {
      Navigator.pop(context);
      return;
    }
    _go(n);
  }
}

class _ClauseText extends StatelessWidget {
  final String text;
  const _ClauseText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.article_rounded, color: AppColors.gold, size: 18),
              SizedBox(width: 6),
              Text('نص البند كما سيظهر في العقد',
                  style: TextStyle(color: AppColors.gold, fontSize: 12.5, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          Text(text, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, height: 1.9)),
        ],
      ),
    );
  }
}

class _Awareness extends StatelessWidget {
  final String text;
  const _Awareness({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.info.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_rounded, color: AppColors.info, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.7)),
          ),
        ],
      ),
    );
  }
}

class _ValueEditor extends StatefulWidget {
  final ContractSession session;
  final ClauseRecord record;
  final BankQuestion question;
  final bool enabled;
  const _ValueEditor({
    super.key,
    required this.session,
    required this.record,
    required this.question,
    required this.enabled,
  });

  @override
  State<_ValueEditor> createState() => _ValueEditorState();
}

class _ValueEditorState extends State<_ValueEditor> {
  late final _c = TextEditingController(
    text: widget.record.value == null
        ? ''
        : widget.record.value!.toStringAsFixed(widget.record.value! % 1 == 0 ? 0 : 2),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _apply() {
    final v = double.tryParse(_c.text.trim());
    if (v == null || v == widget.record.value) return;
    final hadVotes = widget.record.votes.isNotEmpty;
    context.read<ContractState>().setValue(widget.session, widget.record, v);
    FocusScope.of(context).unfocus();
    if (hadVotes) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تغيّرت القيمة، لذا أُعيد فتح التصويت على الصيغة الجديدة')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.question;
    final suffix = switch (q.paramKind) {
      ParamKind.money => widget.session.currency.code,
      ParamKind.percent => '%',
      ParamKind.days => 'يوم',
      _ => null,
    };
    return GoldBorderCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(q.paramLabel ?? 'القيمة',
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _c,
                  enabled: widget.enabled,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  onSubmitted: (_) => _apply(),
                  decoration: InputDecoration(isDense: true, suffixText: suffix),
                ),
              ),
              const SizedBox(width: 10),
              IconButton.filled(
                onPressed: widget.enabled ? _apply : null,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.gold,
                  foregroundColor: AppColors.navyDark,
                ),
                icon: const Icon(Icons.check_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text('تعديل القيمة يعيد التصويت من البداية على الصيغة الجديدة',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}

class _PartnerBallotRow extends StatelessWidget {
  final SessionPartner partner;
  final PartnerVote? vote;
  final bool enabled;
  final bool waitingRemote; // الشريك يصوّت من جواله ولم يصل صوته بعد
  final ValueChanged<Ballot> onVote;
  const _PartnerBallotRow({
    required this.partner,
    required this.vote,
    required this.enabled,
    required this.onVote,
    this.waitingRemote = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.navySurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: vote == null ? AppColors.divider : vote!.ballot.color.withValues(alpha: 0.5)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: AppColors.gold.withValues(alpha: 0.15),
                child: Text(partner.name.characters.first,
                    style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(partner.name,
                        style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700, fontSize: 13.5)),
                    Text('الحصة ${partner.equity.toStringAsFixed(partner.equity % 1 == 0 ? 0 : 1)}%',
                        style: const TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
              ),
              if (vote != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    StatusChip(label: vote!.ballot.label, color: vote!.ballot.color, icon: vote!.ballot.icon),
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.fingerprint_rounded, size: 12, color: AppColors.textMuted),
                        const SizedBox(width: 3),
                        Text(vote!.method.label,
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 10)),
                      ],
                    ),
                  ],
                )
              else if (waitingRemote)
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone_iphone_rounded, size: 14, color: AppColors.textMuted),
                    SizedBox(width: 4),
                    Text('بانتظار تصويته من جواله',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
                  ],
                ),
            ],
          ),
          if (enabled) ...[
            const SizedBox(height: 10),
            Row(
              children: Ballot.values
                  .map((b) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: _BallotButton(
                            ballot: b,
                            selected: vote?.ballot == b,
                            onTap: () => onVote(b),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _BallotButton extends StatelessWidget {
  final Ballot ballot;
  final bool selected;
  final VoidCallback onTap;
  const _BallotButton({required this.ballot, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = ballot.color;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.2) : AppColors.navyLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? c : Colors.transparent, width: 1.5),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ballot.icon, size: 16, color: selected ? c : AppColors.textSecondary),
            const SizedBox(width: 5),
            Text(ballot.label,
                style: TextStyle(
                    color: selected ? c : AppColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

/// نتيجة البند والخيارات المتاحة بعد اكتمال التصويت
class _Outcome extends StatelessWidget {
  final ContractSession session;
  final ClauseRecord record;
  final QuorumResult result;
  final VoidCallback onNext;
  const _Outcome({required this.session, required this.record, required this.result, required this.onNext});

  @override
  Widget build(BuildContext context) {
    final state = context.read<ContractState>();
    final st = record.status;

    if (st == ClauseStatus.pending) return const SizedBox.shrink();

    Widget panel({required Color color, required IconData icon, required String title, required String body, required List<Widget> actions}) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 26),
                const SizedBox(width: 10),
                Text(title, style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.7)),
            const SizedBox(height: 14),
            ...actions,
          ],
        ),
      );
    }

    switch (st) {
      case ClauseStatus.agreed:
        return panel(
          color: AppColors.success,
          icon: Icons.verified_rounded,
          title: 'تم التراضي على البند',
          body: 'بلغت الموافقة ${result.agreeShare.toStringAsFixed(1)}% والنصاب المطلوب ${result.required.toStringAsFixed(result.required % 1 == 0 ? 0 : 2)}%. حُفظ البند مع الطوابع الزمنية لكل صوت.',
          actions: [
            ElevatedButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('البند التالي'),
            ),
          ],
        );
      case ClauseStatus.rejected || ClauseStatus.quorumFailed || ClauseStatus.deadlock:
        String pct(double v) => v.toStringAsFixed(v % 1 == 0 ? 0 : 1);
        return panel(
          color: st.color,
          icon: st.icon,
          title: switch (st) {
            ClauseStatus.quorumFailed => 'تعذّر النصاب',
            ClauseStatus.deadlock => 'جمود في هذا البند',
            _ => 'لم يبلغ البند العتبة المطلوبة',
          },
          body: switch (st) {
            ClauseStatus.quorumFailed =>
              'انتهت المهلة وشاركت حصص ${pct(result.participation)}% فقط من ${pct(result.quorum)}% مطلوبة. '
                  'هذه حالة إجرائية وليست موافقة. أعيدوا التصويت بعد التنسيق، أو أجّلوه، أو حيّدوه بالاتفاق.',
            ClauseStatus.deadlock =>
              'فشل التصويت ${record.failures + 1} مرات متتالية. ناقشوا البند وعدّلوا صيغته أو قيمته قبل إعادة التصويت، '
                  'أو أجّلوه لجلسة لاحقة، أو حيّدوه بالاتفاق حتى لا يعطّل العقد. (بعد التأسيس يتحول الجمود إلى تذكرة نزاع).',
            _ => 'بلغت الموافقة ${pct(result.agreeShare)}% من ${pct(result.required)}% مطلوبة. '
                'يمكنكم مناقشة البند وتعديل صيغته أو قيمته ثم إعادة التصويت، أو تأجيله، أو تحييده بالاتفاق.',
          },
          actions: [
            ElevatedButton.icon(
              onPressed: () => state.revote(session, record),
              icon: const Icon(Icons.replay_rounded),
              label: const Text('إعادة التصويت'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final reason = await askDeferReason(context);
                      if (reason == null) return;
                      state.defer(session, record, reason: reason);
                      onNext();
                    },
                    icon: const Icon(Icons.schedule_rounded, size: 18),
                    label: const Text('تأجيل'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _neutralize(context),
                    icon: const Icon(Icons.block_rounded, size: 18),
                    label: const Text('تحييد'),
                  ),
                ),
              ],
            ),
          ],
        );
      case ClauseStatus.deferred:
      case ClauseStatus.neutralized:
        return panel(
          color: st.color,
          icon: st.icon,
          title: st == ClauseStatus.deferred ? 'البند مؤجل' : 'البند محيّد',
          body: st == ClauseStatus.deferred
              ? 'هذا البند في قائمة المؤجلات، ولا يصدر العقد النهائي قبل حسمه.'
              : 'تم استبعاد هذا البند من العقد باتفاق جميع الشركاء.',
          actions: [
            OutlinedButton.icon(
              onPressed: () => state.reopen(session, record),
              icon: const Icon(Icons.lock_open_rounded, size: 18),
              label: const Text('إعادة فتحه للتصويت'),
            ),
            if (st == ClauseStatus.deferred) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _neutralize(context),
                icon: const Icon(Icons.block_rounded, size: 18),
                label: const Text('تحييد بالاتفاق'),
              ),
            ],
          ],
        );
      case ClauseStatus.notApplicable:
        return panel(
          color: st.color,
          icon: st.icon,
          title: 'البند غير منطبق',
          body: 'لا ينطبق هذا البند بناءً على نتيجة البند الذي يعتمد عليه، فلا يُصوَّت عليه ولا يدخل في العقد.',
          actions: [
            ElevatedButton.icon(
              onPressed: onNext,
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Text('البند التالي'),
            ),
          ],
        );
      case ClauseStatus.pending:
        return const SizedBox.shrink();
    }
  }

  /// التحييد يتطلب تأكيد كل شريك على حدة.
  /// في وضع الخادم يوافق كل شريك من جواله، وتظهر الموافقات هنا لحظياً.
  Future<void> _neutralize(BuildContext context) async {
    final state = context.read<ContractState>();
    final localConfirmed = <String>{};
    await showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.navySurface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => ListenableBuilder(
        listenable: state,
        builder: (ctx, _) => StatefulBuilder(
        builder: (ctx, setSheet) {
          final s = state.sessions.where((x) => x.id == session.id).firstOrNull ?? session;
          final rec = s.records.where((x) => x.key == record.key).firstOrNull ?? record;
          final confirmed = state.isCloud ? rec.neutralConsents : localConfirmed;
          final all = s.partners.where((p) => p.equity > 0).toList();
          final done = all.every((p) => confirmed.contains(p.id));
          return Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.block_rounded, color: AppColors.gold, size: 38),
                const SizedBox(height: 10),
                const Text('تحييد البند بالاتفاق',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text('يُستبعد البند من العقد فقط إذا وافق جميع الشركاء على تحييده.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textMuted, fontSize: 12.5)),
                const SizedBox(height: 16),
                ...all.map((p) {
                  final ok = confirmed.contains(p.id);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        color: ok ? AppColors.success : AppColors.textMuted),
                    title: Text(p.name, style: const TextStyle(color: AppColors.textPrimary)),
                    trailing: ok
                        ? null
                        : !state.canActAs(p)
                            ? const Text('من جواله',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 11.5))
                            : TextButton(
                                onPressed: () async {
                                  final m = await IdentityService.confirm(ctx,
                                      partnerName: p.name, action: 'الموافقة على تحييد البند');
                                  if (m == null) return;
                                  if (state.isCloud) {
                                    state.consentNeutralize(s, rec, p.id, m);
                                  } else {
                                    setSheet(() => localConfirmed.add(p.id));
                                  }
                                },
                                child: const Text('أوافق'),
                              ),
                  );
                }),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: done
                      ? () {
                          state.neutralize(s, rec);
                          Navigator.pop(ctx);
                        }
                      : null,
                  child: const Text('اعتماد التحييد'),
                ),
              ],
            ),
          );
        },
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final bool canPrev, canNext, canDefer;
  final VoidCallback onPrev, onNext, onDefer;
  const _BottomBar({
    required this.canPrev,
    required this.canNext,
    required this.canDefer,
    required this.onPrev,
    required this.onNext,
    required this.onDefer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: AppColors.navyMedium,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'السابق',
            onPressed: canPrev ? onPrev : null,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          Expanded(
            child: TextButton.icon(
              onPressed: canDefer ? onDefer : null,
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: const Text('تأجيل البند لجلسة لاحقة'),
            ),
          ),
          IconButton(
            tooltip: 'التالي',
            onPressed: canNext ? onNext : null,
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }
}

/// سؤال سبب التأجيل (اختياري) قبل نقل البند إلى المؤجلات
Future<String?> askDeferReason(BuildContext context) async {
  final c = TextEditingController();
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('تأجيل البند لجلسة لاحقة'),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLines: 2,
        decoration: const InputDecoration(hintText: 'سبب التأجيل (اختياري)، مثل: بانتظار رأي المحاسب'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('تأجيل')),
      ],
    ),
  );
  c.dispose();
  return r;
}

/// رأس التقدم (P05): المحسوم من الإجمالي، القسم الحالي، غير المحسوم، وتأكيد الحفظ التلقائي
class _ProgressHeader extends StatelessWidget {
  final ContractSession session;
  final ClauseRecord record;
  final DateTime savedAt;
  const _ProgressHeader({required this.session, required this.record, required this.savedAt});

  @override
  Widget build(BuildContext context) {
    final st = context.read<ContractState>();
    final s = session;
    final done = s.count(ClauseStatus.agreed) + s.count(ClauseStatus.neutralized);
    final unresolved = s.records.where((r) => r.status.needsDecision).length + s.count(ClauseStatus.deferred);
    final cat = st.question(record.questionId).category;
    final t = TimeOfDay.fromDateTime(savedAt.toLocal()).format(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'محسوم $done من ${s.records.length} · القسم ${cat.label} · $unresolved غير محسوم',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
        Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_done_rounded, size: 14, color: AppColors.success),
          const SizedBox(width: 4),
          Text('حُفظ تلقائياً $t', style: const TextStyle(color: AppColors.success, fontSize: 11)),
        ]),
      ],
    );
  }
}
