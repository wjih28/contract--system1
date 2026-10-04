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
import '../../theme/app_theme.dart';
import '../establishment/final_contract_screen.dart';
import 'amendment_screens.dart';

final _dt = DateFormat('yyyy/MM/dd HH:mm');

/// حالة الإصدار للعرض: ساري، مؤرشف، قيد التصويت، بانتظار التوقيع، لم يُعتمد
(GovStatus, String) versionState(ContractSession s) {
  if (s.status == SessionStatus.completed) {
    return s.archived ? (GovStatus.archived, 'مؤرشف') : (GovStatus.approved, 'الإصدار الساري');
  }
  if (s.status == SessionStatus.withdrawn) return (GovStatus.rejected, 'لم يُعتمد');
  return s.allResolved ? (GovStatus.pending, 'بانتظار التوقيع') : (GovStatus.draft, 'قيد التصويت');
}

/// فتح الإصدار: المعتمد إلى العقد النهائي (P13)، وغيره إلى تفاصيل التعديل
void openVersion(BuildContext context, ContractSession s) {
  final page = s.status == SessionStatus.completed || !s.isAmendment
      ? FinalContractScreen(sessionId: s.id)
      : AmendmentDetailScreen(sessionId: s.id);
  Navigator.push(context, MaterialPageRoute(builder: (_) => page));
}

/// P14: إصدارات العقد. خط زمني من التأسيس عبر التعديلات، والإصدار الساري مميَّز،
/// والإصدارات السابقة للقراءة فقط. التعديل يُنشئ إصداراً جديداً ولا يغيّر القديم.
class VersionsScreen extends StatelessWidget {
  const VersionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = context.watch<CompanyState>();
    final st = context.watch<ContractState>();
    final c = cs.current;
    if (c == null) return const StateView.empty(title: 'لا توجد شركة', message: '');
    final versions = st.versionsFor(c.id).reversed.toList();
    final current = st.currentContract(c.id);
    final blocker = st.amendmentBlocker(c.id);
    final isPartner = cs.me?.isPartner ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('إصدارات العقد')),
      floatingActionButton: isPartner && current != null
          ? FloatingActionButton.extended(
              onPressed: blocker == null
                  ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AmendmentProposalScreen()))
                  : () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(blocker))),
              backgroundColor: blocker == null ? AppColors.gold : AppColors.navySurface,
              foregroundColor: blocker == null ? AppColors.navyDark : AppColors.textMuted,
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('اقتراح تعديل'),
            )
          : null,
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 90),
          children: [
            if (blocker != null && current != null && isPartner)
              StateBanner(color: AppColors.warning, icon: Icons.lock_clock_rounded, text: blocker),
            if (versions.isEmpty || current == null && versions.every((v) => v.version == 1))
              const StateView.empty(
                icon: Icons.history_rounded,
                title: 'لا توجد إصدارات معتمدة بعد',
                message: 'يظهر الإصدار 1 هنا بعد اعتماد عقد التأسيس وتوقيعه. بعدها يمكن اقتراح التعديلات كإصدارات جديدة.',
              ),
            for (var i = 0; i < versions.length; i++)
              if (versions[i].status == SessionStatus.completed || versions[i].isAmendment)
                _VersionTile(
                  s: versions[i],
                  previous: st.sessions.where((x) => x.id == versions[i].amends).firstOrNull,
                  last: i == versions.length - 1,
                ),
          ],
        ),
      ),
    );
  }
}

class _VersionTile extends StatelessWidget {
  final ContractSession s;
  final ContractSession? previous;
  final bool last;
  const _VersionTile({required this.s, required this.previous, required this.last});

  @override
  Widget build(BuildContext context) {
    final st = context.read<ContractState>();
    final cs = context.read<CompanyState>();
    final (gs, label) = versionState(s);
    final isCurrent = gs == GovStatus.approved;
    final signers = st.signersOf(s);
    final signed = signers.where((p) => s.signOffs[p.id] != null && st.signOffValid(s, s.signOffs[p.id]!)).length;
    final proposer = cs.current?.members.where((m) => m.id == s.proposedBy).firstOrNull?.name;
    final color = isCurrent ? AppColors.gold : AppColors.divider;

    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 34,
          child: Column(children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isCurrent ? AppColors.gold : AppColors.navySurface,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 1.5),
              ),
              child: Text('${s.version}',
                  style: TextStyle(
                      color: isCurrent ? AppColors.navyDark : AppColors.textSecondary, fontWeight: FontWeight.w900)),
            ),
            if (!last) Expanded(child: Container(width: 1.5, color: AppColors.divider)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Material(
              color: AppColors.navySurface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16), side: BorderSide(color: color, width: isCurrent ? 1.5 : 1)),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => openVersion(context, s),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text('الإصدار ${s.version} · ${s.changeType.label}',
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
                      ),
                      StatusBadge(gs, overrideLabel: label, dense: true),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                      s.completedAt != null
                          ? 'ساري من ${_dt.format(s.completedAt!.toLocal())}'
                              '${s.archivedAt == null ? '' : ' حتى ${_dt.format(s.archivedAt!.toLocal())}'}'
                          : 'أُنشئ ${_dt.format(s.createdAt.toLocal())}${proposer == null ? '' : ' · اقترحه $proposer'}',
                      style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    if (s.changeSummary != null) ...[
                      const SizedBox(height: 6),
                      Text(s.changeSummary!,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5, height: 1.6)),
                    ],
                    const SizedBox(height: 8),
                    Wrap(spacing: 14, runSpacing: 4, children: [
                      _meta(Icons.draw_rounded, 'التواقيع $signed من ${signers.length}'),
                      if (s.contentHash != null) _meta(Icons.lock_rounded, 'مرجع السلامة ${s.contentHash!.substring(0, 12)}…'),
                      if (s.disputeRef != null) _meta(Icons.gavel_rounded, 'ناتج عن نزاع'),
                    ]),
                    if (previous != null) ...[
                      const SizedBox(height: 6),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: TextButton.icon(
                          onPressed: () => Navigator.push(context,
                              MaterialPageRoute(builder: (_) => VersionCompareScreen(fromId: previous!.id, toId: s.id))),
                          icon: const Icon(Icons.compare_arrows_rounded, size: 18),
                          label: Text('مقارنة بالإصدار ${previous!.version}'),
                        ),
                      ),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _meta(IconData i, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(i, size: 14, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Flexible(
            child: Text(t,
                overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textMuted, fontSize: 11.5))),
      ]);
}

/// P14_Versions_Compare: الفرق بين إصدارين. جنباً إلى جنب على الشاشات العريضة، ومتتابعاً على الجوال.
class VersionCompareScreen extends StatefulWidget {
  final String fromId;
  final String toId;
  const VersionCompareScreen({super.key, required this.fromId, required this.toId});

  @override
  State<VersionCompareScreen> createState() => _VersionCompareScreenState();
}

class _VersionCompareScreenState extends State<VersionCompareScreen> {
  late String _from = widget.fromId;
  late String _to = widget.toId;

  @override
  Widget build(BuildContext context) {
    final st = context.watch<ContractState>();
    ContractSession? find(String id) => st.sessions.where((x) => x.id == id).firstOrNull;
    final a = find(_from), b = find(_to);
    if (a == null || b == null) return const Scaffold(body: StateView.empty(title: 'الإصدار غير متاح', message: ''));
    final all = st.versionsFor(a.companyId).where((s) => s.status == SessionStatus.completed || s.isAmendment).toList();
    final diff = st.compare(a, b);
    final wide = context.screenSize != ScreenSize.phone;

    DropdownButton<String> pick(String value, ValueChanged<String> on) => DropdownButton<String>(
          value: value,
          dropdownColor: AppColors.navySurface,
          underline: const SizedBox.shrink(),
          items: [for (final s in all) DropdownMenuItem(value: s.id, child: Text('الإصدار ${s.version}'))],
          onChanged: (v) => setState(() => on(v!)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('مقارنة الإصدارات')),
      body: ContentWidth(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
          children: [
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
              pick(_from, (v) => _from = v),
              const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.arrow_back_rounded, color: AppColors.gold)),
              pick(_to, (v) => _to = v),
            ]),
            const SizedBox(height: 10),
            if (diff.isEmpty)
              const StateView.empty(
                  icon: Icons.check_circle_outline_rounded, title: 'لا فروق', message: 'الإصداران متطابقان في البنود والحصص.')
            else
              Text('${diff.length} فروق بين الإصدار ${a.version} والإصدار ${b.version}',
                  style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            for (final d in diff)
              GovCard(
                title: d.title,
                icon: Icons.difference_rounded,
                child: wide
                    ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: _side('الإصدار ${a.version}', d.before, d.textBefore, AppColors.danger)),
                        const SizedBox(width: 12),
                        Expanded(child: _side('الإصدار ${b.version}', d.after, d.textAfter, AppColors.success)),
                      ])
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _side('الإصدار ${a.version}', d.before, d.textBefore, AppColors.danger),
                        const SizedBox(height: 8),
                        _side('الإصدار ${b.version}', d.after, d.textAfter, AppColors.success),
                      ]),
              ),
          ].expand((w) => [w, if (w is GovCard) const SizedBox(height: 10)]).toList(),
        ),
      ),
    );
  }

  Widget _side(String label, String value, String? text, Color c) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withValues(alpha: 0.35)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(color: c, fontSize: 11.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w800)),
          if (text != null) ...[
            const SizedBox(height: 6),
            Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.6)),
          ],
        ]),
      );
}
